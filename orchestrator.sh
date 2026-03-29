#!/bin/bash
set -euo pipefail

# Bash 4+ requis pour declare -A (associative arrays)
if ((BASH_VERSINFO[0] < 4)); then
  echo "ERREUR: bash 4+ requis (actuel: $BASH_VERSION). Sur macOS: brew install bash" >&2
  exit 1
fi

# ============================================================
# Agent Autonome Claude — Orchestrateur principal
# ============================================================
#
# Usage :
#   ./orchestrator.sh    — lance l'agent autonome (BRIEF.md requis)
#
# Ce script doit être lancé depuis un workspace créé par orc agent new.
# Il pilote Claude en boucle pour développer les features de la roadmap.
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Config : cherche d'abord dans .orc/, puis à la racine (rétrocompat)
if [ -f "$SCRIPT_DIR/.orc/config.sh" ]; then
  source "$SCRIPT_DIR/.orc/config.sh"
elif [ -f "$SCRIPT_DIR/config.sh" ]; then
  source "$SCRIPT_DIR/config.sh"
else
  echo "ERREUR : config.sh introuvable (ni .orc/config.sh ni config.sh)" >&2
  exit 1
fi

# Convertir les chemins relatifs en absolus
PROJECT_DIR="$(cd "$SCRIPT_DIR" && realpath "$PROJECT_DIR" 2>/dev/null || echo "$SCRIPT_DIR/$PROJECT_DIR")"
LOG_DIR="$(cd "$SCRIPT_DIR" && realpath "$LOG_DIR" 2>/dev/null || echo "$SCRIPT_DIR/$LOG_DIR")"

# === COULEURS ===
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# === COMPTEURS ===
FEATURE_COUNT=0
EPIC_FEATURE_COUNT=0
TOTAL_FAILURES=0
EVOLVE_CYCLES=0
AI_ROADMAP_ADDS=0
STATE_FILE="$SCRIPT_DIR/.orc/state.json"

# === TRACKING ENRICHI ===
CURRENT_FEATURE=""
CURRENT_PHASE=""
PHASE_STARTED_AT=""
RUN_STARTED_AT=$(date -Iseconds)
FEATURES_TIMELINE="[]"
LAST_FUNCTIONAL_CHECK="null"
RUN_STATUS="running"
RUN_ENDED_AT=""

# === STATE MACHINE ===
# Pilote le workflow global. Transitions valides :
#   init → bootstrap → research → strategy → features → evolve → features (cycle)
#   evolve → post-project → done
#   Tout état → crashed/stopped/budget_exceeded (via cleanup/signaux)
WORKFLOW_PHASE="init"

# Transition de la state machine avec validation
workflow_transition() {
  local target="$1"
  local valid=false
  case "$WORKFLOW_PHASE→$target" in
    init→bootstrap|init→research|init→strategy|init→features) valid=true ;;  # premier lancement
    crashed→bootstrap|crashed→research|crashed→strategy|crashed→features|crashed→post-project) valid=true ;;  # reprise après crash
    stopped→bootstrap|stopped→research|stopped→strategy|stopped→features|stopped→post-project) valid=true ;;  # reprise après arrêt
    budget_exceeded→bootstrap|budget_exceeded→research|budget_exceeded→strategy|budget_exceeded→features) valid=true ;;  # reprise après budget
    done→bootstrap|done→research|done→strategy|done→features) valid=true ;;  # relancement volontaire
    bootstrap→research|bootstrap→strategy|bootstrap→features) valid=true ;;
    research→strategy|research→features) valid=true ;;
    strategy→features) valid=true ;;
    # Self-transitions (reprise dans le même état après crash/restart)
    bootstrap→bootstrap|research→research|strategy→strategy|features→features|evolve→evolve) valid=true ;;
    features→evolve|features→post-project) valid=true ;;
    evolve→features|evolve→post-project|evolve→alignment_pending) valid=true ;;
    alignment_pending→features|alignment_pending→stopped) valid=true ;;
    post-project→done) valid=true ;;
    *→crashed|*→stopped|*→budget_exceeded) valid=true ;;  # sorties d'urgence
  esac
  if [ "$valid" = true ]; then
    log INFO "Workflow: $WORKFLOW_PHASE → $target"
    WORKFLOW_PHASE="$target"
    save_state
  else
    log WARN "Transition workflow invalide : $WORKFLOW_PHASE → $target (ignorée)"
  fi
}

# === TRACKING TOKENS ===
TOKENS_FILE="$SCRIPT_DIR/.orc/tokens.json"
TOTAL_INPUT_TOKENS=0
TOTAL_OUTPUT_TOKENS=0
TOTAL_COST_USD=0

# Pricing dynamique par modèle (USD par token)
# Clé = préfixe du modèle, valeur = "input_cost:output_cost"
declare -A MODEL_PRICING=(
  ["claude-opus-4"]="0.000015:0.000075"
  ["claude-sonnet-4"]="0.000003:0.000015"
  ["claude-haiku-4"]="0.0000008:0.000004"
)
# Fallback si modèle inconnu (tarif Sonnet = raisonnable par défaut)
DEFAULT_COST_PER_INPUT_TOKEN=0.000003
DEFAULT_COST_PER_OUTPUT_TOKEN=0.000015

# Résoudre le pricing pour un modèle donné
# Usage: get_model_pricing "claude-sonnet-4-6" → set COST_PER_INPUT_TOKEN et COST_PER_OUTPUT_TOKEN
# Note: itère les préfixes du plus long au plus court pour éviter les matchs ambigus
get_model_pricing() {
  local model="${1:-}"
  COST_PER_INPUT_TOKEN="$DEFAULT_COST_PER_INPUT_TOKEN"
  COST_PER_OUTPUT_TOKEN="$DEFAULT_COST_PER_OUTPUT_TOKEN"
  # Trier les préfixes par longueur décroissante (le plus spécifique matche d'abord)
  local sorted_prefixes
  sorted_prefixes=$(for p in "${!MODEL_PRICING[@]}"; do echo "$p"; done | awk '{print length, $0}' | sort -rn | cut -d' ' -f2-)
  while IFS= read -r prefix; do
    if [[ "$model" == "$prefix"* ]]; then
      COST_PER_INPUT_TOKEN="${MODEL_PRICING[$prefix]%%:*}"
      COST_PER_OUTPUT_TOKEN="${MODEL_PRICING[$prefix]##*:}"
      return 0
    fi
  done <<< "$sorted_prefixes"
  # Aucun préfixe connu n'a matché — warning pour visibilité
  if [ -n "$model" ]; then
    log WARN "Modèle '$model' inconnu dans MODEL_PRICING — fallback tarif Sonnet (\$${DEFAULT_COST_PER_INPUT_TOKEN}/\$${DEFAULT_COST_PER_OUTPUT_TOKEN})"
  fi
}

# Phases légères qui utilisent CLAUDE_MODEL_LIGHT si disponible
# Phases non-code : pas besoin du modèle principal (text, recherche web, décision)
# Phases légères (modèle léger). Critic + tech-debt utilisent le modèle PRINCIPAL
LIGHT_PHASES="plan acceptance reflection reflect self-improve meta-retro quality strategy research-initial research-epic evolve alignment user-docs"

# Phases fortes qui utilisent CLAUDE_MODEL_STRONG si disponible
# Réflexion profonde : challenger (enrichissement produit pré-implémentation)
STRONG_PHASES="challenger product-review"

# Résoudre le modèle effectif pour une phase donnée
# Hiérarchie : STRONG (challenger) > CLAUDE_MODEL (implement, fix) > LIGHT (plan, reflect)
# Usage: resolve_model "challenger" → affiche le modèle à utiliser
resolve_model() {
  local phase="$1"
  # Tier 1 : modèle fort (challenger, réflexion profonde)
  if [ -n "${CLAUDE_MODEL_STRONG:-}" ] && [[ " $STRONG_PHASES " == *" $phase "* ]]; then
    echo "$CLAUDE_MODEL_STRONG"
  # Tier 2 : modèle léger (plan, reflect, etc.)
  elif [ -n "${CLAUDE_MODEL_LIGHT:-}" ] && [[ " $LIGHT_PHASES " == *" $phase "* ]]; then
    echo "$CLAUDE_MODEL_LIGHT"
  # Tier 3 : modèle principal (implement, fix, critic)
  else
    echo "${CLAUDE_MODEL:-}"
  fi
}

# === LOCKFILE ===
LOCKFILE="$SCRIPT_DIR/.orc/.lock"

# === CLEANUP & SIGNAL HANDLING ===
CLAUDE_PID=""
TMP_JSON=""

cleanup() {
  # Tuer le process Claude en cours si présent
  if [ -n "$CLAUDE_PID" ] && kill -0 "$CLAUDE_PID" 2>/dev/null; then
    log WARN "Arrêt en cours — kill Claude (PID $CLAUDE_PID)..."
    kill "$CLAUDE_PID" 2>/dev/null || true
    wait "$CLAUDE_PID" 2>/dev/null || true
  fi
  # Tuer le challenger async (lookahead) si en cours
  if [ -n "${CHALLENGER_ASYNC_PID:-}" ] && kill -0 "$CHALLENGER_ASYNC_PID" 2>/dev/null; then
    log WARN "Arrêt en cours — kill challenger async (PID $CHALLENGER_ASYNC_PID)..."
    kill "$CHALLENGER_ASYNC_PID" 2>/dev/null || true
    wait "$CHALLENGER_ASYNC_PID" 2>/dev/null || true
  fi
  # Nettoyer le fichier temporaire
  [ -n "$TMP_JSON" ] && rm -f "$TMP_JSON"
  # Marquer le statut si pas déjà fait (= crash ou signal)
  if [ "$RUN_STATUS" = "running" ]; then
    RUN_STATUS="crashed"
    WORKFLOW_PHASE="crashed"
    RUN_ENDED_AT=$(date -Iseconds)
    log ERROR "Run interrompu (crash ou signal)."
    # Diagnostic : écrire les dernières lignes du log pour le status
    write_action_required "Le run a crashé pendant la phase '${CURRENT_PHASE:-inconnue}'" \
      "$(tail -20 "$LOG_DIR/orchestrator.log" 2>/dev/null | grep -v '^\[' | head -10)"
  fi
  # Sauvegarder l'état
  save_state
  # Libérer le lock
  rm -f "$LOCKFILE"
  log INFO "Nettoyage terminé."
}

trap cleanup EXIT INT TERM

# === ACTION REQUIRED ===

# Écrit un fichier .orc/action-required lisible par orc status
write_action_required() {
  local title="$1"
  local details="${2:-}"
  local action_file="$SCRIPT_DIR/.orc/action-required"
  {
    echo "# Action requise"
    echo ""
    echo "**$title**"
    echo ""
    if [ -n "$details" ]; then
      echo '```'
      echo "$details"
      echo '```'
      echo ""
    fi
    echo "Feature : ${CURRENT_FEATURE:-inconnue}"
    echo "Phase : ${CURRENT_PHASE:-inconnue}"
    echo "Date : $(date '+%Y-%m-%d %H:%M:%S')"
  } > "$action_file"
}

# Efface le fichier action-required (appelé au démarrage)
clear_action_required() {
  rm -f "$SCRIPT_DIR/.orc/action-required"
}

# Apprentissage adaptatif : calcule un max_turns optimal basé sur l'historique
# Utilise le p75 des turns passés + 30% de marge, avec un minimum plancher
# Usage: adaptive_max_turns "implement" 50  → affiche le max_turns recommandé
adaptive_max_turns() {
  local phase="$1"
  local default_max="$2"

  # Besoin de jq et du fichier tokens
  if ! command -v jq &>/dev/null || [ ! -f "$TOKENS_FILE" ]; then
    echo "$default_max"
    return
  fi

  # Extraire l'historique des turns pour cette phase
  local turns_json
  turns_json=$(jq -r ".by_phase[\"$phase\"].turns_history // []" "$TOKENS_FILE" 2>/dev/null)

  # Filtrer les 0 (phases tronquées par max_turns, non significatives)
  local clean_json
  clean_json=$(echo "$turns_json" | jq '[.[] | select(. > 0)]' 2>/dev/null || echo "[]")

  # Besoin d'au moins 5 échantillons valides pour adapter
  local count
  count=$(echo "$clean_json" | jq 'length' 2>/dev/null || echo "0")
  count="${count:-0}"
  if ! [[ "$count" =~ ^[0-9]+$ ]] || [ "$count" -lt 5 ]; then
    echo "$default_max"
    return
  fi

  # Calculer le p75 (75ème percentile) + 30% de marge
  local adaptive
  adaptive=$(echo "$clean_json" | jq '
    sort |
    ((length - 1) * 0.75 | floor) as $idx |
    .[$idx] * 1.3 |
    ceil |
    if . < 5 then 5 else . end
  ' 2>/dev/null || echo "$default_max")
  adaptive="${adaptive:-$default_max}"

  # Ne jamais dépasser le défaut (garde-fou), ne jamais descendre sous 5
  if ! [[ "$adaptive" =~ ^[0-9]+$ ]]; then
    echo "$default_max"
  elif [ "$adaptive" -gt "$default_max" ]; then
    echo "$default_max"
  elif [ "$adaptive" -lt 5 ]; then
    echo "5"
  else
    echo "$adaptive"
  fi
}

# === FONCTIONS UTILITAIRES ===

# Troncation intelligente : garde le début et la fin d'un output
# pour ne pas perdre le message d'erreur initial (souvent en tête)
# Usage: smart_truncate "$output" 3000  → 500 premiers chars + ... + 2500 derniers chars
smart_truncate() {
  local text="$1"
  local max_chars="${2:-3000}"
  local len=${#text}
  if [ "$len" -le "$max_chars" ]; then
    echo "$text"
    return
  fi
  local head_chars=$(( max_chars / 6 ))       # ~500 chars du début
  local tail_chars=$(( max_chars - head_chars - 20 ))  # le reste de la fin
  echo "${text:0:$head_chars}
... (tronqué: ${len} chars, début+fin conservés) ...
${text: -$tail_chars}"
}

log() {
  local level="$1" msg="$2"
  local timestamp
  timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  case "$level" in
    INFO)  printf "${CYAN}[%s]${NC} ${GREEN}[INFO]${NC}  %s\n" "$timestamp" "$msg" ;;
    WARN)  printf "${CYAN}[%s]${NC} ${YELLOW}[WARN]${NC}  %s\n" "$timestamp" "$msg" ;;
    ERROR) printf "${CYAN}[%s]${NC} ${RED}[ERROR]${NC} %s\n" "$timestamp" "$msg" ;;
    PHASE) printf "\n${CYAN}[%s]${NC} ${BLUE}[═══════════════]${NC} %s\n" "$timestamp" "$msg" ;;
    COST)  printf "${CYAN}[%s]${NC} ${YELLOW}[\$]${NC}     %s\n" "$timestamp" "$msg" ;;
  esac
  mkdir -p "$LOG_DIR"
  printf "[%s] [%s] %s\n" "$timestamp" "$level" "$msg" >> "$LOG_DIR/orchestrator.log"
}

# Sauvegarde l'état des compteurs (survit à exec et crash)
save_state() {
  mkdir -p "$(dirname "$STATE_FILE")"
  if command -v jq &> /dev/null; then
    # Version enrichie avec tracking complet
    local timeline_json="$FEATURES_TIMELINE"
    [ -z "$timeline_json" ] && timeline_json="[]"
    local current_feat_safe
    current_feat_safe=$(printf '%s' "$CURRENT_FEATURE" | jq -Rs '.' 2>/dev/null || echo '""')
    local current_phase_safe
    current_phase_safe=$(printf '%s' "$CURRENT_PHASE" | jq -Rs '.' 2>/dev/null || echo '""')
    jq -n \
      --argjson feature_count "$FEATURE_COUNT" \
      --argjson epic_feature_count "$EPIC_FEATURE_COUNT" \
      --argjson total_failures "$TOTAL_FAILURES" \
      --argjson evolve_cycles "$EVOLVE_CYCLES" \
      --argjson ai_roadmap_adds "$AI_ROADMAP_ADDS" \
      --argjson current_feature "$current_feat_safe" \
      --argjson current_phase "$current_phase_safe" \
      --arg phase_started_at "${PHASE_STARTED_AT:-}" \
      --arg run_started_at "${RUN_STARTED_AT:-}" \
      --argjson features_timeline "$timeline_json" \
      --argjson functional_check_passed "${LAST_FUNCTIONAL_CHECK:-null}" \
      --arg run_status "${RUN_STATUS:-running}" \
      --arg run_ended_at "${RUN_ENDED_AT:-}" \
      --arg workflow_phase "${WORKFLOW_PHASE:-init}" \
      '{
        feature_count: $feature_count,
        epic_feature_count: $epic_feature_count,
        total_failures: $total_failures,
        evolve_cycles: $evolve_cycles,
        ai_roadmap_adds: $ai_roadmap_adds,
        current_feature: $current_feature,
        current_phase: $current_phase,
        phase_started_at: $phase_started_at,
        run_started_at: $run_started_at,
        features_timeline: $features_timeline,
        functional_check_passed: $functional_check_passed,
        run_status: $run_status,
        run_ended_at: $run_ended_at,
        workflow_phase: $workflow_phase
      }' > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
  else
    # Fallback sans jq — format simple
    cat > "$STATE_FILE" << STATEEOF
{"feature_count":$FEATURE_COUNT,"epic_feature_count":$EPIC_FEATURE_COUNT,"total_failures":$TOTAL_FAILURES,"evolve_cycles":$EVOLVE_CYCLES,"ai_roadmap_adds":$AI_ROADMAP_ADDS,"run_status":"${RUN_STATUS:-running}","run_ended_at":"${RUN_ENDED_AT:-}","workflow_phase":"${WORKFLOW_PHASE:-init}"}
STATEEOF
  fi
}

# Restaure l'état si disponible
restore_state() {
  if command -v jq &> /dev/null && [ -f "$STATE_FILE" ]; then
    FEATURE_COUNT=$(jq -r '.feature_count // 0' "$STATE_FILE")
    EPIC_FEATURE_COUNT=$(jq -r '.epic_feature_count // 0' "$STATE_FILE")
    TOTAL_FAILURES=$(jq -r '.total_failures // 0' "$STATE_FILE")
    EVOLVE_CYCLES=$(jq -r '.evolve_cycles // 0' "$STATE_FILE")
    AI_ROADMAP_ADDS=$(jq -r '.ai_roadmap_adds // 0' "$STATE_FILE")
    # Restaurer le tracking enrichi
    CURRENT_FEATURE=$(jq -r '.current_feature // ""' "$STATE_FILE")
    CURRENT_PHASE=$(jq -r '.current_phase // ""' "$STATE_FILE")
    PHASE_STARTED_AT=$(jq -r '.phase_started_at // ""' "$STATE_FILE")
    local saved_run_started
    saved_run_started=$(jq -r '.run_started_at // ""' "$STATE_FILE")
    [ -n "$saved_run_started" ] && RUN_STARTED_AT="$saved_run_started"
    FEATURES_TIMELINE=$(jq -c '.features_timeline // []' "$STATE_FILE")
    # Restaurer la state machine
    local saved_workflow
    saved_workflow=$(jq -r '.workflow_phase // "init"' "$STATE_FILE")
    [ -n "$saved_workflow" ] && WORKFLOW_PHASE="$saved_workflow"
    log INFO "État restauré : features=$FEATURE_COUNT, échecs=$TOTAL_FAILURES, evolve_cycles=$EVOLVE_CYCLES, workflow=$WORKFLOW_PHASE"
  fi
}

# Met à jour le tracking de phase courante
update_phase_tracking() {
  local phase="$1"
  local feature="${2:-}"
  CURRENT_PHASE="$phase"
  PHASE_STARTED_AT=$(date -Iseconds)
  if [ -n "$feature" ]; then CURRENT_FEATURE="$feature"; fi
}

# Ajoute une entrée à la timeline des features
timeline_add() {
  local name="$1" status="$2" fix_attempts="${3:-0}"
  local ts
  ts=$(date -Iseconds)
  if command -v jq &> /dev/null; then
    FEATURES_TIMELINE=$(echo "$FEATURES_TIMELINE" | jq -c \
      --arg name "$name" --arg status "$status" --arg ts "$ts" --argjson fix "$fix_attempts" \
      '. + [{"name": $name, "started": $ts, "status": $status, "fix_attempts": $fix}]')
  fi
}

# Met à jour le dernier élément de la timeline
timeline_update_last() {
  local status="$1" fix_attempts="${2:-0}"
  local ts
  ts=$(date -Iseconds)
  if command -v jq &> /dev/null; then
    FEATURES_TIMELINE=$(echo "$FEATURES_TIMELINE" | jq -c \
      --arg status "$status" --arg ts "$ts" --argjson fix "$fix_attempts" \
      'if length > 0 then .[-1].ended = $ts | .[-1].status = $status | .[-1].fix_attempts = $fix else . end')
  fi
}

# Marque une feature comme cochée dans ROADMAP.md (fiable, sed-based) — LEGACY
mark_feature_done_bash() {
  local feature_name="$1"
  local roadmap="$PROJECT_DIR/.orc/ROADMAP.md"
  [ -f "$roadmap" ] || return 0
  # Échappe les caractères spéciaux regex dans le nom de la feature
  local escaped_name
  escaped_name=$(printf '%s' "$feature_name" | sed 's/[.[\*^$()+?{|\\]/\\&/g')
  # Remplacer la première occurrence unchecked contenant ce nom
  sed -i "0,/^\- \[ \] ${escaped_name}/s/^\- \[ \] \(${escaped_name}\)/- [x] \1/" "$roadmap" 2>/dev/null || true
  log INFO "Roadmap cochée (bash) : $feature_name"
}

# ============================================================
# KANBAN — Gestion des tickets projet
# ============================================================

# Initialise la structure kanban
init_kanban() {
  mkdir -p "$PROJECT_DIR/.orc/roadmap"/{backlog,todo,in-progress,done}
}

# Lit un champ du frontmatter YAML d'un ticket
_ticket_field() {
  local file="$1" field="$2"
  sed -n '/^---$/,/^---$/p' "$file" 2>/dev/null | grep "^${field}:" | head -1 | sed "s/^${field}: *//;s/^\"//;s/\"$//"
}

# Lit le titre d'un ticket
ticket_title() {
  _ticket_field "$1" "title"
}

