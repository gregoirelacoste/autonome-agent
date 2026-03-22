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
source "$SCRIPT_DIR/config.sh"

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
STATE_FILE="$SCRIPT_DIR/logs/state.json"

# === TRACKING TOKENS ===
TOKENS_FILE="$LOG_DIR/tokens.json"
TOTAL_INPUT_TOKENS=0
TOTAL_OUTPUT_TOKENS=0
TOTAL_COST_USD=0

# Coût par token (Claude Opus 4, en USD) — ajuster selon le modèle
COST_PER_INPUT_TOKEN=0.000015
COST_PER_OUTPUT_TOKEN=0.000075

# === LOCKFILE ===
LOCKFILE="$SCRIPT_DIR/.orchestrator.lock"

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
{"feature_count":$FEATURE_COUNT,"epic_feature_count":$EPIC_FEATURE_COUNT,"total_failures":$TOTAL_FAILURES}
STATEEOF
}

# Restaure l'état si disponible
restore_state() {
  if command -v jq &> /dev/null && [ -f "$STATE_FILE" ]; then
    FEATURE_COUNT=$(jq -r '.feature_count // 0' "$STATE_FILE")
    EPIC_FEATURE_COUNT=$(jq -r '.epic_feature_count // 0' "$STATE_FILE")
    TOTAL_FAILURES=$(jq -r '.total_failures // 0' "$STATE_FILE")
    log INFO "État restauré : features=$FEATURE_COUNT, échecs=$TOTAL_FAILURES"
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

  # Lancer Claude en background avec output JSON
  claude -p "$prompt" \
    --dangerously-skip-permissions \
    --max-turns "$max_turns" \
    --output-format json \
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

  local json_output
  json_output=$(cat "$TMP_JSON")

  local text_output
  if command -v jq &> /dev/null; then
    text_output=$(echo "$json_output" | jq -r '.result // .message // .' 2>/dev/null || echo "$json_output")
  else
    text_output="$json_output"
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
  grep -m1 '^\- \[ \]' "$PROJECT_DIR/ROADMAP.md" 2>/dev/null | sed 's/^- \[ \] //' || true
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

# Pause pour intervention humaine
human_pause() {
  # Si stdin n'est pas un terminal (mode nohup), skip la pause
  if [ ! -t 0 ]; then
    log WARN "Pause ignorée (pas de terminal interactif) : $1"
    return 0
  fi

  local reason="$1"
  log PHASE "PAUSE HUMAINE — $reason"
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
  printf "    ${GREEN}q${NC} — quitter\n"
  echo ""

  while true; do
    read -rp "→ " choice
    case "$choice" in
      c|C) return 0 ;;
      r|R) cat "$PROJECT_DIR/ROADMAP.md" 2>/dev/null || echo "Pas de ROADMAP." ; echo "" ;;
      l|L) tail -30 "$LOG_DIR/orchestrator.log" 2>/dev/null ; echo "" ;;
      t|T) print_cost_summary ;;
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

log PHASE "DÉMARRAGE DE L'AGENT AUTONOME"
log INFO "Config : MAX_FEATURES=$MAX_FEATURES | MAX_FIX=$MAX_FIX_ATTEMPTS | EPIC_SIZE=$EPIC_SIZE"
log INFO "Recherche : $ENABLE_RESEARCH | Approbation humaine : $REQUIRE_HUMAN_APPROVAL"
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

  if [ ! -f "$PROJECT_DIR/BRIEF.md" ]; then
    cp "$SCRIPT_DIR/BRIEF.md" "$PROJECT_DIR/BRIEF.md"
  fi

  mkdir -p "$PROJECT_DIR/research/competitors" \
           "$PROJECT_DIR/research/trends" \
           "$PROJECT_DIR/research/user-needs" \
           "$PROJECT_DIR/research/regulations" \
           "$PROJECT_DIR/logs"

  mkdir -p "$PROJECT_DIR/.claude/skills"
  if compgen -G "$SCRIPT_DIR/skills-templates/*.md" > /dev/null 2>&1; then
    for skill in "$SCRIPT_DIR/skills-templates/"*.md; do
      dest="$PROJECT_DIR/.claude/skills/$(basename "$skill")"
      [ ! -f "$dest" ] && cp "$skill" "$dest"
    done
  fi

  local_prompt=$(render_phase "00-bootstrap.md")
  run_claude "$local_prompt" 60 "$LOG_DIR/00-bootstrap.log" "bootstrap"

  log INFO "Bootstrap terminé."
else
  log INFO "Projet existant détecté (CLAUDE.md présent), reprise en cours..."
fi

# ============================================================
# PHASE 1 — RECHERCHE INITIALE
# ============================================================

if [ "$ENABLE_RESEARCH" = true ] && [ ! -f "$PROJECT_DIR/research/INDEX.md" ]; then
  log PHASE "PHASE 1 — RECHERCHE INITIALE"

  local_prompt=$(render_phase "01-research.md")
  run_claude "$local_prompt" "$MAX_TURNS_RESEARCH_INITIAL" "$LOG_DIR/01-research.log" "research-initial"

  log INFO "Recherche initiale terminée."
fi

# ============================================================
# PHASE 2 — STRATÉGIE
# ============================================================

