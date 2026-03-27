#!/bin/bash
set -euo pipefail

# ============================================================
# Agent Autonome Claude — Orchestrateur principal
# ============================================================
#
# Usage :
#   ./orchestrator.sh    — lance l'agent autonome (BRIEF.md requis)
#
# Ce script doit être lancé depuis un workspace créé par init.sh.
# Il crée project/ (si pas déjà fait) et pilote Claude en boucle.
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

# === TRACKING TOKENS ===
TOKENS_FILE="$SCRIPT_DIR/.orc/tokens.json"
TOTAL_INPUT_TOKENS=0
TOTAL_OUTPUT_TOKENS=0
TOTAL_COST_USD=0

# Coût par token (Claude Opus 4, en USD) — ajuster selon le modèle
COST_PER_INPUT_TOKEN=0.000015
COST_PER_OUTPUT_TOKEN=0.000075

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
  # Nettoyer le fichier temporaire
  [ -n "$TMP_JSON" ] && rm -f "$TMP_JSON"
  # Sauvegarder l'état
  save_state
  # Libérer le lock
  rm -f "$LOCKFILE"
  log INFO "Nettoyage terminé."
}

trap cleanup EXIT INT TERM

# === FONCTIONS UTILITAIRES ===

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
  cat > "$STATE_FILE" << STATEEOF
{"feature_count":$FEATURE_COUNT,"epic_feature_count":$EPIC_FEATURE_COUNT,"total_failures":$TOTAL_FAILURES,"evolve_cycles":$EVOLVE_CYCLES,"ai_roadmap_adds":$AI_ROADMAP_ADDS}
STATEEOF
}

# Restaure l'état si disponible
restore_state() {
  if command -v jq &> /dev/null && [ -f "$STATE_FILE" ]; then
    FEATURE_COUNT=$(jq -r '.feature_count // 0' "$STATE_FILE")
    EPIC_FEATURE_COUNT=$(jq -r '.epic_feature_count // 0' "$STATE_FILE")
    TOTAL_FAILURES=$(jq -r '.total_failures // 0' "$STATE_FILE")
    EVOLVE_CYCLES=$(jq -r '.evolve_cycles // 0' "$STATE_FILE")
    AI_ROADMAP_ADDS=$(jq -r '.ai_roadmap_adds // 0' "$STATE_FILE")
    log INFO "État restauré : features=$FEATURE_COUNT, échecs=$TOTAL_FAILURES, evolve_cycles=$EVOLVE_CYCLES"
  fi
}