# Lit le contenu markdown d'un ticket (après le frontmatter)
ticket_context() {
  awk 'BEGIN{c=0} /^---$/{c++; next} c>=2{print}' "$1" 2>/dev/null
}

# Retourne le prochain ticket à implémenter (chemin du fichier), trié par priorité P0→P3 puis ID
next_ticket() {
  local todo_dir="$PROJECT_DIR/.orc/roadmap/todo"
  [ -d "$todo_dir" ] || return 0
  for p in P0 P1 P2 P3; do
    for f in "$todo_dir"/*.md; do
      [ -f "$f" ] || continue
      local prio
      prio=$(_ticket_field "$f" "priority")
      if [ "$prio" = "$p" ]; then
        echo "$f"
        return 0
      fi
    done
  done
}

# Peek le Nième ticket todo (pour challenger lookahead)
peek_ticket() {
  local n="${1:-1}" count=0
  local todo_dir="$PROJECT_DIR/.orc/roadmap/todo"
  [ -d "$todo_dir" ] || return 0
  for p in P0 P1 P2 P3; do
    for f in "$todo_dir"/*.md; do
      [ -f "$f" ] || continue
      local prio
      prio=$(_ticket_field "$f" "priority")
      if [ "$prio" = "$p" ]; then
        count=$((count + 1))
        if [ "$count" -eq "$n" ]; then
          ticket_title "$f"
          return 0
        fi
      fi
    done
  done
}

# Déplace un ticket vers un statut
move_ticket() {
  local ticket_file="$1" target_status="$2"
  local target_dir="$PROJECT_DIR/.orc/roadmap/$target_status"
  mkdir -p "$target_dir"
  mv "$ticket_file" "$target_dir/$(basename "$ticket_file")"
}

# Vérifie s'il reste des tickets todo
has_todo_tickets() {
  local todo_dir="$PROJECT_DIR/.orc/roadmap/todo"
  [ -d "$todo_dir" ] || return 1
  for f in "$todo_dir"/*.md; do
    [ -f "$f" ] && return 0
  done
  return 1
}

# Compte les tickets todo
count_todo_tickets() {
  local count=0
  local todo_dir="$PROJECT_DIR/.orc/roadmap/todo"
  [ -d "$todo_dir" ] || { echo 0; return; }
  for f in "$todo_dir"/*.md; do
    [ -f "$f" ] && count=$((count + 1))
  done
  echo "$count"
}

# Prochain ID disponible
next_ticket_id() {
  local max=0
  for f in "$PROJECT_DIR/.orc/roadmap"/*/*.md; do
    [ -f "$f" ] || continue
    local num
    num=$(basename "$f" | grep -o '^[0-9]*' || echo 0)
    [ "$num" -gt "$max" ] && max="$num"
  done
  echo $((max + 1))
}

# Génère un slug depuis un titre
_ticket_slug() {
  echo "$1" | sed 's/[^a-zA-Z0-9]/-/g' | tr '[:upper:]' '[:lower:]' | sed 's/^-*//;s/-*$//;s/--*/-/g' | head -c 40
}