if ! grep -q '^\- \[ \]' "$PROJECT_DIR/ROADMAP.md" 2>/dev/null; then
  log PHASE "PHASE 2 — STRATÉGIE"

  local_prompt=$(render_phase "02-strategy.md")
  run_claude "$local_prompt" 30 "$LOG_DIR/02-strategy.log" "strategy"

  log INFO "Roadmap générée."
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
4. Mets à jour research/ et ajuste les specs dans ROADMAP.md si nécessaire
EOF
    )" "$MAX_TURNS_RESEARCH_EPIC" "$LOG_DIR/research-epic-$FEATURE_COUNT.log" "research-epic" "$feature_name"
  fi

  # --- Implémentation ---
  log INFO "Implémentation en cours..."
  impl_prompt=$(render_phase "03-implement.md" \
    "FEATURE_NAME=$feature_name" \
    "FEATURE_BRANCH=$feature_branch")
  run_claude "$impl_prompt" "$MAX_TURNS_PER_INVOCATION" "$LOG_DIR/feature-$FEATURE_COUNT-impl.log" "implement" "$feature_name"

  # --- Test & Fix Loop ---
  attempt=0
  tests_passed=false

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

    if [ $attempt -lt $MAX_FIX_ATTEMPTS ]; then
      log WARN "Échec — correction en cours (tentative $attempt)..."
      fix_prompt=$(write_fix_prompt "$attempt" "$MAX_FIX_ATTEMPTS" \
        "$BUILD_EXIT" "${BUILD_OUTPUT: -3000}" \
        "$TEST_EXIT" "${TEST_OUTPUT: -3000}")
      run_claude "$fix_prompt" 30 "$LOG_DIR/feature-$FEATURE_COUNT-fix-$attempt.log" "fix" "$feature_name"
    fi
  done

  if [ "$tests_passed" = false ]; then
    log ERROR "Feature '$feature_name' abandonnée après $MAX_FIX_ATTEMPTS tentatives."
    TOTAL_FAILURES=$((TOTAL_FAILURES + 1))
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
  run_claude "$reflect_prompt" 20 "$LOG_DIR/feature-$FEATURE_COUNT-reflect.log" "reflect" "$feature_name"

  # --- Merge si OK ---
  if [ "$tests_passed" = true ]; then
    if [ "$REQUIRE_HUMAN_APPROVAL" = true ]; then
      human_pause "Approuver le merge de : $feature_name"
    fi

    current_branch=$(run_in_project "git branch --show-current 2>/dev/null || echo ''")
    if [ -n "$current_branch" ] && [ "$current_branch" != "main" ]; then
      run_in_project "git checkout main 2>/dev/null && git merge --no-ff '$current_branch' -m 'feat: $feature_name' 2>/dev/null || true"
    fi

    log INFO "Feature '$feature_name' mergée."
  fi

  save_state

  # --- Reset compteur epic ---
  if [ "$EPIC_FEATURE_COUNT" -ge "$EPIC_SIZE" ]; then
    EPIC_FEATURE_COUNT=0
  fi

  # --- Méta-rétrospective toutes les N features ---
  if [ $((FEATURE_COUNT % META_RETRO_FREQUENCY)) -eq 0 ]; then
    log PHASE "MÉTA-RÉTROSPECTIVE — $FEATURE_COUNT features"
    retro_prompt=$(render_phase "06-meta-retro.md" "FEATURE_COUNT=$FEATURE_COUNT")
    run_claude "$retro_prompt" "$MAX_TURNS_RESEARCH_TREND" "$LOG_DIR/meta-retro-$FEATURE_COUNT.log" "meta-retro"
    log INFO "Méta-rétrospective terminée."
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
  log PHASE "PHASE FINALE — ÉVOLUTION"
  evolve_prompt=$(render_phase "07-evolve.md")
  run_claude "$evolve_prompt" 30 "$LOG_DIR/07-evolve.log" "evolve"

  if [ ! -f "$PROJECT_DIR/DONE.md" ] && grep -q '^\- \[ \]' "$PROJECT_DIR/ROADMAP.md" 2>/dev/null; then
    log INFO "Nouvelles features ajoutées — relancement de la boucle."
    save_state
    exec "$0"
  fi
fi

# ============================================================
# PHASE POST-PROJET — AUTO-AMÉLIORATION DE L'ORCHESTRATEUR
# ============================================================

log PHASE "AUTO-AMÉLIORATION DE L'ORCHESTRATEUR"

run_claude "$(cat <<'IMPROVE'
PHASE AUTO-AMÉLIORATION DE L'ORCHESTRATEUR

Le projet est terminé. Analyse l'ensemble des logs pour améliorer
l'orchestrateur lui-même (pas le projet, l'OUTIL qui pilote les projets).

Lis :
1. Tous les fichiers logs/retrospective-*.md
2. Tous les fichiers logs/meta-retrospective-*.md
3. Le CLAUDE.md final (les règles que tu t'es auto-ajoutées)
4. Les skills dans .claude/skills/ (celles que tu as créées)

Analyse :
- Quels prompts de phase ont produit les meilleurs résultats ?
- Quels prompts ont dû être "contournés" ou étaient insuffisants ?
- Quels types d'erreurs l'orchestrateur n'a pas su gérer ?
- Quelles étapes manquent dans le workflow ?
- Les garde-fous étaient-ils bien calibrés ?

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

### Garde-fous
- [garde-fou à ajouter/modifier] — [incident qui l'a motivé]

Sois concret et actionnable.
IMPROVE
)" 30 "$LOG_DIR/orchestrator-improvements.log" "self-improve"

log INFO "Suggestions d'amélioration : project/orchestrator-improvements.md"

# ============================================================
# BILAN FINAL
# ============================================================

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