# Initialise le fichier de tracking tokens
init_tokens() {
  mkdir -p "$LOG_DIR"
  if [ ! -f "$TOKENS_FILE" ]; then
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
    '
    .total_input_tokens = $total_in |
    .total_output_tokens = $total_out |
    .total_cost_usd = $total_cost |
    .invocations += 1 |
    .by_phase[$phase].input_tokens = ((.by_phase[$phase].input_tokens // 0) + $input) |
    .by_phase[$phase].output_tokens = ((.by_phase[$phase].output_tokens // 0) + $output) |
    .by_phase[$phase].cost_usd = ((.by_phase[$phase].cost_usd // 0) + $cost) |
    .by_phase[$phase].calls = ((.by_phase[$phase].calls // 0) + 1) |
    (if $feature != "" then
      .by_feature[$feature].input_tokens = ((.by_feature[$feature].input_tokens // 0) + $input) |
      .by_feature[$feature].output_tokens = ((.by_feature[$feature].output_tokens // 0) + $output) |
      .by_feature[$feature].cost_usd = ((.by_feature[$feature].cost_usd // 0) + $cost)
    else . end) |
    .history += [{
      "timestamp": $ts,
      "phase": $phase,
      "feature": $feature,
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
run_claude() {
  local prompt="$1"
  local max_turns="${2:-$MAX_TURNS_PER_INVOCATION}"
  local log_file="${3:-/dev/null}"
  local phase_name="${4:-unknown}"
  local feature_name="${5:-}"

  local exit_code=0
  TMP_JSON=$(mktemp)
  local start_time
  start_time=$(date +%s)

  log INFO "→ Claude lancé [phase=$phase_name] [max_turns=$max_turns]..."

  # Préfixe : forcer Claude à rester dans le répertoire projet
  # + contexte adaptatif : indiquer quels fichiers de connaissance consulter selon la phase
  local context_hint=""
  case "$phase_name" in
    implement)
      context_hint="
CONTEXTE PROJET — Lis dans cet ordre :
1. .orc/codebase/INDEX.md (carte sémantique — TOUJOURS lire en premier)
2. .orc/codebase/auto-map.md (carte auto-générée des exports — vérité du code)
3. Les fichiers de détail .orc/codebase/*.md pertinents pour cette feature (PAS tous)
4. .claude/skills/stack-conventions.md (conventions à respecter)"
      ;;
    fix)
      context_hint="
CONTEXTE PROJET — Lis si pertinent :
1. .orc/codebase/auto-map.md (pour localiser les modules impliqués)
2. .orc/codebase/security.md (si l'erreur est liée à la sécurité)
3. .claude/skills/fix-tests.md (workflow de correction)"
      ;;
    strategy)
      context_hint="
CONTEXTE PROJET — Lis dans cet ordre :
1. .orc/codebase/INDEX.md (état actuel du projet)
2. .orc/codebase/architecture.md (décisions techniques en place)
3. .orc/research/INDEX.md (insights marché)"
      ;;
    reflect)
      context_hint="
CONTEXTE PROJET — Mets à jour :
1. .orc/codebase/auto-map.md est déjà à jour (auto-généré) — lis-le pour vérifier
2. .orc/codebase/INDEX.md + les fichiers de détail impactés par cette feature
3. .claude/skills/stack-conventions.md si nouveaux patterns"
      ;;
    meta-retro)
      context_hint="
CONTEXTE PROJET — Auditer :
1. .orc/codebase/INDEX.md — est-il à jour vs auto-map.md ?
2. .orc/codebase/auto-map.md — vérité du code actuel
3. Tous les fichiers .orc/codebase/*.md — vérifier la cohérence avec le code réel"
      ;;
  esac

  local full_prompt="IMPORTANT: Tu travailles dans le répertoire courant ($(basename "$PROJECT_DIR")/). Tous les fichiers que tu crées ou modifies doivent être dans ce répertoire. Ne navigue JAMAIS vers un répertoire parent (..) et n'utilise PAS de chemins absolus vers des dossiers parents.
${context_hint}

$prompt"

  # Lancer Claude en background avec output stream-JSON (JSONL)
  # stream-json produit des événements au fil de l'eau → le watchdog
  # peut détecter les vrais stalls (contrairement à json qui bufferise tout)
  local model_flag=""
  if [ -n "${CLAUDE_MODEL:-}" ]; then
    model_flag="--model $CLAUDE_MODEL"
  fi

  # shellcheck disable=SC2086
  claude -p "$full_prompt" \
    --dangerously-skip-permissions \
    --max-turns "$max_turns" \
    --output-format stream-json \
    --verbose \
    $model_flag \
    -d "$PROJECT_DIR" > "$TMP_JSON" 2>&1 &

  CLAUDE_PID=$!

  # Monitoring : heartbeat + watchdog stall detection
  local dots=0
  local last_size=0
  local stall_count=0
  local timeout="${CLAUDE_TIMEOUT:-0}"

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

  track_tokens "$phase_name" "$feature_name" "$json_output"

  if [ -n "${MAX_BUDGET_USD:-}" ]; then
    local over_budget
    over_budget=$(awk "BEGIN {print ($TOTAL_COST_USD > $MAX_BUDGET_USD) ? \"yes\" : \"no\"}")
    if [ "$over_budget" = "yes" ]; then
      log ERROR "Budget dépassé ! \$${TOTAL_COST_USD} > \$${MAX_BUDGET_USD}"
      print_cost_summary
      rm -f "$TMP_JSON"
      TMP_JSON=""
      exit 1
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
  ( cd "$PROJECT_DIR" && eval "$@" )
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
    save_state
    print_cost_summary
    exit 0
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
  run_in_project "git remote get-url '$remote' 2>/dev/null" \
    | sed -E 's#^(https://github\.com/|git@github\.com:)##; s#\.git$##'
}

# Crée l'issue de tracking pour un run orchestrateur
gh_create_tracking_issue() {
  if ! gh_available || [ "${GITHUB_TRACKING_ISSUE:-false}" != "true" ]; then
    return 0
  fi

  local repo_slug
  repo_slug=$(gh_repo_slug)
  if [ -z "$repo_slug" ]; then
    log WARN "GitHub: impossible de déterminer le repo — tracking issue non créée."
    return 1
  fi

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

  TRACKING_ISSUE_NUMBER=$(echo "$issue_url" | grep -oE '[0-9]+$')
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
  repo_slug=$(gh_repo_slug)

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
  repo_slug=$(gh_repo_slug)
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
  repo_slug=$(gh_repo_slug)

  # Extraire le numéro de PR
  local pr_number
  pr_number=$(echo "$pr_url" | grep -oE '[0-9]+$')

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
  repo_slug=$(gh_repo_slug)

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
  repo_slug=$(gh_repo_slug)

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
  repo_slug=$(gh_repo_slug)

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
  repo_slug=$(gh_repo_slug)
  if [ -z "$repo_slug" ]; then return 1; fi

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
    issue_num=$(echo "$issue_url" | grep -oE '[0-9]+$')
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
    issue_num=$(grep -F "$feature_name" "$map_file" 2>/dev/null | tail -1 | cut -f2)
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
  repo_slug=$(gh_repo_slug)
  if [ -z "$repo_slug" ]; then return 1; fi

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
  repo_slug=$(gh_repo_slug)

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
  repo_slug=$(gh_repo_slug)
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
  repo_slug=$(gh_repo_slug)
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
  repo_slug=$(gh_repo_slug)
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
  echo "$output" | head -20 | md5sum | cut -d' ' -f1
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
      q|Q) log INFO "Arrêt demandé par l'utilisateur." ; print_cost_summary ; exit 0 ;;
      *) echo "Choix invalide." ;;
    esac
  done
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
# PHASE 0 — BOOTSTRAP
# ============================================================

if [ ! -f "$PROJECT_DIR/CLAUDE.md" ]; then
  log PHASE "PHASE 0 — BOOTSTRAP"

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
  run_claude "$local_prompt" 60 "$LOG_DIR/00-bootstrap.log" "bootstrap"

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
  log PHASE "PHASE 1 — RECHERCHE INITIALE"

  local_prompt=$(render_phase "01-research.md")
  run_claude "$local_prompt" "$MAX_TURNS_RESEARCH_INITIAL" "$LOG_DIR/01-research.log" "research-initial"

  log INFO "Recherche initiale terminée."
fi

# ============================================================
# PHASE 2 — STRATÉGIE
# ============================================================

if ! grep -q '^\- \[ \]' "$PROJECT_DIR/.orc/ROADMAP.md" 2>/dev/null; then
  log PHASE "PHASE 2 — STRATÉGIE"

  local_prompt=$(render_phase "02-strategy.md")
  run_claude "$local_prompt" 30 "$LOG_DIR/02-strategy.log" "strategy"

  log INFO "Roadmap générée."
  gh_sync_roadmap
fi

# ============================================================
# PHASE 3 — BOUCLE PRINCIPALE
# ============================================================

log PHASE "PHASE 3 — BOUCLE DE DÉVELOPPEMENT"

while [ $FEATURE_COUNT -lt $MAX_FEATURES ]; do

  feature_raw=$(next_feature)

  if [ -z "$feature_raw" ]; then
    log INFO "Roadmap vide — passage en phase d'évolution."
    break
  fi

  feature_name=$(echo "$feature_raw" | sed 's/ |.*//')
  feature_branch=$(branch_name "$feature_name")

  FEATURE_COUNT=$((FEATURE_COUNT + 1))
  EPIC_FEATURE_COUNT=$((EPIC_FEATURE_COUNT + 1))
  save_state

  log PHASE "FEATURE #$FEATURE_COUNT : $feature_name"
  gh_comment "🚀 **Feature #$FEATURE_COUNT** : $feature_name — démarrage"

  # --- Vérifier les signaux humains ---
  check_signals

  # --- S'assurer qu'on est sur main avant de commencer ---
  run_in_project "git checkout main 2>/dev/null || true"

  # --- Veille ciblée avant chaque epic ---
  if [ "$ENABLE_RESEARCH" = true ] && [ "$EPIC_FEATURE_COUNT" -eq 1 ]; then
    log INFO "Veille ciblée avant l'epic..."
    run_claude "$(cat <<EOF
VEILLE CIBLÉE avant la feature : $feature_name

1. Comment les concurrents gèrent cette fonctionnalité ? (WebSearch + WebFetch)
2. Best practices UX pour ce type de feature
3. APIs ou données publiques exploitables
4. Mets à jour .orc/research/ et ajuste les specs dans .orc/ROADMAP.md si nécessaire
EOF
    )" "$MAX_TURNS_RESEARCH_EPIC" "$LOG_DIR/research-epic-$FEATURE_COUNT.log" "research-epic" "$feature_name" || {
      log WARN "Veille ciblée échouée ou timeout — on continue sans."
    }
  fi

  # --- Auto repo map (avant chaque feature) ---
  generate_repo_map "$PROJECT_DIR"

  # --- Implémentation (avec human notes + feedback + contexte adaptatif) ---
  log INFO "Implémentation en cours..."
  impl_prompt=$(render_phase "03-implement.md" \
    "FEATURE_NAME=$feature_name" \
    "FEATURE_BRANCH=$feature_branch")

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

  run_claude "$impl_prompt" "$MAX_TURNS_PER_INVOCATION" "$LOG_DIR/feature-$FEATURE_COUNT-impl.log" "implement" "$feature_name"

  # --- Test & Fix Loop (avec détection de boucle) ---
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
      break
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

      # Réflexion structurée (pattern Reflexion) : l'IA écrit ce qu'elle a tenté et pourquoi ça a échoué
      reflection_file="$PROJECT_DIR/.orc/logs/fix-reflections-$FEATURE_COUNT.md"
      run_claude "Tu viens d'essayer de corriger la feature '$feature_name' (tentative $attempt/$MAX_FIX_ATTEMPTS) et ça a échoué.

BUILD (exit $BUILD_EXIT):
${BUILD_OUTPUT: -1500}

TESTS (exit $TEST_EXIT):
${TEST_OUTPUT: -1500}

Écris une RÉFLEXION STRUCTURÉE (3-5 lignes max) dans ce format :
- **Ce que j'ai tenté :** [description de l'approche]
- **Pourquoi ça a échoué :** [cause racine identifiée]
- **Ce que je dois essayer :** [nouvelle approche concrète]

Écris cette réflexion dans le fichier .orc/logs/fix-reflections-$FEATURE_COUNT.md (append).
Ne modifie PAS le code dans cette étape — uniquement la réflexion." \
        5 "$LOG_DIR/feature-$FEATURE_COUNT-reflection-$attempt.log" "reflection" "$feature_name" || true

      # Construire le prompt de fix avec les réflexions passées
      fix_prompt=$(write_fix_prompt "$attempt" "$MAX_FIX_ATTEMPTS" \
        "$BUILD_EXIT" "${BUILD_OUTPUT: -3000}" \
        "$TEST_EXIT" "${TEST_OUTPUT: -3000}")

      # Injecter les réflexions passées
      if [ -f "$reflection_file" ]; then
        fix_prompt="$fix_prompt

RÉFLEXIONS DES TENTATIVES PRÉCÉDENTES (en tenir compte pour ne PAS refaire les mêmes erreurs) :
$(cat "$reflection_file")"
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
    notify "Feature '$feature_name' abandonnée après $attempt tentatives de fix."
    gh_comment "❌ **Feature #$FEATURE_COUNT** : $feature_name — abandonnée après $attempt tentatives"
    gh_create_abandoned_issue "$feature_name" "$attempt"
    # Retour sur main pour ne pas polluer la feature suivante
    run_in_project "git checkout main 2>/dev/null || true"
  fi

  # --- Reflect & Evolve ---
  log INFO "Rétrospective..."
  reflect_prompt=$(render_phase "05-reflect.md" \
    "FEATURE_NAME=$feature_name" \
    "TESTS_PASSED=$tests_passed" \
    "FIX_ATTEMPTS=$attempt" \
    "N=$FEATURE_COUNT")
  run_claude "$reflect_prompt" 20 "$LOG_DIR/feature-$FEATURE_COUNT-reflect.log" "reflect" "$feature_name" || {
    log WARN "Rétrospective échouée — on continue."
  }

  # --- Quality Gate (post-tests, pré-merge) ---
  if [ "$tests_passed" = true ] && [ -n "${QUALITY_COMMAND:-}" ]; then
    log INFO "Quality gate en cours..."
    quality_output=$(run_in_project "$QUALITY_COMMAND 2>&1") && quality_exit=0 || quality_exit=$?

    if [ $quality_exit -ne 0 ]; then
      log WARN "Quality gate échouée — tentative de correction..."
      run_claude "La quality gate a échoué après les tests.

COMMANDE : $QUALITY_COMMAND
EXIT CODE : $quality_exit
OUTPUT :
${quality_output: -3000}

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
    notify "Feature #$FEATURE_COUNT '$feature_name' mergée (\$$TOTAL_COST_USD)"
    gh_comment "✅ **Feature #$FEATURE_COUNT** : $feature_name — mergée (fix: $attempt, coût: \$${TOTAL_COST_USD})"
    gh_sync_roadmap  # Fermer l'issue correspondante
  fi

  save_state

  # --- Reset compteur epic ---
  if [ "$EPIC_FEATURE_COUNT" -ge "$EPIC_SIZE" ]; then
    gh_sync_milestone "Epic $(( (FEATURE_COUNT - 1) / EPIC_SIZE + 1 ))"
    EPIC_FEATURE_COUNT=0
  fi

  # --- Méta-rétrospective toutes les N features ---
  if [ $((FEATURE_COUNT % META_RETRO_FREQUENCY)) -eq 0 ]; then
    log PHASE "MÉTA-RÉTROSPECTIVE — $FEATURE_COUNT features"
    retro_prompt=$(render_phase "06-meta-retro.md" "FEATURE_COUNT=$FEATURE_COUNT")
    run_claude "$retro_prompt" "$MAX_TURNS_RESEARCH_TREND" "$LOG_DIR/meta-retro-$FEATURE_COUNT.log" "meta-retro" || {
      log WARN "Méta-rétrospective échouée — on continue."
    }
    log INFO "Méta-rétrospective terminée."
    gh_create_release "v0.$FEATURE_COUNT.0" "Meta-retro après $FEATURE_COUNT features"
    gh_sync_roadmap
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
  EVOLVE_CYCLES=$((EVOLVE_CYCLES + 1))
  max_evolve="${MAX_EVOLVE_CYCLES:-0}"

  if [ "$max_evolve" -gt 0 ] && [ "$EVOLVE_CYCLES" -gt "$max_evolve" ]; then
    log WARN "Limite de cycles evolve atteinte ($EVOLVE_CYCLES/$max_evolve) — arrêt."
    notify "Limite de cycles evolve atteinte ($max_evolve). Projet terminé automatiquement."
  else
    log PHASE "PHASE FINALE — ÉVOLUTION (cycle $EVOLVE_CYCLES)"
    evolve_prompt=$(render_phase "07-evolve.md")
    run_claude "$evolve_prompt" 30 "$LOG_DIR/07-evolve.log" "evolve"

    if [ ! -f "$PROJECT_DIR/DONE.md" ] && grep -q '^\- \[ \]' "$PROJECT_DIR/.orc/ROADMAP.md" 2>/dev/null; then
      # Compter les features ajoutées par l'IA
      new_features=$(grep -c '^\- \[ \]' "$PROJECT_DIR/.orc/ROADMAP.md" 2>/dev/null || echo "0")
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

      log INFO "Nouvelles features ajoutées — relancement de la boucle."
      save_state
      exec "$0"
    fi
  fi
fi

# ============================================================
# PHASE POST-PROJET — AUTO-AMÉLIORATION DE L'ORCHESTRATEUR
# ============================================================

notify "Projet terminé ! Features: $FEATURE_COUNT, Échecs: $TOTAL_FAILURES, Coût: \$$TOTAL_COST_USD"
log PHASE "AUTO-AMÉLIORATION DE L'ORCHESTRATEUR"

run_claude "$(cat <<'IMPROVE'
PHASE AUTO-AMÉLIORATION DE L'ORCHESTRATEUR

Le projet est terminé. Analyse l'ensemble des logs pour améliorer
l'orchestrateur lui-même (pas le projet, l'OUTIL qui pilote les projets).

Lis :
1. Tous les fichiers .orc/logs/retrospective-*.md
2. Tous les fichiers .orc/logs/meta-retrospective-*.md
3. Tous les fichiers .orc/logs/fix-reflections-*.md
4. Tous les fichiers .orc/logs/human-feedback-*.md
5. Le CLAUDE.md final (les règles que tu t'es auto-ajoutées)
6. Les skills dans .claude/skills/ (celles que tu as créées)

Analyse :
- Quels prompts de phase ont produit les meilleurs résultats ?
- Quels prompts ont dû être "contournés" ou étaient insuffisants ?
- Quels types d'erreurs l'orchestrateur n'a pas su gérer ?
- Quelles étapes manquent dans le workflow ?
- Les garde-fous étaient-ils bien calibrés ?
- Le système de connaissance (codebase/, auto-map, stack-conventions) a-t-il fonctionné ?
- La détection de boucle et les réflexions ont-elles aidé ?
- Le contexte adaptatif par phase était-il pertinent ?

Produis un fichier `orchestrator-improvements.md` dans le dossier courant
avec cette structure :

## Améliorations proposées pour l'orchestrateur

### Phases à modifier
Pour chaque phase concernée :
- **Phase XX** : [problème constaté] → [amélioration proposée]

### Nouvelles phases à ajouter
- [description de la phase] — [pourquoi elle manquait]

### Config à ajuster
- [paramètre] : [valeur actuelle] → [valeur recommandée] — [pourquoi]

### Nouvelles skills utiles
- [nom du skill] — [ce qu'il fait] — [pourquoi il serait utile]

### Système de connaissance (codebase/, auto-map, stack-conventions)
- [ce qui a bien marché] — [ce qu'il faudrait améliorer]
- L'index était-il utile ? L'auto-map était-il à jour ? Les conventions respectées ?

### Garde-fous
- [garde-fou à ajouter/modifier] — [incident qui l'a motivé]

### Conventions bash découvertes
- Si tu as découvert des patterns bash utiles, note-les pour stack-conventions.md de l'orchestrateur

Sois concret et actionnable.
IMPROVE
)" 30 "$LOG_DIR/orchestrator-improvements.log" "self-improve"

log INFO "Suggestions d'amélioration : project/orchestrator-improvements.md"

# Extraire les learnings et les copier dans le template pour les futurs projets
if [ -f "$PROJECT_DIR/orchestrator-improvements.md" ]; then
  learning_file="$SCRIPT_DIR/learnings/$(date +%Y-%m-%d)-${PROJECT_NAME:-project}.md"
  {
    echo "# Learnings — ${PROJECT_NAME:-project}"
    echo "Date : $(date '+%Y-%m-%d')"
    echo "Features : $FEATURE_COUNT | Échecs : $TOTAL_FAILURES | Coût : \$$TOTAL_COST_USD"
    echo ""
    cat "$PROJECT_DIR/orchestrator-improvements.md"
  } > "$learning_file"
  log INFO "Learnings sauvés dans le template : $learning_file"

  # Extraire les conventions bash découvertes et les ajouter à ORC stack-conventions
  orc_conventions="$SCRIPT_DIR/.claude/skills/stack-conventions.md"
  if [ -f "$orc_conventions" ]; then
    # Demander à Claude d'enrichir les stack-conventions de ORC
    run_claude "Lis le fichier orchestrator-improvements.md que tu viens de produire.
S'il contient des conventions bash, des anti-patterns, ou des patterns utiles
qui s'appliquent à l'orchestrateur lui-même (pas au projet), alors :

1. Lis le fichier .claude/skills/stack-conventions.md (les conventions actuelles de ORC)
2. Ajoute les nouvelles conventions découvertes dans les sections appropriées
3. Ne duplique pas ce qui existe déjà
4. Garde le fichier concis

S'il n'y a rien de nouveau à ajouter, ne modifie rien." \
      10 "$LOG_DIR/orc-conventions-update.log" "self-improve" || {
      log WARN "Mise à jour des conventions ORC échouée — pas grave."
    }
  fi

  # Mettre à jour codebase/INDEX.md de ORC si des changements structurels ont été faits
  orc_index="$SCRIPT_DIR/codebase/INDEX.md"
  if [ -f "$orc_index" ]; then
    run_claude "Lis le fichier orchestrator-improvements.md et vérifie si les améliorations
proposées impactent la structure de l'orchestrateur (nouvelles fonctions, nouveaux fichiers,
changements de config, nouveaux paramètres).

Si oui :
1. Lis codebase/INDEX.md (l'index sémantique de ORC)
2. Lis le fichier de détail pertinent dans codebase/
3. Mets-les à jour pour refléter les changements
4. Garde l'index compact (max 40 lignes)

Si les améliorations sont mineures ou ne changent pas la structure, ne modifie rien." \
      10 "$LOG_DIR/orc-index-update.log" "self-improve" || {
      log WARN "Mise à jour de l'index ORC échouée — pas grave."
    }
  fi
fi

# ============================================================
# BILAN FINAL
# ============================================================

gh_sync_roadmap
gh_create_release "v1.0.0" "Projet terminé — $FEATURE_COUNT features"
gh_close_tracking_issue

log PHASE "TERMINÉ"
log INFO "Features complétées : $FEATURE_COUNT"
log INFO "Features en échec : $TOTAL_FAILURES"

if [ -f "$PROJECT_DIR/DONE.md" ]; then
  log INFO "Le projet est déclaré terminé. Voir project/DONE.md"
else
  log WARN "L'orchestrateur s'est arrêté (limite MAX_FEATURES=$MAX_FEATURES atteinte)."
fi

print_cost_summary

echo ""
printf "${GREEN}═══════════════════════════════════════════════════${NC}\n"
printf "${GREEN}  Agent terminé.${NC}\n"
printf "${GREEN}  Features : %s | Échecs : %s${NC}\n" "$FEATURE_COUNT" "$TOTAL_FAILURES"
printf "${GREEN}  Coût total : \$%s USD${NC}\n" "$TOTAL_COST_USD"
printf "${GREEN}  Logs : %s/${NC}\n" "$LOG_DIR"
printf "${GREEN}  Tokens : %s${NC}\n" "$TOKENS_FILE"
printf "${GREEN}  Projet : %s/${NC}\n" "$PROJECT_DIR"
if [ -f "$PROJECT_DIR/orchestrator-improvements.md" ]; then
  printf "${GREEN}  Améliorations : %s/orchestrator-improvements.md${NC}\n" "$PROJECT_DIR"
fi
printf "${GREEN}═══════════════════════════════════════════════════${NC}\n"