# Régénère la vue ROADMAP.md (compat dashboard/status)
regenerate_roadmap_view() {
  local roadmap="$PROJECT_DIR/.orc/ROADMAP.md"
  local project_name="${PROJECT_NAME:-$(basename "$PROJECT_DIR")}"

  {
    echo "# ROADMAP — $project_name"
    echo ""

    # In-progress
    for f in "$PROJECT_DIR/.orc/roadmap/in-progress"/*.md; do
      [ -f "$f" ] || continue
      echo "- [ ] $(ticket_title "$f")"
    done

    # Todo (trié par priorité)
    for p in P0 P1 P2 P3; do
      for f in "$PROJECT_DIR/.orc/roadmap/todo"/*.md; do
        [ -f "$f" ] || continue
        local prio
        prio=$(_ticket_field "$f" "priority")
        [ "$prio" = "$p" ] && echo "- [ ] $(ticket_title "$f")"
      done
    done

    # Backlog
    for f in "$PROJECT_DIR/.orc/roadmap/backlog"/*.md; do
      [ -f "$f" ] || continue
      echo "- [ ] $(ticket_title "$f")"
    done

    # Done
    for f in "$PROJECT_DIR/.orc/roadmap/done"/*.md; do
      [ -f "$f" ] || continue
      echo "- [x] $(ticket_title "$f")"
    done
  } > "$roadmap"
}

# Détecte la dérive directionnelle : si >60% des tickets récents sont dans le même epic
# Retourne un warning textuel à injecter dans le prompt, ou rien si OK
check_direction_drift() {
  local epic_counts=""
  local total=0
  local max_count=0
  local max_epic=""

  # Compter les epics des tickets done + todo (les 20 derniers)
  for dir in "$PROJECT_DIR/.orc/roadmap/done" "$PROJECT_DIR/.orc/roadmap/todo"; do
    [ -d "$dir" ] || continue
    for f in "$dir"/*.md; do
      [ -f "$f" ] || continue
      local epic
      epic=$(_ticket_field "$f" "epic")
      [ -z "$epic" ] && epic="sans-epic"
      epic_counts="$epic_counts$epic
"
      total=$((total + 1))
    done
  done

  [ "$total" -lt 5 ] && return 0  # Pas assez de données

  # Trouver l'epic le plus fréquent
  max_epic=$(echo "$epic_counts" | sort | uniq -c | sort -rn | head -1 | awk '{print $2}')
  max_count=$(echo "$epic_counts" | grep -c "^${max_epic}$" 2>/dev/null || echo 0)

  local ratio=$((max_count * 100 / total))
  if [ "$ratio" -ge 60 ]; then
    log WARN "Derive thematique detectee : $ratio% des tickets dans l'epic '$max_epic'"
    echo "
ATTENTION — DERIVE THEMATIQUE DETECTEE :
$ratio% des tickets recents ($max_count/$total) sont dans l'epic '$max_epic'.
Tu DOIS diversifier les propositions. Explore d'autres domaines du produit.
Assure-toi que les prochains tickets couvrent au moins 3 epics differents."
  fi
}

# Lance le pipeline auto-brainstorm (recherche + propositions + rédaction)
# Appelé par la phase evolve quand score < 24/30
run_auto_brainstorm() {
  local cycle="$1"
  local max_tickets="${MAX_AUTO_BRAINSTORM_TICKETS:-10}"

  log PHASE "AUTO-BRAINSTORM — Cycle $cycle (max $max_tickets tickets)"

  # Collecter le contexte
  local brief_content="" index_content="" maturity_content=""
  local done_tickets="" todo_tickets="" backlog_tickets=""
  local research_content="" alignment_content="" drift_warning=""

  [ -f "$PROJECT_DIR/.orc/BRIEF.md" ] && brief_content=$(head -100 "$PROJECT_DIR/.orc/BRIEF.md")
  [ -f "$PROJECT_DIR/.orc/codebase/INDEX.md" ] && index_content=$(cat "$PROJECT_DIR/.orc/codebase/INDEX.md")

  # Dernier score de maturité
  local latest_maturity
  latest_maturity=$(ls -t "$PROJECT_DIR/.orc/logs"/maturity-score*.md 2>/dev/null | head -1)
  [ -f "$latest_maturity" ] && maturity_content=$(cat "$latest_maturity")

  # Tickets par statut
  for f in "$PROJECT_DIR/.orc/roadmap/done"/*.md; do
    [ -f "$f" ] || continue
    done_tickets="$done_tickets  #$(basename "$f" | grep -o '^[0-9]*') $(ticket_title "$f")
"
  done
  for f in "$PROJECT_DIR/.orc/roadmap/todo"/*.md; do
    [ -f "$f" ] || continue
    todo_tickets="$todo_tickets  #$(basename "$f" | grep -o '^[0-9]*') $(ticket_title "$f")
"
  done
  for f in "$PROJECT_DIR/.orc/roadmap/backlog"/*.md; do
    [ -f "$f" ] || continue
    backlog_tickets="$backlog_tickets  #$(basename "$f" | grep -o '^[0-9]*') $(ticket_title "$f")
"
  done

  # Recherche existante
  [ -f "$PROJECT_DIR/.orc/research/INDEX.md" ] && research_content=$(head -60 "$PROJECT_DIR/.orc/research/INDEX.md")

  # Dernières réponses d'alignement
  local latest_alignment
  latest_alignment=$(ls -t "$PROJECT_DIR/.orc/logs"/alignment-response-*.md 2>/dev/null | head -1)
  [ -f "$latest_alignment" ] && alignment_content=$(cat "$latest_alignment")

  # Détection de dérive
  drift_warning=$(check_direction_drift)

  # Construire le prompt
  local orc_dir
  orc_dir=$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")")
  local prompt
  prompt=$(cat "$orc_dir/phases/auto-brainstorm.md" 2>/dev/null || echo "")

  if [ -z "$prompt" ]; then
    log WARN "Prompt auto-brainstorm.md non trouvé — fallback evolve classique."
    return 1
  fi

  # Substituer les placeholders
  prompt="${prompt//\{\{CYCLE\}\}/$cycle}"
  prompt="${prompt//\{\{PROJECT_NAME\}\}/${PROJECT_NAME:-$(basename "$PROJECT_DIR")}}"
  prompt="${prompt//\{\{MAX_TICKETS\}\}/$max_tickets}"
  prompt="${prompt//\{\{PROJECT_DIR\}\}/$PROJECT_DIR}"
  prompt="${prompt//\{\{BRIEF\}\}/${brief_content:-[Brief non disponible]}}"
  prompt="${prompt//\{\{INDEX\}\}/${index_content:-[Index non disponible]}}"
  prompt="${prompt//\{\{MATURITY_SCORE\}\}/${maturity_content:-[Score non disponible]}}"
  prompt="${prompt//\{\{DONE_TICKETS\}\}/${done_tickets:-[Aucun]}}"
  prompt="${prompt//\{\{TODO_TICKETS\}\}/${todo_tickets:-[Aucun]}}"
  prompt="${prompt//\{\{BACKLOG_TICKETS\}\}/${backlog_tickets:-[Aucun]}}"
  prompt="${prompt//\{\{RESEARCH\}\}/${research_content:-[Pas de recherche]}}"
  prompt="${prompt//\{\{ALIGNMENT_RESPONSE\}\}/${alignment_content:-[Aucune reponse d alignement]}}"
  prompt="${prompt//\{\{DRIFT_WARNING\}\}/${drift_warning}}"

  # Invocation unique : recherche + propositions + auto-sélection + rédaction
  update_phase_tracking "auto-brainstorm" "cycle-$cycle"
  run_claude "$prompt" 25 "$LOG_DIR/auto-brainstorm-$cycle.log" "auto-brainstorm" "cycle-$cycle" || {
    log WARN "Auto-brainstorm échoué — fallback evolve classique."
    return 1
  }

  # Régénérer la vue
  regenerate_roadmap_view
  log INFO "Auto-brainstorm terminé — tickets créés dans .orc/roadmap/todo/"
  return 0
}

# Met à jour CHANGELOG.md du projet après chaque feature mergée
update_changelog() {
  local feature_name="$1"
  local fix_attempts="${2:-0}"
  local changelog="$PROJECT_DIR/CHANGELOG.md"
  local today
  today=$(date '+%Y-%m-%d')

  # Créer le fichier si absent
  if [ ! -f "$changelog" ]; then
    {
      echo "# Changelog"
      echo ""
      echo "Toutes les modifications notables de ce projet sont documentées ici."
      echo "Généré automatiquement par [ORC](https://github.com/gregoirelacoste/orc)."
      echo ""
    } > "$changelog"
  fi

  # Ajouter l'entrée (insérée après le header, avant les anciennes entrées)
  local entry="- **$today** — $feature_name"
  [ "$fix_attempts" -gt 0 ] && entry="$entry ($fix_attempts fix)"

  # Insérer après la première ligne vide suivant le header
  local tmp_cl
  tmp_cl=$(mktemp)
  awk -v entry="$entry" '
    /^$/ && !inserted && NR > 1 { print; print entry; inserted=1; next }
    { print }
  ' "$changelog" > "$tmp_cl" && mv "$tmp_cl" "$changelog"

  # Commit le changelog avec la feature
  run_in_project "git add CHANGELOG.md 2>/dev/null && git commit --amend --no-edit 2>/dev/null" || true
}

# Preflight checks avant merge — vérifie que le changement est safe
# Retourne 0 si OK, 1 si bloqué
preflight_merge() {
  local feature_name="$1"
  local merge_ok=true
  local max_deletions="${MAX_DELETIONS_PER_FEATURE:-500}"
  local max_files="${MAX_FILES_PER_FEATURE:-30}"

  # 1. Fichiers sensibles modifiés ?
  local sensitive_files
  sensitive_files=$(run_in_project "git diff --name-only main 2>/dev/null" | \
    grep -iE '\.env($|\.)|credentials|\.pem$|\.key$|\.cert$|\.p12$|\.pfx$|secret|password|token\.json|id_rsa|id_ed25519|\.npmrc|\.pypirc|\.htpasswd|service.account' | \
    grep -viE '\.example$|\.sample$|\.template$|\.tsx?$|\.jsx?$|\.py$|\.go$|\.rb$|\.java$|\.rs$' || true)
  if [ -n "$sensitive_files" ]; then
    log ERROR "PREFLIGHT BLOQUÉ : fichiers sensibles modifiés :"
    log ERROR "  $sensitive_files"
    notify "ALERTE : feature '$feature_name' modifie des fichiers sensibles : $sensitive_files"
    merge_ok=false
  fi

  # 2. Suppressions massives ? (seuil configurable, ratio > 3:1 ou suppression pure)
  local diff_stat additions deletions
  diff_stat=$(run_in_project "git diff --stat main 2>/dev/null | tail -1" || echo "")
  additions=$(echo "$diff_stat" | awk '{for(i=1;i<=NF;i++) if($i ~ /insertion/) print $(i-1)}')
  deletions=$(echo "$diff_stat" | awk '{for(i=1;i<=NF;i++) if($i ~ /deletion/) print $(i-1)}')
  additions=${additions:-0}; deletions=${deletions:-0}

  if [ "$deletions" -gt "$max_deletions" ] 2>/dev/null; then
    if [ "$additions" -eq 0 ] 2>/dev/null; then
      # Suppression pure — toujours bloquant
      log ERROR "PREFLIGHT BLOQUÉ : suppression pure ($deletions deletions, 0 additions)"
      merge_ok=false
    else
      local ratio=$(( deletions / additions ))
      if [ "$ratio" -gt 3 ] 2>/dev/null; then
        log ERROR "PREFLIGHT BLOQUÉ : suppressions massives ($deletions deletions, ratio $ratio:1)"
        merge_ok=false
      fi
    fi
    [ "$merge_ok" = false ] && notify "ALERTE : feature '$feature_name' supprime massivement ($deletions lignes)"
  fi

  # 3. Fichiers protégés ? (CI config)
  local protected_modified
  protected_modified=$(run_in_project "git diff --name-only main 2>/dev/null" | \
    grep -iE '\.github/workflows|\.gitlab-ci|Dockerfile|docker-compose' || true)
  if [ -n "$protected_modified" ]; then
    log WARN "PREFLIGHT WARNING : fichiers CI/infra modifiés : $protected_modified"
  fi

  # 4. Trop de fichiers modifiés ?
  local files_count
  files_count=$(run_in_project "git diff --name-only main 2>/dev/null | wc -l" || echo "0")
  if [ "$files_count" -gt "$max_files" ] 2>/dev/null; then
    log WARN "PREFLIGHT WARNING : $files_count fichiers modifiés (seuil: $max_files)"
  fi

  if [ "$merge_ok" = false ]; then
    log ERROR "Preflight checks BLOQUÉS — feature '$feature_name' non mergée."
    return 1
  fi

  log INFO "Preflight checks OK ($files_count fichiers, +$additions/-$deletions)"
  return 0
}

# Génère un rapport de changements pour une feature
generate_change_report() {
  local feature_name="$1"
  local feature_num="$2"
  local fix_attempts="${3:-0}"
  local report="$LOG_DIR/change-report-${feature_num}.md"

  {
    echo "# Change Report — Feature #${feature_num}"
    echo ""
    echo "**Feature :** $feature_name"
    echo "**Date :** $(date '+%Y-%m-%d %H:%M')"
    echo "**Branche :** $(run_in_project "git branch --show-current 2>/dev/null" || echo "?")"
    echo "**Fix attempts :** $fix_attempts"
    echo ""

    echo "## Fichiers modifiés"
    echo '```'
    run_in_project "git diff --stat main 2>/dev/null" || echo "(pas de diff)"
    echo '```'
    echo ""

    echo "## Commits"
    echo '```'
    run_in_project "git log --oneline main..HEAD 2>/dev/null" || echo "(pas de commits)"
    echo '```'
    echo ""

    echo "## Métriques"
    local files additions deletions diff_stat_line
    files=$(run_in_project "git diff --name-only main 2>/dev/null | wc -l" || echo "0")
    diff_stat_line=$(run_in_project "git diff --stat main 2>/dev/null | tail -1" || echo "")
    additions=$(echo "$diff_stat_line" | awk '{for(i=1;i<=NF;i++) if($i ~ /insertion/) print $(i-1)}')
    deletions=$(echo "$diff_stat_line" | awk '{for(i=1;i<=NF;i++) if($i ~ /deletion/) print $(i-1)}')
    echo "- Fichiers : ${files:-0}"
    echo "- Lignes ajoutées : ${additions:-0}"
    echo "- Lignes supprimées : ${deletions:-0}"
    echo "- Coût cumulé : \$$TOTAL_COST_USD"
    echo ""
  } > "$report"

  log INFO "Change report : $report"
}

# Vérification fonctionnelle post-feature
run_functional_check() {
  local feature_name="$1"
  if [ -z "${FUNCTIONAL_CHECK_COMMAND:-}" ]; then
    return 0
  fi
  log INFO "Vérification fonctionnelle en cours..."
  local func_output func_exit
  func_output=$(run_in_project "$FUNCTIONAL_CHECK_COMMAND 2>&1") && func_exit=0 || func_exit=$?

  if [ $func_exit -eq 0 ]; then
    log INFO "Vérification fonctionnelle OK ✓"
    LAST_FUNCTIONAL_CHECK=true
    return 0
  fi

  log WARN "Vérification fonctionnelle échouée — tentative de correction..."
  LAST_FUNCTIONAL_CHECK=false

  # Une tentative de fix dédiée
  run_claude "La vérification fonctionnelle a ÉCHOUÉ après le merge de la feature '$feature_name'.

COMMANDE : $FUNCTIONAL_CHECK_COMMAND
EXIT CODE : $func_exit
OUTPUT :
$(smart_truncate "$func_output" 3000)

RÈGLE ABSOLUE : l'application DOIT être fonctionnelle après chaque feature.
Corrige le problème pour que l'app démarre/fonctionne correctement.
Ne casse PAS les tests existants." \
    20 "$LOG_DIR/feature-$FEATURE_COUNT-functional-check.log" "functional-fix" "$feature_name" || {
    log WARN "Correction fonctionnelle échouée."
  }

  # Re-vérifier
  func_output=$(run_in_project "$FUNCTIONAL_CHECK_COMMAND 2>&1") && func_exit=0 || func_exit=$?
  if [ $func_exit -eq 0 ]; then
    log INFO "Vérification fonctionnelle OK après correction ✓"
    LAST_FUNCTIONAL_CHECK=true
    # Commiter le fix
    run_in_project "git add -A && git commit -m 'fix: app fonctionnelle après $feature_name' 2>/dev/null || true"
  else
    log ERROR "App non fonctionnelle après '$feature_name' — signalé mais on continue."
    notify "ALERTE : App non fonctionnelle après '$feature_name'"
  fi
}

# Initialise le fichier de tracking tokens
init_tokens() {
  mkdir -p "$LOG_DIR"
  if [ ! -f "$TOKENS_FILE" ] || [ ! -s "$TOKENS_FILE" ] || ! jq empty "$TOKENS_FILE" 2>/dev/null; then
    cat > "$TOKENS_FILE" << 'JSONEOF'
{
  "total_input_tokens": 0,
  "total_output_tokens": 0,
  "total_cost_usd": 0,
  "invocations": 0,
  "by_phase": {},
  "by_feature": {},
  "history": []
}
JSONEOF
  fi

  if command -v jq &> /dev/null && [ -f "$TOKENS_FILE" ]; then
    TOTAL_INPUT_TOKENS=$(jq -r '.total_input_tokens // 0' "$TOKENS_FILE")
    TOTAL_OUTPUT_TOKENS=$(jq -r '.total_output_tokens // 0' "$TOKENS_FILE")
    TOTAL_COST_USD=$(jq -r '.total_cost_usd // 0' "$TOKENS_FILE")
  fi
}

# Parse la sortie JSON de Claude et extrait les tokens
track_tokens() {
  local phase="$1"
  local feature="${2:-}"
  local json_output="$3"
  local model="${4:-unknown}"
  local actual_turns="${5:-0}"

  if ! command -v jq &> /dev/null; then
    return 0
  fi

  local input_tokens output_tokens
  input_tokens=$(echo "$json_output" | jq -r '.usage.input_tokens // 0' 2>/dev/null || echo "0")
  output_tokens=$(echo "$json_output" | jq -r '.usage.output_tokens // 0' 2>/dev/null || echo "0")

  if [ "$input_tokens" = "0" ] && [ "$output_tokens" = "0" ]; then
    input_tokens=$(echo "$json_output" | jq -r '.result.usage.input_tokens // 0' 2>/dev/null || echo "0")
    output_tokens=$(echo "$json_output" | jq -r '.result.usage.output_tokens // 0' 2>/dev/null || echo "0")
  fi

  [ "$input_tokens" = "null" ] && input_tokens=0
  [ "$output_tokens" = "null" ] && output_tokens=0

  # Valider que ce sont des entiers
  case "$input_tokens" in ''|*[!0-9]*) input_tokens=0 ;; esac
  case "$output_tokens" in ''|*[!0-9]*) output_tokens=0 ;; esac

  if [ "$input_tokens" -eq 0 ] && [ "$output_tokens" -eq 0 ]; then
    return 0
  fi

  local cost
  cost=$(awk "BEGIN {printf \"%.4f\", $input_tokens * $COST_PER_INPUT_TOKEN + $output_tokens * $COST_PER_OUTPUT_TOKEN}")

  TOTAL_INPUT_TOKENS=$((TOTAL_INPUT_TOKENS + input_tokens))
  TOTAL_OUTPUT_TOKENS=$((TOTAL_OUTPUT_TOKENS + output_tokens))
  TOTAL_COST_USD=$(awk "BEGIN {printf \"%.4f\", $TOTAL_COST_USD + $cost}")

  local timestamp
  timestamp=$(date -Iseconds)

  jq \
    --argjson input "$input_tokens" \
    --argjson output "$output_tokens" \
    --argjson cost "$cost" \
    --argjson total_in "$TOTAL_INPUT_TOKENS" \
    --argjson total_out "$TOTAL_OUTPUT_TOKENS" \
    --argjson total_cost "$TOTAL_COST_USD" \
    --arg phase "$phase" \
    --arg feature "$feature" \
    --arg ts "$timestamp" \
    --arg model "$model" \
    --argjson turns "$actual_turns" \
    '
    .total_input_tokens = $total_in |
    .total_output_tokens = $total_out |
    .total_cost_usd = $total_cost |
    .invocations += 1 |
    .by_phase[$phase].input_tokens = ((.by_phase[$phase].input_tokens // 0) + $input) |
    .by_phase[$phase].output_tokens = ((.by_phase[$phase].output_tokens // 0) + $output) |
    .by_phase[$phase].cost_usd = ((.by_phase[$phase].cost_usd // 0) + $cost) |
    .by_phase[$phase].calls = ((.by_phase[$phase].calls // 0) + 1) |
    .by_phase[$phase].models_used[$model] = ((.by_phase[$phase].models_used[$model] // 0) + 1) |
    .by_phase[$phase].turns_history = (((.by_phase[$phase].turns_history // []) + [$turns]) | .[-20:]) |
    (if $feature != "" then
      .by_feature[$feature].input_tokens = ((.by_feature[$feature].input_tokens // 0) + $input) |
      .by_feature[$feature].output_tokens = ((.by_feature[$feature].output_tokens // 0) + $output) |
      .by_feature[$feature].cost_usd = ((.by_feature[$feature].cost_usd // 0) + $cost)
    else . end) |
    .history += [{
      "timestamp": $ts,
      "phase": $phase,
      "feature": $feature,
      "model": $model,
      "turns": $turns,
      "input_tokens": $input,
      "output_tokens": $output,
      "cost_usd": $cost
    }]
    ' "$TOKENS_FILE" > "${TOKENS_FILE}.tmp" && mv "${TOKENS_FILE}.tmp" "$TOKENS_FILE"

  log COST "tokens: +${input_tokens}in/+${output_tokens}out (\$${cost}) | Total: \$${TOTAL_COST_USD}"
}

print_cost_summary() {
  if ! command -v jq &> /dev/null || [ ! -f "$TOKENS_FILE" ]; then
    return 0
  fi

  local invocations total_in total_out total_cost
  invocations=$(jq -r '.invocations // 0' "$TOKENS_FILE")
  total_in=$(jq -r '.total_input_tokens // 0' "$TOKENS_FILE")
  total_out=$(jq -r '.total_output_tokens // 0' "$TOKENS_FILE")
  total_cost=$(jq -r '.total_cost_usd // 0' "$TOKENS_FILE")

  echo ""
  printf "${YELLOW}═══════════════════════════════════════════════════${NC}\n"
  printf "${YELLOW}  CONSOMMATION TOKENS${NC}\n"
  printf "${YELLOW}═══════════════════════════════════════════════════${NC}\n"
  printf "  Invocations Claude :  %s\n" "$invocations"
  printf "  Tokens input :        %s\n" "$total_in"
  printf "  Tokens output :       %s\n" "$total_out"
  printf "  Tokens total :        %s\n" "$((total_in + total_out))"
  printf "  ${YELLOW}Coût estimé :       \$%s USD${NC}\n" "$total_cost"
  echo ""

  printf "  ${CYAN}Par phase :${NC}\n"
  jq -r '.by_phase | to_entries | sort_by(-.value.cost_usd) | .[:5][] | "    \(.key): $\(.value.cost_usd) (\(.value.calls) appels)"' "$TOKENS_FILE" 2>/dev/null || true
  echo ""

  if jq -e '.by_feature | length > 0' "$TOKENS_FILE" > /dev/null 2>&1; then
    printf "  ${CYAN}Par feature :${NC}\n"
    jq -r '.by_feature | to_entries | sort_by(-.value.cost_usd) | .[:5][] | "    \(.key): $\(.value.cost_usd)"' "$TOKENS_FILE" 2>/dev/null || true
    echo ""
  fi
}

# Run Claude avec tracking de tokens et logs temps réel
# Args: prompt, max_turns, log_file, phase_name, feature_name, [system_prompt]
run_claude() {
  local prompt="$1"
  local max_turns="${2:-$MAX_TURNS_PER_INVOCATION}"
  local log_file="${3:-/dev/null}"
  local phase_name="${4:-unknown}"
  local feature_name="${5:-}"
  local custom_system_prompt="${6:-}"

  local exit_code=0
  local start_time
  start_time=$(date +%s)

  # Apprentissage adaptatif : ajuster max_turns selon l'historique réel
  local adapted
  adapted=$(adaptive_max_turns "$phase_name" "$max_turns")
  # Garde-fou : n'utiliser adapted que si c'est un entier valide
  if [[ "${adapted:-}" =~ ^[0-9]+$ ]] && [ "$adapted" != "$max_turns" ]; then
    log INFO "  Turns adaptatifs: $max_turns → $adapted [phase=$phase_name] (basé sur l'historique)"
    max_turns="$adapted"
  fi

  log INFO "→ Claude lancé [phase=$phase_name] [max_turns=$max_turns]..."

  # Préfixe : forcer Claude à rester dans le répertoire projet
  # + contexte adaptatif : indiquer quels fichiers de connaissance consulter selon la phase
  # Pré-lire les fichiers de contexte côté bash pour les injecter directement
  # (évite les tool calls de lecture qui coûtent ~100 tokens d'overhead chacune)
  local index_content="" automap_content=""
  if [ -f "$PROJECT_DIR/.orc/codebase/INDEX.md" ]; then
    # Tronquer à 60 lignes max (convention = 40 lignes, marge de sécurité)
    index_content=$(head -60 "$PROJECT_DIR/.orc/codebase/INDEX.md" 2>/dev/null || true)
  fi
  if [ -f "$PROJECT_DIR/.orc/codebase/auto-map.md" ]; then
    automap_content=$(cat "$PROJECT_DIR/.orc/codebase/auto-map.md" 2>/dev/null || true)
  fi

  local context_hint=""
  case "$phase_name" in
    challenger)
      # Pré-injecter tout le contexte produit pour éviter les tool calls (zéro lecture)
      local brief_content="" roadmap_done="" roadmap_todo="" research_content=""
      brief_content=$(head -100 "$PROJECT_DIR/.orc/BRIEF.md" 2>/dev/null || true)
      roadmap_done=$(grep '^\- \[x\]' "$PROJECT_DIR/.orc/ROADMAP.md" 2>/dev/null | head -20 || true)
      roadmap_todo=$(grep '^\- \[ \]' "$PROJECT_DIR/.orc/ROADMAP.md" 2>/dev/null | head -20 || true)
      research_content=$(head -60 "$PROJECT_DIR/.orc/research/INDEX.md" 2>/dev/null || true)

      context_hint="
CARTE SÉMANTIQUE (INDEX.md) :
${index_content:-[pas encore généré]}

EXPORTS ET CLASSES (auto-map.md) :
${automap_content:-[pas encore généré]}

BRIEF PRODUIT :
${brief_content:-[brief non disponible]}

FEATURES TERMINÉES :
${roadmap_done:-[aucune encore]}

FEATURES À VENIR :
${roadmap_todo:-[aucune]}

INSIGHTS MARCHÉ :
${research_content:-[pas de recherche]}"
      ;;
    product-review)
      # Pré-injecter BRIEF + diff réel + roadmap pour évaluation produit
      # Note : le challenger est injecté séparément dans le feature loop (pas ici)
      local brief_content_pr="" diff_stat_pr="" diff_content_pr="" roadmap_done_pr=""
      brief_content_pr=$(head -100 "$PROJECT_DIR/.orc/BRIEF.md" 2>/dev/null || true)
      diff_stat_pr=$(run_in_project "git diff main...HEAD --stat 2>/dev/null" || true)
      # Diff réel tronqué pour voir le code (pas juste les noms de fichiers)
      diff_content_pr=$(run_in_project "git diff main...HEAD 2>/dev/null | head -200" || true)
      roadmap_done_pr=$(grep '^\- \[x\]' "$PROJECT_DIR/.orc/ROADMAP.md" 2>/dev/null | tail -10 || true)

      context_hint="
BRIEF PRODUIT :
${brief_content_pr:-[brief non disponible]}

FEATURES DÉJÀ LIVRÉES :
${roadmap_done_pr:-[aucune encore]}

FICHIERS MODIFIÉS :
${diff_stat_pr:-[pas de diff]}

DIFF DE CETTE FEATURE (200 premières lignes) :
${diff_content_pr:-[pas de diff]}"
      ;;
    plan)
      context_hint="
CARTE SÉMANTIQUE DU PROJET (INDEX.md) :
${index_content:-[pas encore généré]}

EXPORTS ET CLASSES (auto-map.md) :
${automap_content:-[pas encore généré]}"
      ;;
    implement)
      context_hint="
CARTE SÉMANTIQUE DU PROJET (INDEX.md) :
${index_content:-[pas encore généré]}

EXPORTS ET CLASSES (auto-map.md) :
${automap_content:-[pas encore généré]}

Lis aussi si pertinent pour cette feature :
- Les fichiers de détail .orc/codebase/*.md (PAS tous — uniquement ceux pertinents)
- .claude/skills/stack-conventions.md (conventions à respecter)"
      ;;
    fix)
      context_hint="
EXPORTS ET CLASSES (auto-map.md — pour localiser les modules) :
${automap_content:-[pas encore généré]}

Lis aussi si pertinent :
- .orc/codebase/security.md (si l'erreur est liée à la sécurité)
- .claude/skills/fix-tests.md (workflow de correction)"
      ;;
    strategy)
      context_hint="
CARTE SÉMANTIQUE DU PROJET (INDEX.md) :
${index_content:-[pas encore généré]}

Lis aussi :
- .orc/codebase/architecture.md (décisions techniques en place)
- .orc/research/INDEX.md (insights marché)"
      ;;
    reflect)
      context_hint="
Mets à jour après cette feature :
- .orc/codebase/INDEX.md + les fichiers de détail impactés
- .claude/skills/stack-conventions.md si nouveaux patterns
Note : auto-map.md est déjà régénéré automatiquement (pas besoin de le lire)."
      ;;
    meta-retro)
      context_hint="
CARTE SÉMANTIQUE DU PROJET (INDEX.md) :
${index_content:-[pas encore généré]}

EXPORTS ET CLASSES (auto-map.md) :
${automap_content:-[pas encore généré]}

Auditer : tous les fichiers .orc/codebase/*.md — vérifier la cohérence avec le code réel"
      ;;
  esac

  local full_prompt="IMPORTANT: Tu travailles dans le répertoire courant ($(basename "$PROJECT_DIR")/). Tous les fichiers que tu crées ou modifies doivent être dans ce répertoire. Ne navigue JAMAIS vers un répertoire parent (..) et n'utilise PAS de chemins absolus vers des dossiers parents.
${context_hint}

$prompt"

  # Résoudre le modèle selon la phase (principal ou léger)
  local effective_model
  effective_model=$(resolve_model "$phase_name")
  local model_flag=""
  if [ -n "$effective_model" ]; then
    model_flag="--model $effective_model"
    log INFO "  Modèle: $effective_model [phase=$phase_name]"
  fi

  # Résoudre le pricing pour le tracking
  get_model_pricing "$effective_model"

  # Budget prédictif : estimer le coût AVANT de lancer (et avant mktemp)
  if [ -n "${MAX_BUDGET_USD:-}" ]; then
    # Estimation conservatrice : ~4000 tokens input + ~2000 output par turn
    local est_input=$(( max_turns * 4000 ))
    local est_output=$(( max_turns * 2000 ))
    local est_cost
    est_cost=$(awk "BEGIN {printf \"%.2f\", $est_input * $COST_PER_INPUT_TOKEN + $est_output * $COST_PER_OUTPUT_TOKEN}")
    local remaining
    remaining=$(awk "BEGIN {printf \"%.2f\", $MAX_BUDGET_USD - $TOTAL_COST_USD}")
    local would_exceed
    would_exceed=$(awk "BEGIN {print ($TOTAL_COST_USD + $est_cost > $MAX_BUDGET_USD) ? \"yes\" : \"no\"}")
    if [ "$would_exceed" = "yes" ]; then
      log WARN "Budget prédictif : ~\$${est_cost} estimé, \$${remaining} restant — skip phase '$phase_name'"
      log ERROR "Budget insuffisant — arrêt propre du run."
      print_cost_summary
      workflow_transition "budget_exceeded"
      RUN_STATUS="budget_exceeded"
      RUN_ENDED_AT=$(date -Iseconds)
      save_state
      exit 0
    fi
  fi

  TMP_JSON=$(mktemp)

  # Construire les arguments Claude dans un array (évite la duplication)
  local -a claude_args=(
    -p "$full_prompt"
    --dangerously-skip-permissions
    --max-turns "$max_turns"
    --output-format stream-json
    --verbose
  )
  if [ -n "$effective_model" ]; then
    claude_args+=(--model "$effective_model")
  fi
  # Multi-agent : append le system prompt (ne remplace PAS le défaut + CLAUDE.md)
  if [ -n "$custom_system_prompt" ]; then
    claude_args+=(--append-system-prompt "$custom_system_prompt")
  fi
  claude_args+=(-d "$PROJECT_DIR")

  # Mode debug : FIFO + tee pour streaming temps réel vers orc-debug-live.log
  local _tee_pid="" _debug_log=""
  if [ "${ORC_DEBUG:-false}" = "true" ]; then
    _debug_log="$LOG_DIR/orc-debug-live.log"
    # En-tête de phase en JSON (un objet par ligne = parseable par orc logs --debug)
    local _preview
    _preview=$(printf '%s' "$full_prompt" | head -3 | tr '\n' ' ' | cut -c1-150)
    if command -v jq &>/dev/null; then
      jq -n \
        --arg phase "$phase_name" --arg feature "${feature_name:-}" \
        --arg model "${effective_model:-default}" --argjson max_turns "$max_turns" \
        --arg ts "$(date '+%H:%M:%S')" \
        '{"type":"orc_phase","phase":$phase,"feature":$feature,"model":$model,"max_turns":$max_turns,"ts":$ts}' \
        >> "$_debug_log"
      jq -n \
        --arg phase "$phase_name" \
        --argjson chars "${#full_prompt}" \
        --arg preview "$_preview" \
        --arg ts "$(date '+%H:%M:%S')" \
        '{"type":"orc_prompt","phase":$phase,"chars":$chars,"preview":$preview,"ts":$ts}' \
        >> "$_debug_log"
    else
      printf '{"type":"orc_phase","phase":"%s","feature":"%s","ts":"%s"}\n' \
        "$phase_name" "${feature_name:-}" "$(date '+%H:%M:%S')" >> "$_debug_log"
    fi
    # FIFO : claude écrit → tee lit et duplique vers debug_log ET TMP_JSON en temps réel
    local _debug_fifo
    _debug_fifo=$(mktemp -u /tmp/orc_dbg_XXXXXX)
    mkfifo "$_debug_fifo"
    tee -a "$_debug_log" < "$_debug_fifo" > "$TMP_JSON" &
    _tee_pid=$!
    claude "${claude_args[@]}" > "$_debug_fifo" 2>&1 &
    CLAUDE_PID=$!
  else
    claude "${claude_args[@]}" > "$TMP_JSON" 2>&1 &
    CLAUDE_PID=$!
  fi

  # Monitoring : heartbeat + watchdog stall detection
  local dots=0
  local last_size=0
  local stall_count=0
  # Timeout par phase (PHASE_TIMEOUTS) ou global (CLAUDE_TIMEOUT)
  local timeout="${CLAUDE_TIMEOUT:-0}"
  if declare -p PHASE_TIMEOUTS &>/dev/null && [ -n "${PHASE_TIMEOUTS[$phase_name]+x}" ]; then
    timeout="${PHASE_TIMEOUTS[$phase_name]}"
    log INFO "  Timeout: ${timeout}s [phase=$phase_name]"
  fi

  while kill -0 "$CLAUDE_PID" 2>/dev/null; do
    dots=$((dots + 1))
    local elapsed=$(( $(date +%s) - start_time ))
    local mins=$((elapsed / 60))
    local secs=$((elapsed % 60))
    local size
    size=$(wc -c < "$TMP_JSON" 2>/dev/null || echo "0")

    # Heartbeat toutes les 15s
    if [ $((dots % 3)) -eq 0 ]; then
      printf "\r  ${CYAN}⏳ %s | %02d:%02d | %s bytes reçus${NC}   " \
        "$phase_name" "$mins" "$secs" "$size" >&2
    fi

    # Watchdog : détecter si Claude est bloqué (aucune donnée nouvelle)
    if [ "$size" = "$last_size" ]; then
      stall_count=$((stall_count + 1))
    else
      stall_count=0
      last_size="$size"
    fi

    # Si bloqué depuis 2 minutes (24 x 5s), log un warning
    if [ "$stall_count" -eq 24 ]; then
      log WARN "Claude semble bloqué (pas de nouvelles données depuis 2min) [phase=$phase_name]"
    fi

    # Kill auto si stall prolongé (STALL_KILL_THRESHOLD × 5s)
    local stall_kill_threshold="${STALL_KILL_THRESHOLD:-0}"
    if [ "$stall_kill_threshold" -gt 0 ] && [ "$stall_count" -ge "$stall_kill_threshold" ]; then
      local stall_mins=$(( stall_count * 5 / 60 ))
      log ERROR "Claude bloqué depuis ${stall_mins}min — kill auto [phase=$phase_name]"
      kill "$CLAUDE_PID" 2>/dev/null || true
      wait "$CLAUDE_PID" 2>/dev/null || true
      exit_code=124
      CLAUDE_PID=""
      break
    fi

    # Timeout global : kill si dépassé
    if [ "$timeout" -gt 0 ] && [ "$elapsed" -ge "$timeout" ]; then
      log ERROR "Timeout atteint (${timeout}s) — kill Claude [phase=$phase_name]"
      kill "$CLAUDE_PID" 2>/dev/null || true
      wait "$CLAUDE_PID" 2>/dev/null || true
      exit_code=124  # Convention timeout
      CLAUDE_PID=""
      break
    fi

    sleep 5
  done

  # Récupérer le code de sortie si pas déjà fait (timeout)
  if [ -n "$CLAUDE_PID" ]; then
    wait "$CLAUDE_PID" || exit_code=$?
    CLAUDE_PID=""
  fi
  # Attendre que tee finisse de flusher TMP_JSON (se termine seul quand Claude ferme le FIFO)
  if [ -n "$_tee_pid" ]; then
    wait "$_tee_pid" 2>/dev/null || true
    _tee_pid=""
  fi
  # Nettoyage FIFO après que les deux processus ont terminé (évite la race condition rm -f prématuré)
  if [ -n "${_debug_fifo:-}" ]; then
    rm -f "$_debug_fifo" 2>/dev/null || true
    _debug_fifo=""
  fi

  local duration=$(( $(date +%s) - start_time ))
  local dur_mins=$((duration / 60))
  local dur_secs=$((duration % 60))

  printf "\r%80s\r" "" >&2

  log INFO "← Claude terminé [phase=$phase_name] [durée=${dur_mins}m${dur_secs}s] [exit=$exit_code]"

  # stream-json : extraire la ligne "result" finale (même structure que json)
  local json_output
  json_output=$(grep '^{.*"type":"result"' "$TMP_JSON" | tail -1 2>/dev/null || echo "{}")

  local text_output
  if command -v jq &> /dev/null; then
    text_output=$(echo "$json_output" | jq -r '.result // .message // .' 2>/dev/null || cat "$TMP_JSON")
  else
    text_output=$(cat "$TMP_JSON")
  fi

  echo "$text_output" >> "$log_file"
  if [ "$VERBOSE" = true ]; then
    local line_count
    line_count=$(echo "$text_output" | wc -l)
    if [ "$line_count" -gt 20 ]; then
      echo "$text_output" | head -5
      echo "  ... ($line_count lignes, voir $log_file) ..."
      echo "$text_output" | tail -5
    else
      echo "$text_output"
    fi
  fi

  # Détecter error_max_turns — la phase a été tronquée par le max_turns
  local result_subtype=""
  if command -v jq &> /dev/null; then
    result_subtype=$(echo "$json_output" | jq -r '.subtype // ""' 2>/dev/null || true)
    if [ "$result_subtype" = "error_max_turns" ]; then
      log WARN "Claude a atteint la limite de turns ($max_turns) en phase '$phase_name' — résultat potentiellement incomplet."
    fi
  fi

  # Compter les turns réellement utilisés (nombre de messages assistant dans le stream)
  local actual_turns=0
  actual_turns=$(grep -c '"role":"assistant"' "$TMP_JSON" 2>/dev/null || echo "0")
  # Fallback : essayer l'autre format si 0
  if [ "$actual_turns" -eq 0 ]; then
    actual_turns=$(grep -c '"type":"assistant"' "$TMP_JSON" 2>/dev/null || echo "0")
  fi

  # Ne PAS enregistrer les turns si la phase a été tronquée par max_turns
  # (sinon feedback loop négatif : moins de turns → historique bas → encore moins de turns)
  local turns_to_record="$actual_turns"
  if [ "$result_subtype" = "error_max_turns" ]; then
    turns_to_record=0
    log WARN "Turns non enregistrés (tronqués par max_turns=$max_turns)"
  fi

  track_tokens "$phase_name" "$feature_name" "$json_output" "$effective_model" "$turns_to_record"

  if [ -n "${MAX_BUDGET_USD:-}" ]; then
    local over_budget
    over_budget=$(awk "BEGIN {print ($TOTAL_COST_USD > $MAX_BUDGET_USD) ? \"yes\" : \"no\"}")
    if [ "$over_budget" = "yes" ]; then
      log ERROR "Budget dépassé ! \$${TOTAL_COST_USD} > \$${MAX_BUDGET_USD}"
      print_cost_summary
      rm -f "$TMP_JSON"
      TMP_JSON=""
      workflow_transition "budget_exceeded"
      RUN_STATUS="budget_exceeded"
      RUN_ENDED_AT=$(date -Iseconds)
      save_state
      exit 0
    fi
  fi

  rm -f "$TMP_JSON"
  TMP_JSON=""
  return $exit_code
}

# Remplace les placeholders {{VAR}} dans un fichier phase
# Note: pour les prompts avec du contenu build/test, on utilise
# write_prompt_file pour éviter les problèmes de caractères spéciaux
render_phase() {
  local phase_file="$1"
  shift
  local content
  content=$(cat "$SCRIPT_DIR/phases/$phase_file")

  while [ $# -gt 0 ]; do
    local key="${1%%=*}"
    local value="${1#*=}"
    content="${content//\{\{$key\}\}/$value}"
    shift
  done

  echo "$content"
}

# Écrit un prompt dans un fichier temporaire pour éviter les problèmes
# de caractères spéciaux dans les outputs build/test
write_fix_prompt() {
  local attempt="$1" max_fix="$2" build_exit="$3" build_output="$4" test_exit="$5" test_output="$6"
  local tmp_prompt
  tmp_prompt=$(mktemp)
  cat > "$tmp_prompt" << FIXEOF
Tests/build échoués (tentative ${attempt}/${max_fix}).

BUILD (exit ${build_exit}):
${build_output}

TESTS (exit ${test_exit}):
${test_output}

Analyse et corrige les erreurs :

1. Lis le message d'erreur attentivement
2. Identifie la cause racine (pas juste le symptôme)
3. Corrige le code applicatif OU le test si le test est incorrect
4. Ne désactive JAMAIS un test — le corriger ou corriger le code
5. Commite la correction

Si tu as déjà échoué sur le même problème :
- Essaie une approche différente
- Mets à jour CLAUDE.md avec une règle pour éviter ce piège à l'avenir
FIXEOF
  cat "$tmp_prompt"
  rm -f "$tmp_prompt"
}

# Lit la prochaine feature non cochée de la ROADMAP
next_feature() {
  grep -m1 '^\- \[ \]' "$PROJECT_DIR/.orc/ROADMAP.md" 2>/dev/null | sed 's/^- \[ \] //' || true
}

# Peek la Nième feature non-cochée (sans consommer)
# Usage: peek_feature 2 → retourne la 2ème feature non-cochée (= celle d'après)
peek_feature() {
  local n="${1:-1}"
  grep '^\- \[ \]' "$PROJECT_DIR/.orc/ROADMAP.md" 2>/dev/null | sed -n "${n}p" | sed 's/^- \[ \] //' || true
}

# Challenger async PID (global, pour cleanup et wait)
CHALLENGER_ASYNC_PID=""

# Lancer le challenger en subshell async (isole les globales run_claude)
# Usage: run_challenger_async "feature_name" 3 &; CHALLENGER_ASYNC_PID=$!
run_challenger_async() {
  local feat_name="$1" feat_count="$2"
  local cost_file="$PROJECT_DIR/.orc/logs/.challenger-cost-$feat_count"
  local challenger_out="$PROJECT_DIR/.orc/logs/challenger-$feat_count.md"

  # Guard : ne pas relancer si déjà produit (crash recovery)
  if [ -f "$challenger_out" ]; then
    return 0
  fi

  (
    # Subshell : CLAUDE_PID, TMP_JSON etc. sont isolés du parent
    local cost_before="$TOTAL_COST_USD"
    local challenger_prompt
    challenger_prompt=$(render_phase "03c-challenger.md" \
      "FEATURE_NAME=$feat_name" \
      "N=$feat_count")
    run_claude "$challenger_prompt" "${MAX_TURNS_CHALLENGER:-3}" \
      "$LOG_DIR/feature-$feat_count-challenger.log" "challenger" "$feat_name" || true

    # Exporter le DELTA de coût (pas le total) pour le parent
    local delta
    delta=$(awk "BEGIN { printf \"%.6f\", $TOTAL_COST_USD - $cost_before }")
    printf "%s" "$delta" > "$cost_file"
  )
}

# Récupérer le coût du challenger async et l'intégrer au budget parent
collect_challenger_cost() {
  local feat_count="$1"
  local cost_file="$PROJECT_DIR/.orc/logs/.challenger-cost-$feat_count"
  if [ -f "$cost_file" ]; then
    local delta_cost
    delta_cost=$(cat "$cost_file" 2>/dev/null || echo "0")
    if [ -n "$delta_cost" ] && [ "$delta_cost" != "0" ]; then
      TOTAL_COST_USD=$(awk "BEGIN { printf \"%.6f\", $TOTAL_COST_USD + $delta_cost }")
      log INFO "Coût challenger async intégré : +\$$delta_cost (total: \$$TOTAL_COST_USD)"
    fi
    rm -f "$cost_file"
  fi
}

# Nom court pour les branches git (avec fallback si vide)
branch_name() {
  local name
  name=$(echo "$1" | sed 's/ |.*//;s/[^a-zA-Z0-9]/-/g' | tr '[:upper:]' '[:lower:]' | sed 's/^-*//;s/-*$//' | head -c 40)
  if [ -z "$name" ]; then
    name="feature-$(date +%s)"
  fi
  echo "$name"
}

# Exécute une commande dans PROJECT_DIR sans changer le pwd global
run_in_project() {
  ( set +e; cd "$PROJECT_DIR" && eval "$@" )
}

# === NOTIFICATIONS ===

notify() {
  local message="$1"
  if [ -n "${NOTIFY_COMMAND:-}" ]; then
    eval "$NOTIFY_COMMAND \"[ORC] $message\"" 2>/dev/null || log WARN "Notification échouée."
  fi
}

# === SIGNAUX FILE-BASED (mode nohup) ===

# Vérifie les fichiers de signal déposés par l'humain
check_signals() {
  local signal_dir="$SCRIPT_DIR/.orc"

  # Vérifier les signaux GitHub (labels sur la tracking issue)
  gh_check_signals

  # Signal : pause demandée
  if [ -f "$signal_dir/pause-requested" ]; then
    rm -f "$signal_dir/pause-requested"
    log INFO "Signal pause-requested détecté."
    if [ -t 0 ]; then
      human_pause "Pause demandée via fichier signal"
    else
      log WARN "Pause demandée mais pas de terminal — l'agent attend un signal continue."
      notify "Pause demandée — en attente de .orc/continue (ou label orc:continue sur GitHub)"
      # Attente active : fichier continue OU signal GitHub
      while [ ! -f "$signal_dir/continue" ]; do
        gh_check_signals  # Convertit les labels GitHub en fichiers locaux
        sleep 5
      done
      rm -f "$signal_dir/continue"
      log INFO "Signal continue reçu — reprise."
    fi
  fi

  # Signal : arrêt après la feature en cours
  if [ -f "$signal_dir/stop-after-feature" ]; then
    rm -f "$signal_dir/stop-after-feature"
    log INFO "Signal stop-after-feature détecté — arrêt propre après cette feature."
    notify "Arrêt propre demandé — finit la feature en cours."
    workflow_transition "stopped"
    RUN_STATUS="stopped"
    RUN_ENDED_AT=$(date -Iseconds)
    save_state
    print_cost_summary
    exit 0
  fi

  # Signal : skip la feature en cours
  if [ -f "$signal_dir/skip-feature" ]; then
    rm -f "$signal_dir/skip-feature"
    log WARN "Signal skip-feature détecté — abandon de la feature en cours."
    notify "Feature '${CURRENT_FEATURE:-inconnue}' skippée par signal humain."
    SKIP_CURRENT_FEATURE=true
  fi
}

# === GITHUB INTEGRATION ===

# Détecte si GitHub est disponible et configuré
HAS_GH=false
TRACKING_ISSUE_NUMBER=""

gh_available() {
  if [ "$HAS_GH" = true ]; then return 0; fi
  if command -v gh &> /dev/null && gh auth status &> /dev/null; then
    HAS_GH=true
    return 0
  fi
  return 1
}

# Vérifie si on utilise le mode PR
gh_pr_mode() {
  [ "${GIT_STRATEGY:-local}" = "pr" ] && gh_available
}

# Récupère le owner/repo depuis le remote git
gh_repo_slug() {
  local remote="${GITHUB_REMOTE:-origin}"
  local url
  url=$(run_in_project "git remote get-url '$remote' 2>/dev/null" || true)
  [ -z "$url" ] && return 1
  echo "$url" | sed -E 's#^(https://github\.com/|git@github\.com:)##; s#\.git$##'
}

# Crée l'issue de tracking pour un run orchestrateur
gh_create_tracking_issue() {
  if ! gh_available || [ "${GITHUB_TRACKING_ISSUE:-false}" != "true" ]; then
    return 0
  fi

  local repo_slug
  repo_slug=$(gh_repo_slug) || { log WARN "GitHub: remote introuvable — opération ignorée."; return 0; }

  local body
  body="## 🔄 ORC Orchestrator Run

**Projet** : ${PROJECT_NAME:-$(basename "$PROJECT_DIR")}
**Démarré** : $(date '+%Y-%m-%d %H:%M:%S')
**Config** : MAX_FEATURES=$MAX_FEATURES | EPIC_SIZE=$EPIC_SIZE | MAX_FIX=$MAX_FIX_ATTEMPTS

---
_Cet issue est mis à jour automatiquement par l'orchestrateur ORC._
_Labels \`orc:pause\`, \`orc:stop\`, \`orc:continue\` peuvent être utilisés comme signaux._"

  local issue_url
  issue_url=$(gh issue create \
    --repo "$repo_slug" \
    --title "🔄 ORC Run: ${PROJECT_NAME:-$(basename "$PROJECT_DIR")} — $(date '+%Y-%m-%d')" \
    --body "$body" \
    --label "orc-run" 2>/dev/null) || {
    # Le label n'existe peut-être pas — retry sans label
    issue_url=$(gh issue create \
      --repo "$repo_slug" \
      --title "🔄 ORC Run: ${PROJECT_NAME:-$(basename "$PROJECT_DIR")} — $(date '+%Y-%m-%d')" \
      --body "$body" 2>/dev/null) || {
      log WARN "GitHub: impossible de créer la tracking issue."
      return 1
    }
  }

  TRACKING_ISSUE_NUMBER=$(echo "$issue_url" | grep -oE '[0-9]+$' || true)
  if [ -z "$TRACKING_ISSUE_NUMBER" ]; then
    log WARN "GitHub: impossible d'extraire le numéro d'issue depuis '$issue_url'."
    return 1
  fi
  log INFO "GitHub: tracking issue créée → $issue_url"

  # Persister le numéro de l'issue dans .orc/
  echo "$TRACKING_ISSUE_NUMBER" > "$SCRIPT_DIR/.orc/tracking-issue"
}

# Restaure le numéro de la tracking issue (pour reprise)
gh_restore_tracking_issue() {
  local issue_file="$SCRIPT_DIR/.orc/tracking-issue"
  if [ -f "$issue_file" ]; then
    TRACKING_ISSUE_NUMBER=$(cat "$issue_file" 2>/dev/null || echo "")
  fi
}

# Poste un commentaire sur la tracking issue
gh_comment() {
  if ! gh_available || [ -z "$TRACKING_ISSUE_NUMBER" ]; then
    return 0
  fi

  local message="$1"
  local repo_slug
  repo_slug=$(gh_repo_slug) || { log WARN "GitHub: remote introuvable — opération ignorée."; return 0; }

  gh issue comment "$TRACKING_ISSUE_NUMBER" \
    --repo "$repo_slug" \
    --body "$message" &>/dev/null || {
    log WARN "GitHub: échec commentaire sur issue #$TRACKING_ISSUE_NUMBER"
  }
}

# Crée une PR pour une feature branch
gh_create_pr() {
  local branch="$1" feature_name="$2" fix_attempts="${3:-0}"

  if ! gh_pr_mode; then return 1; fi

  local repo_slug
  repo_slug=$(gh_repo_slug) || { log WARN "GitHub: remote introuvable — opération ignorée."; return 0; }
  local remote="${GITHUB_REMOTE:-origin}"

  # Push la branche
  run_in_project "git push -u '$remote' '$branch' 2>&1" || {
    log WARN "GitHub: push de la branche '$branch' échoué."
    return 1
  }

  local body
  body="## Feature: $feature_name

**Orchestrated by ORC** — Feature #$FEATURE_COUNT
- Fix attempts: $fix_attempts
- Cost so far: \$${TOTAL_COST_USD} USD"

  if [ -n "$TRACKING_ISSUE_NUMBER" ]; then
    body="$body
- Tracking: #$TRACKING_ISSUE_NUMBER"
  fi

  local pr_url
  pr_url=$(gh pr create \
    --repo "$repo_slug" \
    --base main \
    --head "$branch" \
    --title "feat: $feature_name" \
    --body "$body" 2>/dev/null) || {
    log WARN "GitHub: impossible de créer la PR pour '$feature_name'."
    return 1
  }

  log INFO "GitHub: PR créée → $pr_url"
  echo "$pr_url"
}

# Merge une PR (auto ou après review)
# L'approbation peut venir de TROIS sources (premier arrivé gagne) :
#   1. PR review "APPROVED" sur GitHub
#   2. Fichier .orc/approve (touch local ou via script)
#   3. Terminal interactif (human_pause si stdin est un TTY)
gh_merge_pr() {
  local pr_url="$1"

  if ! gh_pr_mode; then return 1; fi

  local repo_slug
  repo_slug=$(gh_repo_slug) || { log WARN "GitHub: remote introuvable — opération ignorée."; return 0; }

  # Extraire le numéro de PR
  local pr_number
  pr_number=$(echo "$pr_url" | grep -oE '[0-9]+$' || true)
  if [ -z "$pr_number" ]; then
    log WARN "GitHub: impossible d'extraire le numéro de PR depuis '$pr_url'."
    return 1
  fi

  if [ "$REQUIRE_HUMAN_APPROVAL" = true ]; then
    log INFO "En attente d'approbation pour PR #$pr_number..."
    log INFO "  → GitHub : approuver la PR sur $pr_url"
    log INFO "  → Local  : touch $SCRIPT_DIR/.orc/approve"
    if [ -t 0 ]; then
      log INFO "  → Terminal : répondre 'c' à la pause interactive"
    fi
    notify "PR #$pr_number en attente d'approbation : $pr_url (ou touch .orc/approve)"
    gh_comment "⏳ Feature #$FEATURE_COUNT en attente d'approbation → $pr_url
_Approuver via PR review, ou localement : \`touch .orc/approve\`_"

    # Nettoyage préventif
    rm -f "$SCRIPT_DIR/.orc/approve"

    # Si terminal interactif : proposer la pause classique en parallèle
    if [ -t 0 ]; then
      # Mode interactif : human_pause classique + poll GitHub en background
      _gh_poll_approval "$pr_number" "$repo_slug" &
      local poll_pid=$!
      human_pause "Approuver la PR #$pr_number ($pr_url)"
      # Si on arrive ici, l'humain a dit "c" → tuer le poll
      kill "$poll_pid" 2>/dev/null || true
      wait "$poll_pid" 2>/dev/null || true
    else
      # Mode nohup : poll multi-source (GitHub review + fichier local)
      local wait_count=0
      local max_wait=2880  # 24h à 30s d'intervalle
      while [ $wait_count -lt $max_wait ]; do
        # Source 1 : PR review sur GitHub
        local review_state
        review_state=$(gh pr view "$pr_number" \
          --repo "$repo_slug" \
          --json reviewDecision \
          --jq '.reviewDecision' 2>/dev/null || echo "")
        if [ "$review_state" = "APPROVED" ]; then
          log INFO "GitHub: PR #$pr_number approuvée via review !"
          break
        fi

        # Source 2 : fichier .orc/approve (contrôle local)
        if [ -f "$SCRIPT_DIR/.orc/approve" ]; then
          rm -f "$SCRIPT_DIR/.orc/approve"
          log INFO "Approbation locale détectée (.orc/approve)"
          break
        fi

        # Source 3 : signaux d'arrêt (pour pouvoir quitter)
        if [ -f "$SCRIPT_DIR/.orc/stop-after-feature" ]; then
          log WARN "Signal stop détecté pendant l'attente d'approbation."
          return 1
        fi

        # Source 4 : signaux GitHub
        gh_check_signals
        if [ -f "$SCRIPT_DIR/.orc/pause-requested" ] || [ -f "$SCRIPT_DIR/.orc/stop-after-feature" ]; then
          log WARN "Signal GitHub détecté pendant l'attente d'approbation."
          return 1
        fi

        sleep 30
        wait_count=$((wait_count + 1))
      done

      if [ $wait_count -ge $max_wait ]; then
        log ERROR "Timeout (24h) en attente d'approbation pour PR #$pr_number."
        return 1
      fi
    fi
  fi

  # Merge via GitHub
  gh pr merge "$pr_number" \
    --repo "$repo_slug" \
    --merge \
    --delete-branch 2>/dev/null || {
    log WARN "GitHub: merge de PR #$pr_number échoué — fallback merge local."
    return 1
  }

  # Synchroniser le main local
  run_in_project "git checkout main 2>/dev/null && git pull '${GITHUB_REMOTE:-origin}' main 2>/dev/null || true"

  log INFO "GitHub: PR #$pr_number mergée et branche supprimée."
  rm -f "$SCRIPT_DIR/.orc/approve"
  return 0
}

# Helper interne : poll GitHub pour approval en background (utilisé en mode interactif)
_gh_poll_approval() {
  local pr_number="$1" repo_slug="$2"
  while true; do
    local review_state
    review_state=$(gh pr view "$pr_number" \
      --repo "$repo_slug" \
      --json reviewDecision \
      --jq '.reviewDecision' 2>/dev/null || echo "")
    if [ "$review_state" = "APPROVED" ]; then
      # Créer le signal pour que human_pause puisse détecter
      touch "$SCRIPT_DIR/.orc/approve"
      return 0
    fi
    sleep 30
  done
}

# Vérifie les signaux GitHub (labels sur la tracking issue)
gh_check_signals() {
  if ! gh_available || [ "${GITHUB_SIGNALS:-false}" != "true" ] || [ -z "$TRACKING_ISSUE_NUMBER" ]; then
    return 0
  fi

  local repo_slug
  repo_slug=$(gh_repo_slug) || { log WARN "GitHub: remote introuvable — opération ignorée."; return 0; }

  local labels
  labels=$(gh issue view "$TRACKING_ISSUE_NUMBER" \
    --repo "$repo_slug" \
    --json labels \
    --jq '.labels[].name' 2>/dev/null || echo "")

  # Signal pause
  if echo "$labels" | grep -q "orc:pause"; then
    log INFO "GitHub: signal orc:pause détecté sur issue #$TRACKING_ISSUE_NUMBER"
    # Retirer le label
    gh issue edit "$TRACKING_ISSUE_NUMBER" \
      --repo "$repo_slug" \
      --remove-label "orc:pause" &>/dev/null || true
    # Créer le fichier de signal local
    touch "$SCRIPT_DIR/.orc/pause-requested"
  fi

  # Signal stop
  if echo "$labels" | grep -q "orc:stop"; then
    log INFO "GitHub: signal orc:stop détecté sur issue #$TRACKING_ISSUE_NUMBER"
    gh issue edit "$TRACKING_ISSUE_NUMBER" \
      --repo "$repo_slug" \
      --remove-label "orc:stop" &>/dev/null || true
    touch "$SCRIPT_DIR/.orc/stop-after-feature"
  fi

  # Signal continue (pour débloquer un nohup en attente)
  if echo "$labels" | grep -q "orc:continue"; then
    log INFO "GitHub: signal orc:continue détecté sur issue #$TRACKING_ISSUE_NUMBER"
    gh issue edit "$TRACKING_ISSUE_NUMBER" \
      --repo "$repo_slug" \
      --remove-label "orc:continue" &>/dev/null || true
    touch "$SCRIPT_DIR/.orc/continue"
  fi
}

# Crée une issue pour une feature abandonnée
gh_create_abandoned_issue() {
  local feature_name="$1" attempts="$2"

  if ! gh_available || [ "${GITHUB_TRACKING_ISSUE:-false}" != "true" ]; then
    return 0
  fi

  local repo_slug
  repo_slug=$(gh_repo_slug) || { log WARN "GitHub: remote introuvable — opération ignorée."; return 0; }

  local body="## Feature abandonnée : $feature_name

**Tentatives** : $attempts / $MAX_FIX_ATTEMPTS
**Feature #** : $FEATURE_COUNT"

  # Ajouter les réflexions si disponibles
  local reflections="$PROJECT_DIR/.orc/logs/fix-reflections-$FEATURE_COUNT.md"
  if [ -f "$reflections" ]; then
    body="$body

### Réflexions de debug
\`\`\`
$(tail -50 "$reflections")
\`\`\`"
  fi

  gh issue create \
    --repo "$repo_slug" \
    --title "🐛 Abandoned: $feature_name" \
    --body "$body" \
    --label "bug,orc-abandoned" 2>/dev/null || {
    # Retry sans labels
    gh issue create \
      --repo "$repo_slug" \
      --title "🐛 Abandoned: $feature_name" \
      --body "$body" 2>/dev/null || true
  }
}

# Ferme la tracking issue à la fin du run
gh_close_tracking_issue() {
  if ! gh_available || [ -z "$TRACKING_ISSUE_NUMBER" ]; then
    return 0
  fi

  local repo_slug
  repo_slug=$(gh_repo_slug) || { log WARN "GitHub: remote introuvable — opération ignorée."; return 0; }

  gh_comment "## 🏁 Run terminé

- **Features** : $FEATURE_COUNT
- **Échecs** : $TOTAL_FAILURES
- **Coût total** : \$${TOTAL_COST_USD} USD
- **Durée** : $(date '+%Y-%m-%d %H:%M:%S')"

  gh issue close "$TRACKING_ISSUE_NUMBER" \
    --repo "$repo_slug" &>/dev/null || true

  log INFO "GitHub: tracking issue #$TRACKING_ISSUE_NUMBER fermée."
  rm -f "$SCRIPT_DIR/.orc/tracking-issue"
}

# === PHASE 2 : ROADMAP SYNC (local → GitHub Issues, push-only) ===

# Synchronise ROADMAP.md vers GitHub Issues.
# Crée une issue par feature non cochée, ferme les issues des features cochées.
# Ne lit JAMAIS les issues comme source de features.
gh_sync_roadmap() {
  if ! gh_available || [ "${GITHUB_SYNC_ROADMAP:-false}" != "true" ]; then
    return 0
  fi

  local repo_slug
  repo_slug=$(gh_repo_slug) || { log WARN "GitHub: remote introuvable — opération ignorée."; return 0; }

  local roadmap="$PROJECT_DIR/.orc/ROADMAP.md"
  if [ ! -f "$roadmap" ]; then return 0; fi

  # Fichier de mapping local : feature_name → issue_number
  local map_file="$SCRIPT_DIR/.orc/roadmap-issues.map"
  touch "$map_file"

  # Sync features non cochées → créer les issues manquantes
  while IFS= read -r line; do
    local feature_name
    feature_name=$(echo "$line" | sed 's/^- \[ \] //')
    [ -z "$feature_name" ] && continue

    # Déjà mappée ?
    if grep -qF "$feature_name" "$map_file" 2>/dev/null; then
      continue
    fi

    # Créer l'issue
    local issue_url
    issue_url=$(gh issue create \
      --repo "$repo_slug" \
      --title "$feature_name" \
      --body "Feature de la roadmap ORC.
_Miroir automatique de ROADMAP.md — ne pas modifier cette issue._" \
      --label "orc-feature" 2>/dev/null) || {
      # Retry sans label
      issue_url=$(gh issue create \
        --repo "$repo_slug" \
        --title "$feature_name" \
        --body "Feature de la roadmap ORC." 2>/dev/null) || continue
    }

    local issue_num
    issue_num=$(echo "$issue_url" | grep -oE '[0-9]+$' || true)
    [ -z "$issue_num" ] && continue
    echo "$feature_name	$issue_num" >> "$map_file"
    log INFO "GitHub: issue #$issue_num créée pour '$feature_name'"
  done < <(grep '^\- \[ \]' "$roadmap" 2>/dev/null || true)

  # Sync features cochées → fermer les issues correspondantes
  while IFS= read -r line; do
    local feature_name
    feature_name=$(echo "$line" | sed 's/^- \[x\] //')
    [ -z "$feature_name" ] && continue

    # Trouver l'issue mappée
    local issue_num
    issue_num=$(grep -F "$feature_name" "$map_file" 2>/dev/null | tail -1 | cut -f2 || true)
    [ -z "$issue_num" ] && continue

    # Fermer si pas déjà fermée
    local state
    state=$(gh issue view "$issue_num" \
      --repo "$repo_slug" \
      --json state --jq '.state' 2>/dev/null || echo "")
    if [ "$state" = "OPEN" ]; then
      gh issue close "$issue_num" \
        --repo "$repo_slug" \
        --comment "Fermée automatiquement — feature mergée." &>/dev/null || true
      log INFO "GitHub: issue #$issue_num fermée (feature terminée)"
    fi
  done < <(grep '^\- \[x\]' "$roadmap" 2>/dev/null || true)
}

# Crée un milestone GitHub pour un epic (groupe de features)
gh_sync_milestone() {
  local epic_name="$1"

  if ! gh_available || [ "${GITHUB_SYNC_ROADMAP:-false}" != "true" ]; then
    return 0
  fi

  local repo_slug
  repo_slug=$(gh_repo_slug) || { log WARN "GitHub: remote introuvable — opération ignorée."; return 0; }

  # Vérifier si le milestone existe déjà
  local existing
  existing=$(gh api "repos/$repo_slug/milestones" \
    --jq ".[] | select(.title==\"$epic_name\") | .number" 2>/dev/null || echo "")

  if [ -n "$existing" ]; then
    echo "$existing"
    return 0
  fi

  # Créer le milestone
  local milestone_num
  milestone_num=$(gh api "repos/$repo_slug/milestones" \
    -f title="$epic_name" \
    -f description="Epic ORC — groupe de $EPIC_SIZE features" \
    --jq '.number' 2>/dev/null || echo "")

  if [ -n "$milestone_num" ]; then
    log INFO "GitHub: milestone '$epic_name' créé (#$milestone_num)"
    echo "$milestone_num"
  fi
}

# === PHASE 2 : FEEDBACK GITHUB (lecture additive) ===

# Lit les commentaires récents de la tracking issue comme feedback additionnel.
# Ajouté au contenu de human-notes, ne remplace rien.
gh_read_feedback() {
  if ! gh_available || [ "${GITHUB_FEEDBACK:-false}" != "true" ] || [ -z "$TRACKING_ISSUE_NUMBER" ]; then
    return 0
  fi

  local repo_slug
  repo_slug=$(gh_repo_slug) || { log WARN "GitHub: remote introuvable — opération ignorée."; return 0; }

  # Lire les commentaires récents (depuis le dernier check)
  local last_check_file="$SCRIPT_DIR/.orc/gh-feedback-last-check"
  local since=""
  if [ -f "$last_check_file" ]; then
    since=$(cat "$last_check_file")
  fi

  # Récupérer les commentaires
  local comments
  comments=$(gh api "repos/$repo_slug/issues/$TRACKING_ISSUE_NUMBER/comments" \
    --jq '.[].body' 2>/dev/null || echo "")

  if [ -z "$comments" ]; then return 0; fi

  # Filtrer : ignorer les commentaires automatiques de l'orchestrateur (commencent par emoji)
  local human_comments=""
  while IFS= read -r comment; do
    # Les commentaires auto commencent par ✅ ❌ 🚀 ⏳ 🏁 — les ignorer
    if echo "$comment" | grep -qE '^(✅|❌|🚀|⏳|🏁|##)'; then
      continue
    fi
    if [ -n "$comment" ]; then
      human_comments="${human_comments}${comment}
"
    fi
  done <<< "$comments"

  if [ -n "$human_comments" ]; then
    echo "
FEEDBACK GITHUB (commentaires sur l'issue de tracking) :
$human_comments"
  fi

  # Mettre à jour le timestamp
  date -u +%Y-%m-%dT%H:%M:%SZ > "$last_check_file"
}

# === PHASE 3 : CI GITHUB ACTIONS (validation bonus, jamais bloquante) ===

# Attend le résultat du CI sur la branche courante (si GitHub Actions configuré).
# Retourne 0 si CI pass ou pas de CI. Retourne 1 si CI fail.
# N'est JAMAIS bloquant pour le merge — les tests locaux font foi.
gh_wait_ci() {
  local branch="$1"

  if ! gh_available || [ "${GITHUB_CI:-false}" != "true" ]; then
    return 0
  fi

  local repo_slug
  repo_slug=$(gh_repo_slug) || { log WARN "GitHub: remote introuvable — opération ignorée."; return 0; }
  local remote="${GITHUB_REMOTE:-origin}"

  # S'assurer que la branche est poussée
  run_in_project "git push '$remote' '$branch' 2>&1" || return 0

  # Attendre les checks (timeout 10 min)
  log INFO "GitHub CI: attente des checks sur '$branch'..."

  local ci_result
  ci_result=$(gh pr checks "$branch" \
    --repo "$repo_slug" \
    --watch \
    --fail-fast 2>&1) && local ci_exit=0 || local ci_exit=$?

  if [ $ci_exit -eq 0 ]; then
    log INFO "GitHub CI: tous les checks passent."
    gh_comment "🟢 CI OK sur \`$branch\`"
    return 0
  else
    log WARN "GitHub CI: checks échoués (non-bloquant — les tests locaux font foi)."
    gh_comment "🔴 CI échoué sur \`$branch\` (non-bloquant)
\`\`\`
$(echo "$ci_result" | tail -20)
\`\`\`"
    return 1
  fi
}

# Poste le résultat de la quality gate comme commit status
gh_post_quality_status() {
  local state="$1" description="$2"

  if ! gh_available || [ "${GITHUB_CI:-false}" != "true" ]; then
    return 0
  fi

  local repo_slug
  repo_slug=$(gh_repo_slug) || { log WARN "GitHub: remote introuvable — opération ignorée."; return 0; }
  local sha
  sha=$(run_in_project "git rev-parse HEAD 2>/dev/null" || echo "")
  [ -z "$sha" ] && return 0

  gh api "repos/$repo_slug/statuses/$sha" \
    -f state="$state" \
    -f description="$description" \
    -f context="orc/quality-gate" &>/dev/null || true
}

# === PHASE 3 : GITHUB RELEASES (changelog auto-généré) ===

# Crée une release GitHub après une meta-rétro ou en fin de projet.
gh_create_release() {
  local tag="$1" title="$2"

  if ! gh_available || [ "${GITHUB_RELEASES:-false}" != "true" ]; then
    return 0
  fi

  local repo_slug
  repo_slug=$(gh_repo_slug) || { log WARN "GitHub: remote introuvable — opération ignorée."; return 0; }
  local remote="${GITHUB_REMOTE:-origin}"

  # S'assurer que main est poussé
  run_in_project "git push '$remote' main 2>&1" || {
    log WARN "GitHub: push main échoué — release non créée."
    return 1
  }

  # Créer le tag
  run_in_project "git tag '$tag' 2>/dev/null" || true
  run_in_project "git push '$remote' '$tag' 2>&1" || true

  # Générer les notes de release
  local body
  body="## $title

**Features** : $FEATURE_COUNT | **Échecs** : $TOTAL_FAILURES | **Coût** : \$${TOTAL_COST_USD} USD

### Changelog
$(run_in_project "git log --oneline --no-decorate \$(git describe --tags --abbrev=0 HEAD^ 2>/dev/null || git rev-list --max-parents=0 HEAD)..HEAD 2>/dev/null" || echo "Première release")"

  gh release create "$tag" \
    --repo "$repo_slug" \
    --title "$title" \
    --notes "$body" &>/dev/null || {
    log WARN "GitHub: release '$tag' non créée."
    return 1
  }

  log INFO "GitHub: release $tag créée."
}

# === HUMAN NOTES (instructions mid-run asynchrones) ===

# Lit le fichier human-notes.md si présent et retourne son contenu
read_human_notes() {
  local notes_file="$SCRIPT_DIR/.orc/human-notes.md"
  if [ -f "$notes_file" ] && [ -s "$notes_file" ]; then
    local content
    content=$(cat "$notes_file")
    echo "

NOTES DE L'HUMAIN (lire attentivement et prendre en compte) :
$content"
  fi
}

# === FIX LOOP DETECTION ===

LAST_ERROR_HASH=""

# Compare l'erreur courante avec la précédente pour détecter les boucles
error_hash() {
  local output="$1"
  # Extraire les lignes d'erreur, supprimer les numéros de ligne/timestamps
  # pour comparer la structure de l'erreur, pas sa position exacte
  local filtered
  filtered=$(echo "$output" | grep -iE 'error|fail|exception|TypeError|SyntaxError|cannot find|not found|unexpected' | \
    sed 's/[0-9]\+//g' | sort -u | head -10)
  # Fallback sur head -20 si aucune ligne d'erreur trouvée
  if [ -z "$filtered" ]; then
    filtered=$(echo "$output" | head -20)
  fi
  echo "$filtered" | md5sum | cut -d' ' -f1
}

# === QUALITY GATE ===

run_quality_gate() {
  if [ -z "${QUALITY_COMMAND:-}" ]; then
    return 0
  fi

  log INFO "Quality gate en cours..."
  local quality_output quality_exit
  quality_output=$(run_in_project "$QUALITY_COMMAND 2>&1") && quality_exit=0 || quality_exit=$?

  if [ $quality_exit -ne 0 ]; then
    log WARN "Quality gate échouée (exit $quality_exit)"
    echo "$quality_output"
    return 1
  fi

  log INFO "Quality gate OK."
  return 0
}

# === AUTO REPO MAP ===
# Génère automatiquement une carte des symboles du projet.
# Inspiré du "repo map" d'Aider (tree-sitter), version bash/grep.
# Résultat : .orc/codebase/auto-map.md — vérité du code, pas maintenu par l'IA.

generate_repo_map() {
  local project_dir="$1"
  local map_file="$project_dir/.orc/codebase/auto-map.md"

  mkdir -p "$project_dir/.orc/codebase"

  {
    echo "# Auto-generated Repo Map"
    echo "> Généré automatiquement — NE PAS modifier à la main."
    echo "> Dernière mise à jour : $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""

    # Détecter la stack par les fichiers présents
    local has_ts=false has_js=false has_py=false has_java=false has_go=false has_astro=false

    compgen -G "$project_dir/src/**/*.ts" > /dev/null 2>&1 && has_ts=true
    compgen -G "$project_dir/src/**/*.tsx" > /dev/null 2>&1 && has_ts=true
    compgen -G "$project_dir/**/*.astro" > /dev/null 2>&1 && has_astro=true
    compgen -G "$project_dir/src/**/*.js" > /dev/null 2>&1 && has_js=true
    compgen -G "$project_dir/src/**/*.jsx" > /dev/null 2>&1 && has_js=true
    compgen -G "$project_dir/**/*.py" > /dev/null 2>&1 && has_py=true
    compgen -G "$project_dir/src/**/*.java" > /dev/null 2>&1 && has_java=true
    compgen -G "$project_dir/**/*.go" > /dev/null 2>&1 && has_go=true

    # TypeScript / JavaScript
    if [ "$has_ts" = true ] || [ "$has_js" = true ]; then
      echo "## Exports TypeScript/JavaScript"
      echo ""
      find "$project_dir/src" -type f \( -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.jsx" \) \
        ! -path "*/node_modules/*" ! -path "*/.next/*" ! -path "*/dist/*" ! -name "*.test.*" ! -name "*.spec.*" \
        2>/dev/null | sort | while read -r f; do
        local rel_path="${f#$project_dir/}"
        local exports
        exports=$(grep -E "^export (default )?(function|class|const|interface|type|enum) " "$f" 2>/dev/null || true)
        if [ -n "$exports" ]; then
          echo "### $rel_path"
          echo "$exports" | sed 's/^/- /' | head -20
          echo ""
        fi
      done
    fi

    # Astro
    if [ "$has_astro" = true ]; then
      echo "## Pages & Components Astro"
      echo ""
      find "$project_dir/src" -type f -name "*.astro" 2>/dev/null | sort | while read -r f; do
        local rel_path="${f#$project_dir/}"
        echo "- $rel_path"
      done
      echo ""
    fi

    # Python
    if [ "$has_py" = true ]; then
      echo "## Modules Python"
      echo ""
      find "$project_dir" -type f -name "*.py" \
        ! -path "*/venv/*" ! -path "*/__pycache__/*" ! -path "*/migrations/*" ! -name "test_*" \
        2>/dev/null | sort | while read -r f; do
        local rel_path="${f#$project_dir/}"
        local exports
        exports=$(grep -E "^(class |def |async def )" "$f" 2>/dev/null || true)
        if [ -n "$exports" ]; then
          echo "### $rel_path"
          echo "$exports" | sed 's/^/- /' | head -20
          echo ""
        fi
      done
    fi

    # Java
    if [ "$has_java" = true ]; then
      echo "## Classes Java"
      echo ""
      find "$project_dir/src" -type f -name "*.java" ! -name "*Test.java" \
        2>/dev/null | sort | while read -r f; do
        local rel_path="${f#$project_dir/}"
        local exports
        exports=$(grep -E "^public (class|interface|enum|record) " "$f" 2>/dev/null || true)
        if [ -n "$exports" ]; then
          echo "### $rel_path"
          echo "$exports" | sed 's/^/- /' | head -10
          echo ""
        fi
      done
    fi

    # Go
    if [ "$has_go" = true ]; then
      echo "## Packages Go"
      echo ""
      find "$project_dir" -type f -name "*.go" ! -name "*_test.go" \
        2>/dev/null | sort | while read -r f; do
        local rel_path="${f#$project_dir/}"
        local exports
        exports=$(grep -E "^func [A-Z]|^type [A-Z]" "$f" 2>/dev/null || true)
        if [ -n "$exports" ]; then
          echo "### $rel_path"
          echo "$exports" | sed 's/^/- /' | head -20
          echo ""
        fi
      done
    fi

    # Routes / API endpoints
    local api_files
    api_files=$(find "$project_dir/src" -type f \( -path "*/api/*" -o -path "*/routes/*" -o -path "*/pages/api/*" \) \
      ! -path "*/node_modules/*" 2>/dev/null | sort)
    if [ -n "$api_files" ]; then
      echo "## API Routes"
      echo ""
      echo "$api_files" | while read -r f; do
        echo "- ${f#$project_dir/}"
      done
      echo ""
    fi

  } > "$map_file" 2>/dev/null

  # Tronquer si trop long (max 200 lignes)
  local line_count
  line_count=$(wc -l < "$map_file")
  if [ "$line_count" -gt 200 ]; then
    head -200 "$map_file" > "${map_file}.tmp"
    echo "" >> "${map_file}.tmp"
    echo "> Tronqué à 200 lignes ($line_count au total)" >> "${map_file}.tmp"
    mv "${map_file}.tmp" "$map_file"
  fi

  log INFO "Repo map généré : $map_file ($line_count lignes)"
}

# Pause pour intervention humaine
human_pause() {
  # Si stdin n'est pas un terminal (mode nohup), skip la pause
  if [ ! -t 0 ]; then
    log WARN "Pause ignorée (pas de terminal interactif) : $1"
    return 0
  fi

  local reason="$1"
  log PHASE "PAUSE HUMAINE — $reason"
  notify "Pause humaine : $reason (features: $FEATURE_COUNT, coût: \$$TOTAL_COST_USD)"
  echo ""
  printf "${YELLOW}═══════════════════════════════════════════════════${NC}\n"
  printf "${YELLOW}  PAUSE — Intervention humaine requise${NC}\n"
  printf "${YELLOW}  Raison : %s${NC}\n" "$reason"
  printf "${YELLOW}  Features complétées : %s${NC}\n" "$FEATURE_COUNT"
  printf "${YELLOW}  Coût actuel : \$%s USD${NC}\n" "$TOTAL_COST_USD"
  printf "${YELLOW}═══════════════════════════════════════════════════${NC}\n"
  echo ""
  echo "  Commandes :"
  printf "    ${GREEN}c${NC} — continuer\n"
  printf "    ${GREEN}r${NC} — voir la roadmap\n"
  printf "    ${GREEN}l${NC} — voir les logs récents\n"
  printf "    ${GREEN}t${NC} — voir les tokens consommés\n"
  printf "    ${GREEN}d${NC} — voir le diff de la dernière feature\n"
  printf "    ${GREEN}s${NC} — voir le résumé de la dernière feature\n"
  printf "    ${GREEN}f${NC} — laisser un feedback sur la dernière feature\n"
  printf "    ${GREEN}n${NC} — écrire des notes pour l'IA (instructions mid-run)\n"
  printf "    ${GREEN}q${NC} — quitter\n"
  echo ""

  while true; do
    # Vérifier si un signal externe (GitHub review ou fichier) débloque la pause
    if [ -f "$SCRIPT_DIR/.orc/approve" ]; then
      rm -f "$SCRIPT_DIR/.orc/approve"
      printf "\n  ${GREEN}Approbation reçue (signal externe).${NC}\n"
      return 0
    fi
    # read avec timeout de 5s pour pouvoir vérifier les signaux régulièrement
    read -t 5 -rp "→ " choice || { choice=""; continue; }
    case "$choice" in
      "") continue ;;
      c|C) return 0 ;;
      r|R) cat "$PROJECT_DIR/.orc/ROADMAP.md" 2>/dev/null || echo "Pas de ROADMAP." ; echo "" ;;
      l|L) tail -30 "$LOG_DIR/orchestrator.log" 2>/dev/null ; echo "" ;;
      t|T) print_cost_summary ;;
      d|D)
        # Diff de la dernière feature mergée
        echo ""
        printf "${CYAN}  Diff de la dernière feature :${NC}\n"
        run_in_project "git diff HEAD~1 --stat 2>/dev/null" || echo "  Pas de diff disponible."
        echo ""
        run_in_project "git diff HEAD~1 2>/dev/null" | head -100
        local diff_lines
        diff_lines=$(run_in_project "git diff HEAD~1 2>/dev/null" | wc -l)
        if [ "$diff_lines" -gt 100 ]; then
          echo "  ... ($diff_lines lignes au total, tronqué à 100)"
        fi
        echo ""
        ;;
      s|S)
        # Résumé de la dernière feature (log de reflect)
        echo ""
        printf "${CYAN}  Résumé de la dernière feature :${NC}\n"
        local summary_file="$LOG_DIR/feature-$FEATURE_COUNT-reflect.log"
        if [ -f "$summary_file" ]; then
          cat "$summary_file"
        else
          echo "  Pas de résumé disponible."
        fi
        echo ""
        ;;
      f|F)
        # Feedback humain structuré
        echo ""
        printf "${CYAN}  Feedback sur la feature #$FEATURE_COUNT :${NC}\n"
        printf "  (Tapez votre feedback, puis une ligne vide pour terminer)\n"
        echo ""
        local feedback=""
        local line
        while IFS= read -rp "  > " line; do
          [ -z "$line" ] && break
          feedback="$feedback$line
"
        done
        if [ -n "$feedback" ]; then
          local feedback_file="$PROJECT_DIR/.orc/logs/human-feedback-$FEATURE_COUNT.md"
          mkdir -p "$PROJECT_DIR/.orc/logs"
          cat > "$feedback_file" << FBEOF
# Feedback humain — Feature #$FEATURE_COUNT
Date : $(date '+%Y-%m-%d %H:%M:%S')

$feedback
FBEOF
          log INFO "Feedback enregistré : $feedback_file"
          printf "  ${GREEN}Feedback enregistré.${NC}\n"
        fi
        echo ""
        ;;
      n|N)
        # Notes mid-run pour l'IA
        echo ""
        printf "${CYAN}  Notes pour l'IA (sera lu avant la prochaine feature) :${NC}\n"
        printf "  (Tapez vos instructions, puis une ligne vide pour terminer)\n"
        echo ""
        local notes=""
        local nline
        while IFS= read -rp "  > " nline; do
          [ -z "$nline" ] && break
          notes="$notes$nline
"
        done
        if [ -n "$notes" ]; then
          local notes_file="$SCRIPT_DIR/.orc/human-notes.md"
          # Append pour accumuler les notes
          {
            echo ""
            echo "## $(date '+%Y-%m-%d %H:%M:%S')"
            echo "$notes"
          } >> "$notes_file"
          log INFO "Notes enregistrées dans .orc/human-notes.md"
          printf "  ${GREEN}Notes enregistrées — l'IA les lira à la prochaine feature.${NC}\n"
        fi
        echo ""
        ;;
      q|Q) log INFO "Arrêt demandé par l'utilisateur." ; workflow_transition "stopped" ; RUN_STATUS="stopped" ; RUN_ENDED_AT=$(date -Iseconds) ; print_cost_summary ; exit 0 ;;
      *) echo "Choix invalide." ;;
    esac
  done
}

# ============================================================
# WIZARD D'ALIGNEMENT (interactif, entre cycles evolve)
# ============================================================

# Lit le fichier alignment-response le plus récent et l'injecte dans le prompt
read_alignment_response() {
  local latest
  latest=$(ls -t "$PROJECT_DIR/.orc/logs/alignment-response-"*.md 2>/dev/null | head -1)
  if [ -n "$latest" ] && [ -f "$latest" ] && [ -s "$latest" ]; then
    local content
    content=$(cat "$latest")
    echo "

DIRECTIVES D'ALIGNEMENT DE L'HUMAIN (prioritaire — adapter le travail en conséquence) :
$content"
  fi
}

# Wizard interactif : pose les questions du rapport d'alignement une par une
alignment_wizard() {
  local cycle="$1"
  local report_file="$PROJECT_DIR/.orc/logs/alignment-report-${cycle}.md"
  local response_file="$PROJECT_DIR/.orc/logs/alignment-response-${cycle}.md"

  # Si pas de terminal interactif, skip le wizard (mode nohup)
  if [ ! -t 0 ]; then
    log WARN "Alignment wizard ignoré (pas de terminal). Le rapport est dans : $report_file"
    log WARN "Pour répondre manuellement, créer : $response_file"
    return 0
  fi

  echo ""
  printf "${CYAN}═══════════════════════════════════════════════════${NC}\n"
  printf "${CYAN}  CHECKPOINT D'ALIGNEMENT — Cycle %s${NC}\n" "$cycle"
  printf "${CYAN}  Features complétées : %s | Coût : \$%s USD${NC}\n" "$FEATURE_COUNT" "$TOTAL_COST_USD"
  printf "${CYAN}═══════════════════════════════════════════════════${NC}\n"
  echo ""

  # Afficher le résumé du rapport si disponible
  if [ -f "$report_file" ]; then
    printf "${YELLOW}  Rapport d'alignement :${NC}\n"
    echo ""
    cat "$report_file"
    echo ""
    printf "${YELLOW}───────────────────────────────────────────────────${NC}\n"
    echo ""
  else
    printf "${YELLOW}  Rapport d'alignement non disponible.${NC}\n"
    printf "${YELLOW}  Consultez la roadmap et le brief pour le contexte.${NC}\n"
    echo ""
  fi

  # Questions interactives
  local responses=""

  local questions=(
    "La direction générale est-elle toujours la bonne ? (oui / ajustements à faire)"
    "Parmi les features prévues, y en a-t-il à retirer ou réordonner ?"
    "Y a-t-il un besoin nouveau non couvert par le brief ?"
    "Quel est ton critère de \"suffisant\" pour ce projet ?"
    "Feedback libre sur ce que tu as vu jusqu'ici ?"
  )

  printf "  ${GREEN}Réponds aux questions ci-dessous (Entrée = passer, q = quitter)${NC}\n"
  echo ""

  for i in "${!questions[@]}"; do
    local qnum=$((i + 1))
    printf "  ${CYAN}%d. %s${NC}\n" "$qnum" "${questions[$i]}"
    local answer=""
    local line
    while IFS= read -rp "  > " line; do
      if [ "$line" = "q" ]; then
        log INFO "Wizard interrompu par l'utilisateur."
        [ -n "$responses" ] && printf "  ${YELLOW}Réponses partielles conservées.${NC}\n"
        break 2
      fi
      [ -z "$line" ] && break
      answer="$answer$line
"
    done
    if [ -n "$answer" ]; then
      responses="$responses
### Q${qnum}. ${questions[$i]}
$answer"
    fi
    echo ""
  done

  # Sauvegarder les réponses
  if [ -n "$responses" ]; then
    mkdir -p "$PROJECT_DIR/.orc/logs"
    cat > "$response_file" << ALEOF
# Réponses d'alignement — Cycle $cycle
Date : $(date '+%Y-%m-%d %H:%M:%S')
$responses
ALEOF
    log INFO "Réponses d'alignement enregistrées : $response_file"
    printf "  ${GREEN}Réponses enregistrées. Elles seront prises en compte dans le prochain cycle.${NC}\n"
  else
    printf "  ${YELLOW}Aucune réponse — le prochain cycle continue avec la direction actuelle.${NC}\n"
  fi
  echo ""
}

# ============================================================
# VÉRIFICATIONS PRÉALABLES
# ============================================================

if ! command -v claude &> /dev/null; then
  printf "${RED}Erreur : 'claude' CLI non trouvé.${NC}\n"
  exit 1
fi

if ! command -v jq &> /dev/null; then
  printf "${YELLOW}⚠ jq non trouvé — le tracking de tokens sera désactivé.${NC}\n"
  printf "  Installer : ${CYAN}sudo apt install jq${NC}\n"
fi

if [ ! -f "$SCRIPT_DIR/BRIEF.md" ]; then
  printf "${RED}Erreur : BRIEF.md non trouvé.${NC}\n"
  echo ""
  echo "  Ce script doit être lancé depuis un workspace créé par init.sh."
  echo "  Depuis le repo template, lancez :"
  printf "    ${CYAN}./init.sh mon-projet${NC}\n"
  exit 1
fi

# S'assurer que .orc/ existe (state, logs, lock)
mkdir -p "$SCRIPT_DIR/.orc"

# Lockfile — empêche l'exécution concurrente
if [ -f "$LOCKFILE" ]; then
  existing_pid=$(cat "$LOCKFILE" 2>/dev/null || echo "")
  if [ -n "$existing_pid" ] && kill -0 "$existing_pid" 2>/dev/null; then
    printf "${RED}Erreur : orchestrateur déjà en cours (PID %s).${NC}\n" "$existing_pid"
    printf "  Si ce n'est pas le cas : ${CYAN}rm %s${NC}\n" "$LOCKFILE"
    exit 1
  fi
  log WARN "Lock orphelin détecté (PID $existing_pid mort), nettoyage."
  rm -f "$LOCKFILE"
fi
echo $$ > "$LOCKFILE"

mkdir -p "$LOG_DIR"
init_tokens
restore_state
gh_restore_tracking_issue

# === MIGRATION CONFIG AUTO ===
# Détecte les paramètres manquants dans la config du projet et les ajoute
# avec les valeurs par défaut. Permet aux projets existants de bénéficier
# des nouvelles options sans intervention humaine.
migrate_config() {
  # Résoudre la config projet (supporte .orc/config.sh et config.sh rétrocompat)
  local project_config="$SCRIPT_DIR/.orc/config.sh"
  [ -f "$project_config" ] || project_config="$SCRIPT_DIR/config.sh"
  [ -f "$project_config" ] || return 0

  # Vérifier que la config est writable
  [ -w "$project_config" ] || { log WARN "Config non writable ($project_config) — migration ignorée."; return 0; }

  # Résoudre le chemin du template orc (via le symlink orchestrator.sh)
  local orc_dir
  orc_dir=$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || realpath "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")")
  local default_config="$orc_dir/config.default.sh"
  [ -f "$default_config" ] || return 0

  local migrated=0

  # Extraire les paramètres définis dans config.default.sh (VAR=value, pas les commentaires ni declare)
  while IFS= read -r line; do
    # Ignorer les lignes vides, commentaires, declare, et sections
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ "$line" =~ ^[[:space:]]*$ ]] && continue
    [[ "$line" =~ ^declare ]] && continue
    [[ "$line" =~ ^\) ]] && continue

    # Extraire le nom de la variable
    local var_name="${line%%=*}"
    var_name="${var_name#"${var_name%%[![:space:]]*}"}"  # trim leading spaces
    [[ "$var_name" =~ ^[A-Z_][A-Z_0-9]*$ ]] || continue

    # Vérifier si le paramètre existe dans la config du projet
    if ! grep -q "^${var_name}=" "$project_config" 2>/dev/null; then
      echo "# [migré auto]" >> "$project_config"
      echo "$line" >> "$project_config"
      migrated=$((migrated + 1))
      log INFO "Config migrée : $var_name"
    fi
  done < "$default_config"

  # Migrer PHASE_TIMEOUTS (declare -A, traitement spécial)
  if ! grep -q "PHASE_TIMEOUTS" "$project_config" 2>/dev/null; then
    if grep -q "declare -A PHASE_TIMEOUTS" "$default_config" 2>/dev/null; then
      echo "# [migré auto] Timeouts par phase" >> "$project_config"
      sed -n '/^declare -A PHASE_TIMEOUTS/,/^)/p' "$default_config" >> "$project_config"
      migrated=$((migrated + 1))
      log INFO "Config migrée : PHASE_TIMEOUTS"
    fi
  fi

  if [ "$migrated" -gt 0 ]; then
    log INFO "Migration config : $migrated paramètres ajoutés."
  fi
}
migrate_config

# Re-source la config au top-level après migration (declare -A PHASE_TIMEOUTS
# crée un array local si sourcé dans une fonction — le re-source ici le rend global)
if [ -f "$SCRIPT_DIR/.orc/config.sh" ]; then
  source "$SCRIPT_DIR/.orc/config.sh"
elif [ -f "$SCRIPT_DIR/config.sh" ]; then
  source "$SCRIPT_DIR/config.sh"
fi

# === MIGRATION KANBAN ===
# Convertit le ROADMAP.md plat en structure kanban si pas encore fait
migrate_to_kanban() {
  local roadmap="$PROJECT_DIR/.orc/ROADMAP.md"
  local kanban_dir="$PROJECT_DIR/.orc/roadmap"

  # Déjà migré ? Vérifier qu'il y a de vrais tickets (pas juste des dossiers vides)
  local has_tickets=false
  for _d in "$kanban_dir"/*/; do
    [ -d "$_d" ] || continue
    for _f in "$_d"*.md; do
      [ -f "$_f" ] && { has_tickets=true; break 2; }
    done
  done
  if [ "$has_tickets" = true ]; then
    return 0
  fi

  # Pas de ROADMAP.md ? Juste initialiser la structure vide
  if [ ! -f "$roadmap" ]; then
    init_kanban
    return 0
  fi

  init_kanban
  local id=1

  # Parser chaque ligne de feature du ROADMAP.md
  while IFS= read -r line; do
    local title desc slug padded_id status_dir
    title=$(echo "$line" | sed 's/^- \[.\] //' | sed 's/ |.*//')
    desc=$(echo "$line" | grep -o '|.*' | sed 's/^| *//' || true)
    slug=$(echo "$title" | sed 's/[^a-zA-Z0-9]/-/g' | tr '[:upper:]' '[:lower:]' | sed 's/^-*//;s/-*$//;s/--*/-/g' | head -c 30)
    padded_id=$(printf "%03d" "$id")

    if [[ "$line" =~ ^\-\ \[x\] ]]; then
      status_dir="done"
    else
      status_dir="todo"
    fi

    cat > "$kanban_dir/$status_dir/$padded_id-$slug.md" <<TICKET
---
id: $id
title: "$title"
priority: P1
type: feature
effort: M
tags: []
epic: mvp
created: $(date '+%Y-%m-%d')
source: strategy
---

## Contexte
Feature issue de la roadmap initiale.

## Specification
$title
$([ -n "$desc" ] && echo "
Criteres d'acceptance : $desc")

## Criteres de validation
$([ -n "$desc" ] && echo "- [ ] $desc" || echo "- [ ] Feature implementee et fonctionnelle")

## Notes
Migre depuis ROADMAP.md (format legacy).
TICKET

    id=$((id + 1))
  done < <(grep '^\- \[' "$roadmap")

  # Archiver l'ancien fichier et régénérer la vue
  mv "$roadmap" "$roadmap.legacy"
  regenerate_roadmap_view
  log INFO "Migration kanban : $((id - 1)) tickets migres depuis ROADMAP.md"
}
migrate_to_kanban

clear_action_required
log PHASE "DÉMARRAGE DE L'AGENT AUTONOME"
log INFO "Config : MAX_FEATURES=$MAX_FEATURES | MAX_FIX=$MAX_FIX_ATTEMPTS | EPIC_SIZE=$EPIC_SIZE"
log INFO "Recherche : $ENABLE_RESEARCH | Approbation humaine : $REQUIRE_HUMAN_APPROVAL"
log INFO "Git strategy : ${GIT_STRATEGY:-local} | GitHub tracking : ${GITHUB_TRACKING_ISSUE:-false} | GitHub signals : ${GITHUB_SIGNALS:-false}"
if [ -n "${MAX_BUDGET_USD:-}" ]; then
  log INFO "Budget max : \$${MAX_BUDGET_USD} USD"
fi
if [ "$TOTAL_COST_USD" != "0" ]; then
  log INFO "Reprise — coût cumulé : \$${TOTAL_COST_USD} USD"
fi

# ============================================================
# REPRISE ALIGNMENT_PENDING — Wizard interactif
# ============================================================

if [ "$WORKFLOW_PHASE" = "alignment_pending" ]; then
  log PHASE "REPRISE — CHECKPOINT D'ALIGNEMENT (cycle $EVOLVE_CYCLES)"
  RUN_STATUS="running"

  # Lancer le wizard interactif
  alignment_wizard "$EVOLVE_CYCLES"

  # Réinjecter dans le flow : reprendre la boucle features
  AI_ROADMAP_ADDS=0  # Reset après validation humaine
  workflow_transition "features"
  save_state
  log INFO "Alignement validé — reprise de la boucle de développement."
fi

# Reprise post-DONE avec nouveaux tickets kanban
SKIP_TO_POST_PROJECT=false
if [ "$WORKFLOW_PHASE" = "done" ] && [ ! -f "$PROJECT_DIR/DONE.md" ] && has_todo_tickets; then
  log INFO "Reprise post-DONE detectee — nouveaux tickets trouves, retour en boucle features."
  workflow_transition "features"
  RUN_STATUS="running"
elif [ -f "$PROJECT_DIR/DONE.md" ] || [[ "$WORKFLOW_PHASE" =~ ^(done|crashed|stopped)$ ]]; then
  # Reprise après crash en post-project : sauter directement à post-project
  # (évite de re-générer la stratégie quand le projet est terminé)
  log INFO "Reprise post-projet detectee (DONE.md ou workflow=$WORKFLOW_PHASE) — saut direct."
  SKIP_TO_POST_PROJECT=true
  RUN_STATUS="running"
fi

# ============================================================
# PHASE 0 — BOOTSTRAP
# ============================================================

if [ ! -f "$PROJECT_DIR/CLAUDE.md" ]; then
  workflow_transition "bootstrap"
  log PHASE "PHASE 0 — BOOTSTRAP"
  update_phase_tracking "bootstrap" ""

  if [ ! -d "$PROJECT_DIR/.git" ]; then
    mkdir -p "$PROJECT_DIR"
    run_in_project "git init -b main > /dev/null 2>&1"
  fi

  mkdir -p "$PROJECT_DIR/.orc"

  if [ ! -f "$PROJECT_DIR/.orc/BRIEF.md" ]; then
    cp "$SCRIPT_DIR/BRIEF.md" "$PROJECT_DIR/.orc/BRIEF.md"
  fi

  mkdir -p "$PROJECT_DIR/.orc/research/competitors" \
           "$PROJECT_DIR/.orc/research/trends" \
           "$PROJECT_DIR/.orc/research/user-needs" \
           "$PROJECT_DIR/.orc/research/regulations" \
           "$PROJECT_DIR/.orc/logs"

  # Copier les learnings inter-projets si disponibles
  if compgen -G "$SCRIPT_DIR/learnings/*.md" > /dev/null 2>&1; then
    mkdir -p "$PROJECT_DIR/learnings"
    for learning in "$SCRIPT_DIR/learnings/"*.md; do
      dest="$PROJECT_DIR/learnings/$(basename "$learning")"
      [ ! -f "$dest" ] && cp "$learning" "$dest"
    done
    log INFO "Learnings inter-projets copiés ($(ls -1 "$SCRIPT_DIR/learnings/"*.md 2>/dev/null | wc -l) fichiers)."
  fi

  mkdir -p "$PROJECT_DIR/.claude/skills"
  if compgen -G "$SCRIPT_DIR/skills-templates/*.md" > /dev/null 2>&1; then
    for skill in "$SCRIPT_DIR/skills-templates/"*.md; do
      dest="$PROJECT_DIR/.claude/skills/$(basename "$skill")"
      [ ! -f "$dest" ] && cp "$skill" "$dest"
    done
  fi

  local_prompt=$(render_phase "00-bootstrap.md")

  # Injecter les learnings inter-projets directement dans le prompt
  # (au lieu de compter sur Claude pour les lire via tool call)
  if [ -d "$PROJECT_DIR/learnings" ] && compgen -G "$PROJECT_DIR/learnings/*.md" > /dev/null 2>&1; then
    learnings_content=""
    for lf in "$PROJECT_DIR/learnings/"*.md; do
      learnings_content="$learnings_content
--- $(basename "$lf") ---
$(head -50 "$lf")
"
    done
    local_prompt="$local_prompt

LEARNINGS DES PROJETS PRÉCÉDENTS (intègre les règles pertinentes dans CLAUDE.md) :
$learnings_content"
    log INFO "Learnings inter-projets injectés dans le prompt bootstrap."
  fi

  run_claude "$local_prompt" 30 "$LOG_DIR/00-bootstrap.log" "bootstrap"

  # Créer la tracking issue GitHub si configuré
  if [ -z "$TRACKING_ISSUE_NUMBER" ]; then
    gh_create_tracking_issue
  fi

  log INFO "Bootstrap terminé."
else
  log INFO "Projet existant détecté (CLAUDE.md présent), reprise en cours..."
fi

# ============================================================
# PHASE 1 — RECHERCHE INITIALE
# ============================================================

if [ "$ENABLE_RESEARCH" = true ] && [ ! -f "$PROJECT_DIR/.orc/research/INDEX.md" ]; then
  workflow_transition "research"
  log PHASE "PHASE 1 — RECHERCHE INITIALE"
  update_phase_tracking "research-initial" ""

  local_prompt=$(render_phase "01-research.md")
  run_claude "$local_prompt" "$MAX_TURNS_RESEARCH_INITIAL" "$LOG_DIR/01-research.log" "research-initial"

  log INFO "Recherche initiale terminée."
fi

# ============================================================
# PHASE 2 — STRATÉGIE
# ============================================================

if [ "$SKIP_TO_POST_PROJECT" != true ] && ! has_todo_tickets && ! grep -q '^\- \[ \]' "$PROJECT_DIR/.orc/ROADMAP.md" 2>/dev/null; then
  workflow_transition "strategy"
  log PHASE "PHASE 2 — STRATÉGIE"
  update_phase_tracking "strategy" ""

  # Initialiser le kanban pour que la strategy écrive directement des tickets
  init_kanban

  local_prompt=$(render_phase "02-strategy.md")
  run_claude "$local_prompt" 30 "$LOG_DIR/02-strategy.log" "strategy"

  # Régénérer la vue ROADMAP.md depuis les tickets créés par la strategy
  regenerate_roadmap_view
  log INFO "Roadmap générée (kanban)."
  gh_sync_roadmap
fi

# ============================================================
# PHASE 3 — BOUCLE PRINCIPALE (avec cycles evolve intégrés)
# ============================================================

# Boucle englobante : feature loop + evolve, sans exec "$0" restart
if [ "$SKIP_TO_POST_PROJECT" != true ]; then
  workflow_transition "features"
fi
MAIN_LOOP_CONTINUE=true
while [ "$MAIN_LOOP_CONTINUE" = true ]; do

if [ "$SKIP_TO_POST_PROJECT" = true ]; then
  log INFO "Saut de la boucle features (reprise post-projet)."
  MAIN_LOOP_CONTINUE=false
fi

log PHASE "PHASE 3 — BOUCLE DE DÉVELOPPEMENT"

while [ $FEATURE_COUNT -lt $MAX_FEATURES ]; do

  # --- Sélection du prochain ticket (kanban prioritaire, fallback legacy) ---
  current_ticket=$(next_ticket)
  if [ -n "$current_ticket" ]; then
    feature_name=$(ticket_title "$current_ticket")
    feature_raw="$feature_name"
    # Déplacer en in-progress
    move_ticket "$current_ticket" "in-progress"
    current_ticket="$PROJECT_DIR/.orc/roadmap/in-progress/$(basename "$current_ticket")"
  else
    # Fallback legacy (ROADMAP.md plat)
    feature_raw=$(next_feature)
    current_ticket=""
  fi

  if [ -z "$feature_raw" ] && [ -z "$feature_name" ]; then
    log INFO "Roadmap vide — passage en phase d'évolution."
    break
  fi

  [ -z "${feature_name:-}" ] && feature_name=$(echo "$feature_raw" | sed 's/ |.*//')
  feature_branch=$(branch_name "$feature_name")

  FEATURE_COUNT=$((FEATURE_COUNT + 1))
  EPIC_FEATURE_COUNT=$((EPIC_FEATURE_COUNT + 1))
  update_phase_tracking "implement" "$feature_name"
  timeline_add "$feature_name" "in_progress" 0
  save_state

  log PHASE "FEATURE #$FEATURE_COUNT : $feature_name"
  gh_comment "🚀 **Feature #$FEATURE_COUNT** : $feature_name — démarrage"

  # --- Vérifier les signaux humains ---
  SKIP_CURRENT_FEATURE=false
  check_signals

  # Skip demandé par signal humain → passer à la feature suivante
  if [ "$SKIP_CURRENT_FEATURE" = true ]; then
    log WARN "Feature '$feature_name' skippée par signal humain."
    timeline_update_last "skipped" 0
    # Déplacer le ticket en done (kanban) ou cocher (legacy)
    if [ -n "$current_ticket" ] && [ -f "$current_ticket" ]; then
      move_ticket "$current_ticket" "done"
      regenerate_roadmap_view
    else
      mark_feature_done_bash "$feature_name"
    fi
    run_in_project "git checkout main 2>/dev/null || true"
    continue
  fi

  # --- S'assurer qu'on est sur main avant de commencer ---
  run_in_project "git checkout main 2>/dev/null || true"

  # --- Veille ciblée avant chaque epic ---
  if [ "$ENABLE_RESEARCH" = true ] && [ "$EPIC_FEATURE_COUNT" -eq 1 ]; then
    log PHASE "RESEARCH-EPIC — $feature_name"
    update_phase_tracking "research-epic" "$feature_name"
    run_claude "$(cat <<EOF
VEILLE CIBLÉE avant la feature : $feature_name

1. Comment les concurrents gèrent cette fonctionnalité ? (WebSearch + WebFetch)
2. Best practices UX pour ce type de feature
3. APIs ou données publiques exploitables
4. Mets à jour .orc/research/ si nécessaire
EOF
    )" "$MAX_TURNS_RESEARCH_EPIC" "$LOG_DIR/research-epic-$FEATURE_COUNT.log" "research-epic" "$feature_name" || {
      log WARN "Veille ciblée échouée ou timeout — on continue sans."
    }
  fi

  # --- Auto repo map (avant chaque feature) ---
  generate_repo_map "$PROJECT_DIR"

  # --- Challenger (modèle fort, enrichissement produit avant plan) ---
  challenger_file="$PROJECT_DIR/.orc/logs/challenger-$FEATURE_COUNT.md"
  if [ "${ENABLE_CHALLENGER:-true}" = true ]; then
    # Récupérer le challenger async lancé au cycle précédent (lookahead)
    if [ -n "${CHALLENGER_ASYNC_PID:-}" ]; then
      log INFO "Attente du challenger async (lookahead)..."
      wait "$CHALLENGER_ASYNC_PID" 2>/dev/null || true
      CHALLENGER_ASYNC_PID=""
      collect_challenger_cost "$FEATURE_COUNT"
    fi

    # Challenger synchrone si pas de lookahead (feature 1 ou reprise après crash)
    if [ ! -f "$challenger_file" ]; then
      update_phase_tracking "challenger" "$feature_name"
      log PHASE "CHALLENGER — $feature_name"
      challenger_prompt=$(render_phase "03c-challenger.md" \
        "FEATURE_NAME=$feature_name" \
        "N=$FEATURE_COUNT")
      run_claude "$challenger_prompt" "${MAX_TURNS_CHALLENGER:-3}" \
        "$LOG_DIR/feature-$FEATURE_COUNT-challenger.log" "challenger" "$feature_name" || {
        log WARN "Challenger échoué — on continue sans."
      }
    else
      log INFO "Challenger déjà prêt (lookahead ou reprise) — skip."
    fi
  fi

  # --- Planification rapide (modèle léger, avant implement) ---
  update_phase_tracking "plan" "$feature_name"
  log PHASE "PLAN — $feature_name"
  plan_prompt=$(render_phase "03a-plan.md" \
    "FEATURE_NAME=$feature_name" \
    "N=$FEATURE_COUNT")
  # Injecter le contenu détaillé du ticket kanban dans le plan
  if [ -n "$current_ticket" ] && [ -f "$current_ticket" ]; then
    ticket_specs=$(ticket_context "$current_ticket")
    if [ -n "$ticket_specs" ]; then
      plan_prompt="$plan_prompt

TICKET DETAILLE (specifications, criteres, contexte) :
$ticket_specs"
      log INFO "Contenu ticket kanban injecté dans le prompt de planification."
    fi
  fi

  # Injecter le challenger dans le prompt de plan s'il existe
  if [ -f "${challenger_file:-}" ]; then
    plan_prompt="$plan_prompt

ENRICHISSEMENTS DU CHALLENGER (intègre-les dans ton plan) :
$(cat "$challenger_file")"
    log INFO "Challenger injecté dans le prompt de planification."
  fi

  run_claude "$plan_prompt" "${MAX_TURNS_PLAN:-8}" "$LOG_DIR/feature-$FEATURE_COUNT-plan.log" "plan" "$feature_name" || {
    log WARN "Planification échouée — on continue sans plan."
  }

  # Injecter le plan dans le prompt d'implémentation s'il existe
  plan_file="$PROJECT_DIR/.orc/logs/plan-$FEATURE_COUNT.md"

  # --- Implémentation (avec human notes + feedback + contexte adaptatif) ---
  log PHASE "IMPLEMENT — $feature_name"
  impl_prompt=$(render_phase "03-implement.md" \
    "FEATURE_NAME=$feature_name" \
    "FEATURE_BRANCH=$feature_branch")

  # Injecter le contenu détaillé du ticket kanban dans l'implémentation
  if [ -n "$current_ticket" ] && [ -f "$current_ticket" ]; then
    ticket_specs=$(ticket_context "$current_ticket")
    if [ -n "$ticket_specs" ]; then
      impl_prompt="$impl_prompt

TICKET DETAILLE (specifications, criteres, contexte) :
$ticket_specs"
      log INFO "Contenu ticket kanban injecté dans le prompt d'implémentation."
    fi
  fi

  # Injecter le plan s'il a été produit
  if [ -f "$plan_file" ]; then
    impl_prompt="$impl_prompt

PLAN VALIDÉ POUR CETTE FEATURE (suis-le, ne réinvente pas l'approche) :
$(head -30 "$plan_file")"
    log INFO "Plan injecté dans le prompt d'implémentation."
  else
    log WARN "Plan non trouvé ($plan_file) — implémentation sans plan."
  fi

  # Injecter les notes humaines mid-run si présentes
  human_notes=$(read_human_notes)
  if [ -n "$human_notes" ]; then
    impl_prompt="$impl_prompt
$human_notes"
    log INFO "Notes humaines injectées dans le prompt."
  fi

  # Injecter le feedback GitHub (commentaires sur tracking issue) si activé
  gh_feedback=$(gh_read_feedback)
  if [ -n "$gh_feedback" ]; then
    impl_prompt="$impl_prompt
$gh_feedback"
    log INFO "Feedback GitHub injecté dans le prompt."
  fi

  # Injecter le feedback humain de la feature précédente si présent
  prev_feedback="$PROJECT_DIR/.orc/logs/human-feedback-$((FEATURE_COUNT - 1)).md"
  if [ -f "$prev_feedback" ]; then
    impl_prompt="$impl_prompt

FEEDBACK HUMAIN SUR LA FEATURE PRÉCÉDENTE (en tenir compte) :
$(cat "$prev_feedback")"
    log INFO "Feedback humain de la feature précédente injecté."
  fi

  # Injecter les réponses d'alignement du dernier checkpoint si présentes
  alignment_response=$(read_alignment_response)
  if [ -n "$alignment_response" ]; then
    impl_prompt="$impl_prompt
$alignment_response"
    log INFO "Réponses d'alignement injectées dans le prompt."
  fi

  # Injecter seulement les enrichissements immédiats du challenger (pas les idées futures)
  if [ -f "${challenger_file:-}" ]; then
    challenger_enrichments=""
    challenger_enrichments=$(sed -n '/### Enrichissements immédiats/,/^### [^E]/{ /^### [^E]/d; p; }' "$challenger_file" 2>/dev/null | head -15 || true)
    if [ -n "$challenger_enrichments" ]; then
      impl_prompt="$impl_prompt

ENRICHISSEMENTS PRODUIT (challenger — à intégrer dans l'implémentation) :
$challenger_enrichments"
      log INFO "Enrichissements challenger injectés dans l'implémentation."
    fi
  fi

  run_claude "$impl_prompt" "$MAX_TURNS_PER_INVOCATION" "$LOG_DIR/feature-$FEATURE_COUNT-impl.log" "implement" "$feature_name"

  # --- Lookahead : lancer le challenger de la feature SUIVANTE en arrière-plan ---
  if [ "${ENABLE_CHALLENGER:-true}" = true ]; then
    next_raw=""
    # Kanban: peek le 1er ticket todo (le courant est déjà en in-progress)
    next_raw=$(peek_ticket 1)
    # Fallback legacy
    [ -z "$next_raw" ] && next_raw=$(peek_feature 2)
    if [ -n "$next_raw" ]; then
      next_name=$(echo "$next_raw" | sed 's/ |.*//')
      next_count=$((FEATURE_COUNT + 1))
      next_challenger="$PROJECT_DIR/.orc/logs/challenger-$next_count.md"
      if [ ! -f "$next_challenger" ]; then
        log INFO "Lookahead: lancement challenger pour '$next_name' en arrière-plan..."
        run_challenger_async "$next_name" "$next_count" &
        CHALLENGER_ASYNC_PID=$!
      fi
    fi
  fi

  # --- Lint (rapide, avant les tests) ---
  if [ -n "${LINT_COMMAND:-}" ]; then
    log PHASE "LINT — $feature_name"
    update_phase_tracking "lint" "$feature_name"
    LINT_OUTPUT=$(run_in_project "$LINT_COMMAND 2>&1") && LINT_EXIT=0 || LINT_EXIT=$?
    if [ $LINT_EXIT -ne 0 ]; then
      log WARN "Lint échoué — correction rapide avant les tests..."
      run_claude "Le lint a échoué après l'implémentation de la feature '$feature_name'.

COMMANDE : $LINT_COMMAND
EXIT CODE : $LINT_EXIT
OUTPUT :
$(smart_truncate "$LINT_OUTPUT" 2000)

Corrige les erreurs de lint. Ne change PAS la logique, uniquement le formatage/style." \
        10 "$LOG_DIR/feature-$FEATURE_COUNT-lint.log" "lint" "$feature_name" || true
    else
      log INFO "Lint OK."
    fi
  fi

  # --- Review adversariale (conditionnelle : skip si changement trivial) ---
  changed_files_count=""
  changed_files_count=$(run_in_project "git diff --name-only main 2>/dev/null | wc -l" || echo "0")

  if [ "$changed_files_count" -ge 3 ]; then
    update_phase_tracking "critic" "$feature_name"
    log PHASE "CRITIC — $feature_name ($changed_files_count fichiers)"
    critic_prompt=$(render_phase "03b-critic.md" "FEATURE_NAME=$feature_name")
    critic_system='Tu es un REVIEWER SENIOR sceptique et méticuleux. Tu n'\''as PAS écrit ce code — un autre développeur l'\''a fait. Ton seul objectif est de trouver les bugs, failles et problèmes AVANT que ça parte en production. Tu es payé pour casser, pas pour complimenter. Sois direct et factuel.'
    run_claude "$critic_prompt" 10 "$LOG_DIR/feature-$FEATURE_COUNT-critic.log" "critic" "$feature_name" "$critic_system" || {
      log WARN "Review adversariale échouée — on continue."
    }
  else
    log INFO "Review adversariale skippée ($changed_files_count fichiers — changement trivial)."
  fi

  # --- Test & Fix Loop (avec détection de boucle) ---
  update_phase_tracking "test-fix" "$feature_name"
  save_state
  attempt=0
  tests_passed=false
  LAST_ERROR_HASH=""
  same_error_count=0

  while [ $attempt -lt $MAX_FIX_ATTEMPTS ]; do
    log INFO "Tests — tentative $((attempt + 1))/$MAX_FIX_ATTEMPTS"

    BUILD_OUTPUT=$(run_in_project "$BUILD_COMMAND 2>&1") && BUILD_EXIT=0 || BUILD_EXIT=$?
    TEST_OUTPUT=$(run_in_project "$TEST_COMMAND 2>&1") && TEST_EXIT=0 || TEST_EXIT=$?

    if [ $BUILD_EXIT -eq 0 ] && [ $TEST_EXIT -eq 0 ]; then
      tests_passed=true
      log INFO "Build + tests OK !"
      clear_action_required
      break
    fi

    # Détecter les problèmes d'environnement (vars manquantes, services non configurés)
    combined_output="${BUILD_OUTPUT}${TEST_OUTPUT}"
    if echo "$combined_output" | grep -qiE 'required.*env|env.*required|API.*key.*required|URL.*required|missing.*key|missing.*env|not configured|\.env'; then
      missing_vars=""; env_errors=""; proj_name_short=""
      missing_vars=$(echo "$combined_output" | grep -oiE '[A-Z_]{3,}(URL|KEY|SECRET|TOKEN|ID)' | sort -u | head -5 || true)
      env_errors=$(echo "$combined_output" | grep -iE 'required|missing|env|key|url|not configured' | head -5 || true)
      proj_name_short=$(basename "$SCRIPT_DIR")
      write_action_required "Variables d'environnement manquantes" \
        "Le build ou les tests échouent car des variables d'environnement ne sont pas configurées.

Variables probables : ${missing_vars:-voir erreur ci-dessous}

${env_errors}

Résoudre :
  orc agent env ${proj_name_short}"
      log WARN "Variables d'environnement manquantes détectées — voir 'orc status ${proj_name_short}'"
    fi

    attempt=$((attempt + 1))

    # Détection de boucle : même erreur que la tentative précédente ?
    current_error_hash=$(error_hash "${BUILD_OUTPUT}${TEST_OUTPUT}")
    if [ "$current_error_hash" = "$LAST_ERROR_HASH" ]; then
      same_error_count=$((same_error_count + 1))
    else
      same_error_count=0
    fi
    LAST_ERROR_HASH="$current_error_hash"

    if [ $attempt -lt $MAX_FIX_ATTEMPTS ]; then
      if [ "$same_error_count" -ge 2 ]; then
        # Même erreur 3x de suite → abandon anticipé
        log ERROR "Même erreur détectée 3 fois — boucle de fix, abandon de la feature."
        notify "Feature '$feature_name' bloquée : même erreur en boucle (3x)"
        break
      fi

      # Construire le prompt de fix avec réflexion intégrée (1 invocation au lieu de 2)
      reflection_file="$PROJECT_DIR/.orc/logs/fix-reflections-$FEATURE_COUNT.md"
      fix_prompt=$(write_fix_prompt "$attempt" "$MAX_FIX_ATTEMPTS" \
        "$BUILD_EXIT" "$(smart_truncate "$BUILD_OUTPUT" 3000)" \
        "$TEST_EXIT" "$(smart_truncate "$TEST_OUTPUT" 3000)")

      # Réflexion structurée intégrée au fix (pattern Reflexion sans invocation séparée)
      fix_prompt="$fix_prompt

AVANT DE CODER, écris une RÉFLEXION STRUCTURÉE (3-5 lignes) dans .orc/logs/fix-reflections-$FEATURE_COUNT.md (append) :
- **Ce que j'ai tenté :** [description de l'approche]
- **Pourquoi ça a échoué :** [cause racine identifiée]
- **Ce que je vais essayer :** [nouvelle approche concrète]
Puis applique la correction."

      # Injecter les réflexions passées
      if [ -f "$reflection_file" ]; then
        fix_prompt="$fix_prompt

RÉFLEXIONS DES TENTATIVES PRÉCÉDENTES (en tenir compte pour ne PAS refaire les mêmes erreurs) :
$(cat "$reflection_file")"
      fi

      # Injecter les problèmes connus inter-features (10 dernières entrées max)
      known_issues="$PROJECT_DIR/.orc/known-issues.md"
      if [ -f "$known_issues" ]; then
        fix_prompt="$fix_prompt

PROBLÈMES DÉJÀ RÉSOLUS SUR CE PROJET (solutions connues) :
$(tail -60 "$known_issues")"
      fi

      if [ "$same_error_count" -eq 1 ]; then
        # Même erreur 2x → renforcer le changement d'approche
        fix_prompt="$fix_prompt

ATTENTION : cette erreur est IDENTIQUE à la tentative précédente.
Ton approche actuelle ne fonctionne pas. Tu DOIS :
1. Repenser l'architecture de cette partie du code
2. Essayer une approche radicalement différente
3. Ne PAS réappliquer la même correction"
        log WARN "Même erreur détectée 2 fois — changement d'approche..."
      else
        log WARN "Échec — correction en cours (tentative $attempt)..."
      fi

      run_claude "$fix_prompt" 30 "$LOG_DIR/feature-$FEATURE_COUNT-fix-$attempt.log" "fix" "$feature_name"
    fi
  done

  if [ "$tests_passed" = false ]; then
    log ERROR "Feature '$feature_name' abandonnée après $attempt tentatives."
    TOTAL_FAILURES=$((TOTAL_FAILURES + 1))
    timeline_update_last "failed" "$attempt"
    notify "Feature '$feature_name' abandonnée après $attempt tentatives de fix."
    gh_comment "❌ **Feature #$FEATURE_COUNT** : $feature_name — abandonnée après $attempt tentatives"
    gh_create_abandoned_issue "$feature_name" "$attempt"
    # Retour sur main pour ne pas polluer la feature suivante
    run_in_project "git checkout main 2>/dev/null || true"
  elif [ "$attempt" -gt 0 ]; then
    # Fix réussi après des échecs → mémoriser dans known-issues.md pour les futures features
    known_issues="$PROJECT_DIR/.orc/known-issues.md"
    reflection_file="$PROJECT_DIR/.orc/logs/fix-reflections-$FEATURE_COUNT.md"
    if [ -f "$reflection_file" ]; then
      {
        echo ""
        echo "### Feature #$FEATURE_COUNT: $feature_name (résolu en $attempt tentatives)"
        echo ""
        # Extraire la dernière réflexion (celle qui a mené au fix)
        tail -5 "$reflection_file"
        echo ""
      } >> "$known_issues"
      log INFO "Problème résolu mémorisé dans known-issues.md"
    fi
  fi

  # --- Couverture de tests (tracking + alerte si baisse) ---
  if [ "$tests_passed" = true ] && [ -n "${COVERAGE_COMMAND:-}" ]; then
    log INFO "Couverture de tests en cours..."
    cov_output=""; cov_exit=0; cov_percent=0; prev_cov=0
    cov_output=$(run_in_project "$COVERAGE_COMMAND 2>&1") && cov_exit=0 || cov_exit=$?
    # Extraire le % de couverture (cherche le pattern XX.X% ou XX%)
    cov_percent=$(echo "$cov_output" | grep -Eo '[0-9]+\.?[0-9]*%' | tail -1 | tr -d '%' || echo "")
    if [ -n "$cov_percent" ]; then
      log INFO "Couverture : ${cov_percent}%"
      # Tracker dans state.json
      if command -v jq &>/dev/null && [ -f "$STATE_FILE" ]; then
        prev_cov=$(jq -r '.coverage_percent // ""' "$STATE_FILE" 2>/dev/null)
        jq --arg cov "$cov_percent" '.coverage_percent = $cov' "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
        # Alerte si baisse significative (> 5%)
        if [ -n "$prev_cov" ] && [ "$prev_cov" != "null" ]; then
          drop=0
          drop=$(awk "BEGIN {d = $prev_cov - $cov_percent; printf \"%.0f\", d}")
          if [ "$drop" -gt 5 ] 2>/dev/null; then
            log WARN "Couverture en baisse : ${prev_cov}% → ${cov_percent}% (-${drop}%)"
            notify "Couverture en baisse : ${prev_cov}% → ${cov_percent}%"
          fi
        fi
      fi
    fi
  fi

  # --- Product Review (autocritique métier post-implémentation) ---
  if [ "${ENABLE_PRODUCT_REVIEW:-true}" = true ] && [ "$tests_passed" = true ]; then
    product_review_file="$PROJECT_DIR/.orc/logs/product-review-$FEATURE_COUNT.md"
    if [ ! -f "$product_review_file" ]; then
      log PHASE "PRODUCT-REVIEW — $feature_name"
      update_phase_tracking "product-review" "$feature_name"
      pr_prompt=""
      pr_prompt=$(render_phase "04d-product-review.md" \
        "FEATURE_NAME=$feature_name" \
        "N=$FEATURE_COUNT")
      # Injecter le challenger pour comparer attendu vs réalisé
      if [ -f "${challenger_file:-}" ]; then
        pr_prompt="$pr_prompt

CE QUE LE CHALLENGER ATTENDAIT (comparer avec ce qui a été implémenté) :
$(cat "$challenger_file")"
      fi
      run_claude "$pr_prompt" "${MAX_TURNS_PRODUCT_REVIEW:-5}" \
        "$LOG_DIR/feature-$FEATURE_COUNT-product-review.log" "product-review" "$feature_name" || {
        log WARN "Product review échouée — on continue."
      }
    else
      log INFO "Product review déjà exécutée (reprise) — skip."
    fi
  fi

  # --- Reflect & Evolve ---
  log PHASE "REFLECT — $feature_name"
  update_phase_tracking "reflect" "$feature_name"

  # Métriques bash pré-calculées (évite que Claude perde des turns à les collecter)
  files_changed=""; lines_added=""; lines_deleted=""
  files_changed=$(run_in_project "git diff --name-only HEAD~1 2>/dev/null | wc -l" || echo "?")
  reflect_stat=""
  reflect_stat=$(run_in_project "git diff --stat HEAD~1 2>/dev/null | tail -1" || echo "")
  lines_added=$(echo "$reflect_stat" | awk '{for(i=1;i<=NF;i++) if($i ~ /insertion/) print $(i-1)}')
  lines_deleted=$(echo "$reflect_stat" | awk '{for(i=1;i<=NF;i++) if($i ~ /deletion/) print $(i-1)}')

  reflect_prompt=$(render_phase "05-reflect.md" \
    "FEATURE_NAME=$feature_name" \
    "TESTS_PASSED=$tests_passed" \
    "FIX_ATTEMPTS=$attempt" \
    "N=$FEATURE_COUNT")

  reflect_prompt="$reflect_prompt

MÉTRIQUES (pré-calculées, pas besoin de les recalculer) :
- Fichiers modifiés : $files_changed
- Lignes ajoutées : ${lines_added:-0} | supprimées : ${lines_deleted:-0}
- Tentatives de fix : $attempt
- Coût cumulé : \$$TOTAL_COST_USD"

  run_claude "$reflect_prompt" 15 "$LOG_DIR/feature-$FEATURE_COUNT-reflect.log" "reflect" "$feature_name" || {
    log WARN "Rétrospective échouée — on continue."
  }

  # --- Quality Gate (post-tests, pré-merge) ---
  if [ "$tests_passed" = true ] && [ -n "${QUALITY_COMMAND:-}" ]; then
    log PHASE "QUALITY — $feature_name"
    update_phase_tracking "quality" "$feature_name"
    quality_output=$(run_in_project "$QUALITY_COMMAND 2>&1") && quality_exit=0 || quality_exit=$?

    if [ $quality_exit -ne 0 ]; then
      log WARN "Quality gate échouée — tentative de correction..."
      run_claude "La quality gate a échoué après les tests.

COMMANDE : $QUALITY_COMMAND
EXIT CODE : $quality_exit
OUTPUT :
$(smart_truncate "$quality_output" 3000)

Corrige le problème de qualité sans casser les tests existants.
Exemples de problèmes : performance dégradée, bundle trop gros, couverture insuffisante, score lighthouse en baisse." \
        20 "$LOG_DIR/feature-$FEATURE_COUNT-quality.log" "quality" "$feature_name" || {
        log WARN "Correction quality gate échouée."
      }

      # Re-vérifier
      quality_output=$(run_in_project "$QUALITY_COMMAND 2>&1") && quality_exit=0 || quality_exit=$?
      if [ $quality_exit -ne 0 ]; then
        log WARN "Quality gate toujours en échec — merge quand même (non-bloquant)."
        notify "Quality gate échouée pour '$feature_name' — mergé quand même."
      else
        log INFO "Quality gate OK après correction."
      fi
    else
      log INFO "Quality gate OK."
      gh_post_quality_status "success" "Quality gate passed"
    fi
  fi

  # --- CI distant (bonus, non-bloquant) ---
  if [ "$tests_passed" = true ]; then
    ci_branch=$(run_in_project "git branch --show-current 2>/dev/null || echo ''")
    gh_wait_ci "$ci_branch" || log WARN "CI distant échoué (non-bloquant)."
  fi

  # --- Merge si OK ---
  if [ "$tests_passed" = true ]; then
    current_branch=$(run_in_project "git branch --show-current 2>/dev/null || echo ''")
    if [ -n "$current_branch" ] && [ "$current_branch" != "main" ]; then
      safe_feature_name="${feature_name//\'/}"

      # Preflight checks (sécurité : fichiers sensibles, suppressions massives)
      if ! preflight_merge "$feature_name"; then
        log ERROR "Feature '$feature_name' bloquée par les preflight checks."
        TOTAL_FAILURES=$((TOTAL_FAILURES + 1))
        timeline_update_last "blocked" "$attempt"
        notify "Feature '$feature_name' bloquée par preflight checks — intervention requise."
        write_action_required "Preflight checks bloqués pour '$feature_name'" \
          "La feature modifie des fichiers sensibles ou contient des suppressions massives. Vérifiez le diff et approuvez manuellement."
        run_in_project "git checkout main 2>/dev/null || true"
        # Passer directement à la feature suivante
        CURRENT_PHASE=""
        CURRENT_FEATURE=""
        save_state
        continue
      fi

      # Générer le change report avant merge
      generate_change_report "$feature_name" "$FEATURE_COUNT" "$attempt"

      if gh_pr_mode; then
        # === MODE PR : créer une PR, merger via GitHub ===
        pr_url=$(gh_create_pr "$current_branch" "$safe_feature_name" "$attempt") || pr_url=""

        if [ -n "$pr_url" ]; then
          gh_merge_pr "$pr_url" || {
            # Fallback : merge local si PR échoue
            log WARN "Fallback → merge local."
            if [ "$REQUIRE_HUMAN_APPROVAL" = true ] && [ -t 0 ]; then
              human_pause "Approuver le merge de : $feature_name"
            fi
            run_in_project "git checkout main 2>/dev/null && git merge --no-ff '$current_branch' -m \"feat: $safe_feature_name\" 2>/dev/null || true"
          }
        else
          # Pas de PR → merge local
          if [ "$REQUIRE_HUMAN_APPROVAL" = true ] && [ -t 0 ]; then
            human_pause "Approuver le merge de : $feature_name"
          fi
          run_in_project "git checkout main 2>/dev/null && git merge --no-ff '$current_branch' -m \"feat: $safe_feature_name\" 2>/dev/null || true"
        fi
      else
        # === MODE LOCAL : merge direct (comportement original) ===
        if [ "$REQUIRE_HUMAN_APPROVAL" = true ]; then
          human_pause "Approuver le merge de : $feature_name"
        fi
        run_in_project "git checkout main 2>/dev/null && git merge --no-ff '$current_branch' -m \"feat: $safe_feature_name\" 2>/dev/null || true"
      fi
    fi

    log INFO "Feature '$feature_name' mergée."
    # Déplacer le ticket en done (kanban) ou cocher (legacy)
    if [ -n "$current_ticket" ] && [ -f "$current_ticket" ]; then
      move_ticket "$current_ticket" "done"
      regenerate_roadmap_view
    else
      mark_feature_done_bash "$feature_name"
    fi
    # Changelog auto : ajouter l'entrée pour cette feature
    update_changelog "$feature_name" "$attempt"
    # Vérification fonctionnelle post-merge
    run_functional_check "$feature_name"
    # Mise à jour timeline
    timeline_update_last "done" "$attempt"
    notify "Feature #$FEATURE_COUNT '$feature_name' mergée (\$$TOTAL_COST_USD)"
    gh_comment "✅ **Feature #$FEATURE_COUNT** : $feature_name — mergée (fix: $attempt, coût: \$${TOTAL_COST_USD})"
    gh_sync_roadmap  # Fermer l'issue correspondante
  fi

  CURRENT_PHASE=""
  CURRENT_FEATURE=""
  save_state

  # --- Reset compteur epic + acceptance ---
  if [ "$EPIC_FEATURE_COUNT" -ge "$EPIC_SIZE" ]; then
    epic_number=$(( (FEATURE_COUNT - 1) / EPIC_SIZE + 1 ))
    gh_sync_milestone "Epic $epic_number"

    # Phase acceptance : valider les user stories de cet epic
    log PHASE "ACCEPTANCE — Epic $epic_number"
    update_phase_tracking "acceptance" "epic-$epic_number"
    acceptance_prompt=""
    acceptance_prompt=$(render_phase "04b-acceptance.md" \
      "EPIC_NUMBER=$epic_number" \
      "FEATURE_COUNT=$FEATURE_COUNT")
    # DEV_COMMAND ajouté en fin de prompt (pas render_phase, car peut contenir / ou \)
    acceptance_prompt="$acceptance_prompt

COMMANDE DEV SERVER : ${DEV_COMMAND:-npm run dev}"
    run_claude "$acceptance_prompt" 20 "$LOG_DIR/acceptance-epic-$epic_number.log" "acceptance" "epic-$epic_number" || {
      log WARN "Acceptance échouée — on continue."
    }

    # Phase QA : test fonctionnel réel (curl + navigateur)
    if [ -n "${DEV_COMMAND:-}" ]; then
      qa_port="${DEV_PORT:-3000}"
      log PHASE "QA — Epic $epic_number"
      update_phase_tracking "qa" "epic-$epic_number"

      # Kill tout process résiduel sur le port (acceptance précédente, crash, etc.)
      lsof -ti:"$qa_port" | xargs kill 2>/dev/null || true

      qa_prompt=""
      qa_prompt=$(render_phase "04c-qa.md" \
        "EPIC_NUMBER=$epic_number" \
        "FEATURE_COUNT=$FEATURE_COUNT" \
        "PORT=$qa_port")
      qa_prompt="$qa_prompt

COMMANDE DEV SERVER : ${DEV_COMMAND}
PORT : ${qa_port}"
      run_claude "$qa_prompt" 30 "$LOG_DIR/qa-epic-$epic_number.log" "qa" "epic-$epic_number" || {
        log WARN "QA échouée — on continue."
      }

      # Cleanup : kill le serveur dev si Claude ne l'a pas fait
      lsof -ti:"$qa_port" | xargs kill 2>/dev/null || true
    else
      log INFO "QA skippée (pas de DEV_COMMAND configurée)."
    fi

    # Mise à jour incrémentale du README (quick, modèle léger)
    run_claude "Mets à jour le README.md du projet pour refléter les features de l'Epic $epic_number.
Lis .orc/ROADMAP.md pour voir les features terminées. Lis le README actuel.
Ajoute/mets à jour la section 'Features' avec les fonctionnalités implémentées.
Garde le README concis et à jour. Ne réécris pas tout — édite seulement ce qui a changé." \
      5 "$LOG_DIR/readme-update-epic-$epic_number.log" "reflect" "epic-$epic_number" || true

    EPIC_FEATURE_COUNT=0
  fi

  # --- Méta-rétrospective toutes les N features ---
  if [ $((FEATURE_COUNT % META_RETRO_FREQUENCY)) -eq 0 ]; then
    log PHASE "MÉTA-RÉTROSPECTIVE — $FEATURE_COUNT features"
    update_phase_tracking "meta-retro" ""
    retro_prompt=$(render_phase "06-meta-retro.md" "FEATURE_COUNT=$FEATURE_COUNT")
    run_claude "$retro_prompt" "$MAX_TURNS_RESEARCH_TREND" "$LOG_DIR/meta-retro-$FEATURE_COUNT.log" "meta-retro" || {
      log WARN "Méta-rétrospective échouée — on continue."
    }
    log INFO "Méta-rétrospective terminée."
    gh_create_release "v0.$FEATURE_COUNT.0" "Meta-retro après $FEATURE_COUNT features"
    gh_sync_roadmap

    # Phase tech-debt : déclencher si signaux de dette (trop d'échecs)
    if [ "$TOTAL_FAILURES" -gt 0 ] && [ $((TOTAL_FAILURES * 100 / FEATURE_COUNT)) -ge 30 ]; then
      log PHASE "TECH-DEBT — $TOTAL_FAILURES échecs sur $FEATURE_COUNT features (>30%)"
      update_phase_tracking "tech-debt" ""
      debt_prompt=""
      debt_prompt=$(render_phase "06b-tech-debt.md" \
        "FEATURE_COUNT=$FEATURE_COUNT" \
        "TOTAL_FAILURES=$TOTAL_FAILURES")
      run_claude "$debt_prompt" 20 "$LOG_DIR/tech-debt-$FEATURE_COUNT.log" "tech-debt" || {
        log WARN "Tech-debt échouée — on continue."
      }
    fi
  fi

  # --- Pause humaine configurable ---
  if [ "$PAUSE_EVERY_N_FEATURES" -gt 0 ] && [ $((FEATURE_COUNT % PAUSE_EVERY_N_FEATURES)) -eq 0 ]; then
    human_pause "Checkpoint toutes les $PAUSE_EVERY_N_FEATURES features"
  fi

done

# ============================================================
# PHASE FINALE — ÉVOLUTION OU FIN
# ============================================================

if [ ! -f "$PROJECT_DIR/DONE.md" ]; then
  workflow_transition "evolve"
  EVOLVE_CYCLES=$((EVOLVE_CYCLES + 1))
  max_evolve="${MAX_EVOLVE_CYCLES:-0}"

  if [ "$max_evolve" -gt 0 ] && [ "$EVOLVE_CYCLES" -gt "$max_evolve" ]; then
    log WARN "Limite de cycles evolve atteinte ($EVOLVE_CYCLES/$max_evolve) — arrêt."
    notify "Limite de cycles evolve atteinte ($max_evolve). Projet terminé automatiquement."
    MAIN_LOOP_CONTINUE=false
  else
    log PHASE "PHASE FINALE — ÉVOLUTION (cycle $EVOLVE_CYCLES)"
    update_phase_tracking "evolve" "cycle-$EVOLVE_CYCLES"

    # Phase 1 : Score de maturité (evolve classique — décide DONE ou continue)
    evolve_prompt=$(render_phase "07-evolve.md")
    run_claude "$evolve_prompt" 30 "$LOG_DIR/07-evolve.log" "evolve"

    # Phase 2 : Si pas DONE → auto-brainstorm (remplace les 3-5 features basiques d'evolve)
    todo_before=0
    if [ ! -f "$PROJECT_DIR/DONE.md" ]; then
      todo_before=$(count_todo_tickets)

      if [ "${ENABLE_AUTO_BRAINSTORM:-true}" = true ]; then
        run_auto_brainstorm "$EVOLVE_CYCLES" || {
          log WARN "Auto-brainstorm echoue — aucun ticket cree. Relancer ou valider la roadmap manuellement."
        }
      fi

      # Régénérer la vue ROADMAP.md
      regenerate_roadmap_view
    fi

    if [ ! -f "$PROJECT_DIR/DONE.md" ] && (has_todo_tickets || grep -q '^\- \[ \]' "$PROJECT_DIR/.orc/ROADMAP.md" 2>/dev/null); then
      # Compter les features ajoutées par l'IA (delta = après - avant)
      new_features=$(( $(count_todo_tickets) - todo_before ))
      [ "$new_features" -lt 0 ] && new_features=0
      AI_ROADMAP_ADDS=$((AI_ROADMAP_ADDS + new_features))
      log INFO "Nouvelles features ajoutées par l'IA : $new_features (total IA: $AI_ROADMAP_ADDS)"

      # Forcer une pause si trop de features ajoutées par l'IA
      max_ai_adds="${MAX_AI_ROADMAP_ADDS:-5}"
      if [ "$max_ai_adds" -gt 0 ] && [ "$AI_ROADMAP_ADDS" -ge "$max_ai_adds" ]; then
        log WARN "L'IA a ajouté $AI_ROADMAP_ADDS features à la roadmap — pause de validation requise."
        notify "L'IA a ajouté $AI_ROADMAP_ADDS features à la roadmap. Validation humaine recommandée."
        human_pause "L'IA a ajouté $AI_ROADMAP_ADDS features — valider la direction ?"
        AI_ROADMAP_ADDS=0  # Reset après validation
      fi

      # --- Checkpoint d'alignement entre cycles ---
      if [ "${ALIGNMENT_CHECK:-true}" = true ]; then
        log PHASE "CHECKPOINT D'ALIGNEMENT — Cycle $EVOLVE_CYCLES"
        update_phase_tracking "alignment" "cycle-$EVOLVE_CYCLES"

        # Générer le rapport d'alignement via Claude
        alignment_prompt=$(render_phase "07b-alignment.md" "CYCLE=$EVOLVE_CYCLES")
        run_claude "$alignment_prompt" 15 "$LOG_DIR/07b-alignment-$EVOLVE_CYCLES.log" "alignment" || {
          log WARN "Génération rapport d'alignement échouée — on continue."
        }

        # Arrêter le run et attendre le prochain start pour le wizard
        log INFO "Rapport d'alignement généré. Arrêt pour validation humaine."
        notify "Cycle $EVOLVE_CYCLES terminé. Rapport d'alignement prêt. Relancer avec 'orc agent start' pour le wizard."
        workflow_transition "alignment_pending"
        RUN_STATUS="alignment_pending"
        RUN_ENDED_AT=$(date -Iseconds)
        save_state
        print_cost_summary
        exit 0
      else
        log INFO "Nouvelles features ajoutées — relancement de la boucle."
        workflow_transition "features"
        save_state
      fi
    else
      MAIN_LOOP_CONTINUE=false
    fi
  fi
else
  MAIN_LOOP_CONTINUE=false
fi

done  # fin MAIN_LOOP (while MAIN_LOOP_CONTINUE)

# ============================================================
# PHASE POST-PROJET — AUTO-AMÉLIORATION DE L'ORCHESTRATEUR
# ============================================================

workflow_transition "post-project"
notify "Projet terminé ! Features: $FEATURE_COUNT, Échecs: $TOTAL_FAILURES, Coût: \$$TOTAL_COST_USD"

# Skip self-improve si déjà fait (reprise après crash en post-project)
if [ "$SKIP_TO_POST_PROJECT" = true ] && [ -f "$PROJECT_DIR/orchestrator-improvements.md" ]; then
  log INFO "Auto-amélioration déjà faite — skip (reprise post-projet)."
else
log PHASE "AUTO-AMÉLIORATION DE L'ORCHESTRATEUR"

run_claude "$(cat <<'IMPROVE'
PHASE AUTO-AMÉLIORATION DE L'ORCHESTRATEUR

Le projet est terminé. Analyse les logs et améliore l'orchestrateur.

Lis : .orc/logs/retrospective-*.md, meta-retrospective-*.md, fix-reflections-*.md,
human-feedback-*.md, CLAUDE.md, .claude/skills/

TÂCHE 1 — Analyse et améliorations proposées :
Produis `orchestrator-improvements.md` avec : phases à modifier, config à ajuster,
nouvelles skills, garde-fous, conventions bash. Sois concret.

TÂCHE 2 — Si le fichier .claude/skills/stack-conventions.md existe :
Ajoute les conventions bash et anti-patterns découverts (sans doublons).

TÂCHE 3 — Si codebase/INDEX.md existe :
Vérifie s'il faut le mettre à jour (nouvelles fonctions, structure changée).
Garde-le compact (max 40 lignes).

Fais les 3 tâches en une seule session.
IMPROVE
)" 30 "$LOG_DIR/orchestrator-improvements.log" "self-improve"

log INFO "Suggestions d'amélioration : orchestrator-improvements.md"

# Extraire les learnings et les copier dans le template pour les futurs projets
if [ -f "$PROJECT_DIR/orchestrator-improvements.md" ]; then
  _orc_real_dir=$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || realpath "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")")
  learning_file="$_orc_real_dir/learnings/$(date +%Y-%m-%d)-${PROJECT_NAME:-project}.md"
  {
    echo "# Learnings — ${PROJECT_NAME:-project}"
    echo "Date : $(date '+%Y-%m-%d')"
    echo "Features : $FEATURE_COUNT | Échecs : $TOTAL_FAILURES | Coût : \$$TOTAL_COST_USD"
    echo ""
    cat "$PROJECT_DIR/orchestrator-improvements.md"
  } > "$learning_file"
  log INFO "Learnings sauvés dans le template : $learning_file"
fi
fi  # fin du guard SKIP_TO_POST_PROJECT self-improve

# ============================================================
# DOCUMENTATION UTILISATEUR
# ============================================================

log PHASE "DOCUMENTATION UTILISATEUR"
update_phase_tracking "user-docs" ""
run_claude "$(cat "$SCRIPT_DIR/phases/08-user-docs.md")" 15 "$LOG_DIR/08-user-docs.log" "user-docs" || {
  log WARN "Génération doc utilisateur échouée — pas grave."
}

# ============================================================
# BILAN FINAL
# ============================================================

gh_sync_roadmap
gh_create_release "v1.0.0" "Projet terminé — $FEATURE_COUNT features"
gh_close_tracking_issue

# Vérification fonctionnelle finale
if [ -n "${FUNCTIONAL_CHECK_COMMAND:-}" ]; then
  log INFO "Vérification fonctionnelle finale..."
  final_func_output=$(run_in_project "$FUNCTIONAL_CHECK_COMMAND 2>&1") && final_func_exit=0 || final_func_exit=$?
  if [ $final_func_exit -eq 0 ]; then
    log INFO "App fonctionnelle en fin de run ✓"
    LAST_FUNCTIONAL_CHECK=true
  else
    log ERROR "App NON fonctionnelle en fin de run ✗"
    LAST_FUNCTIONAL_CHECK=false
    notify "ALERTE : App non fonctionnelle en fin de run !"
  fi
  save_state
fi

workflow_transition "done"
CURRENT_PHASE="done"
CURRENT_FEATURE=""
RUN_STATUS="completed"
RUN_ENDED_AT=$(date -Iseconds)
save_state

# Déploiement automatique si configuré (post-completion, ne bloque pas le statut "done")
if [ -n "${DEPLOY_COMMAND:-}" ]; then
  if [ "${LAST_FUNCTIONAL_CHECK:-null}" = "true" ]; then
    log PHASE "DÉPLOIEMENT"
    log INFO "Commande : $DEPLOY_COMMAND"
    deploy_output=$(run_in_project "$DEPLOY_COMMAND 2>&1") && deploy_exit=0 || deploy_exit=$?
    if [ $deploy_exit -eq 0 ]; then
      log INFO "Déploiement réussi ✓"
      notify "Déploiement réussi ! Projet $PROJECT_NAME déployé."
    else
      log ERROR "Déploiement échoué (exit $deploy_exit)"
      log ERROR "Output : $(smart_truncate "$deploy_output" 1000)"
      notify "Déploiement échoué pour $PROJECT_NAME."
    fi
  elif [ "${LAST_FUNCTIONAL_CHECK:-null}" = "false" ]; then
    log WARN "Déploiement ignoré — app non fonctionnelle."
  else
    log INFO "Déploiement ignoré — aucune vérification fonctionnelle configurée."
  fi
fi

log PHASE "TERMINÉ"
log INFO "Features complétées : $FEATURE_COUNT"
log INFO "Features en échec : $TOTAL_FAILURES"

if [ -f "$PROJECT_DIR/DONE.md" ]; then
  log INFO "Le projet est déclaré terminé. Voir DONE.md"
else
  log WARN "L'orchestrateur s'est arrêté (limite MAX_FEATURES=$MAX_FEATURES atteinte)."
fi

print_cost_summary

# Calcul de la durée du run
run_end_time=$(date +%s)
run_start_epoch=$(date -d "$RUN_STARTED_AT" +%s 2>/dev/null || echo "$run_end_time")
run_duration_s=$((run_end_time - run_start_epoch))
run_hours=$((run_duration_s / 3600))
run_minutes=$(( (run_duration_s % 3600) / 60 ))
if [ $run_hours -gt 0 ]; then
  run_duration_str="${run_hours}h${run_minutes}m"
else
  run_duration_str="${run_minutes}m"
fi

echo ""
printf "${GREEN}═══════════════════════════════════════════════════${NC}\n"
printf "${GREEN}  Agent terminé.${NC}\n"
printf "${GREEN}  Features : %s | Échecs : %s | Durée : %s${NC}\n" "$FEATURE_COUNT" "$TOTAL_FAILURES" "$run_duration_str"
printf "${GREEN}  Coût total : \$%s USD${NC}\n" "$TOTAL_COST_USD"
if [ -n "${FUNCTIONAL_CHECK_COMMAND:-}" ]; then
  if [ "${LAST_FUNCTIONAL_CHECK:-}" = "true" ]; then
    printf "${GREEN}  App fonctionnelle : ✓${NC}\n"
  else
    printf "${RED}  App fonctionnelle : ✗${NC}\n"
  fi
fi
printf "${GREEN}  Logs : %s/${NC}\n" "$LOG_DIR"
printf "${GREEN}  Projet : %s/${NC}\n" "$PROJECT_DIR"
if [ -f "$PROJECT_DIR/orchestrator-improvements.md" ]; then
  printf "${GREEN}  Améliorations : %s/orchestrator-improvements.md${NC}\n" "$PROJECT_DIR"
fi
printf "${GREEN}═══════════════════════════════════════════════════${NC}\n"
