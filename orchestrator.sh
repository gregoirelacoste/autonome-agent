#!/bin/bash
set -euo pipefail

# ============================================================
# Agent Autonome Claude — Orchestrateur principal
# ============================================================
#
# Usage :
#   1. cp BRIEF.template.md BRIEF.md && vim BRIEF.md
#   2. vim config.sh  (ajuster les paramètres)
#   3. ./orchestrator.sh
#
# L'orchestrateur crée un dossier project/ avec son propre git,
# puis pilote Claude en boucle autonome.
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

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

# === FONCTIONS UTILITAIRES ===

log() {
  local level="$1" msg="$2"
  local timestamp
  timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  case "$level" in
    INFO)  echo -e "${CYAN}[$timestamp]${NC} ${GREEN}[INFO]${NC}  $msg" ;;
    WARN)  echo -e "${CYAN}[$timestamp]${NC} ${YELLOW}[WARN]${NC}  $msg" ;;
    ERROR) echo -e "${CYAN}[$timestamp]${NC} ${RED}[ERROR]${NC} $msg" ;;
    PHASE) echo -e "\n${CYAN}[$timestamp]${NC} ${BLUE}[═══════════════]${NC} $msg" ;;
  esac
  echo "[$timestamp] [$level] $msg" >> "$LOG_DIR/orchestrator.log"
}

run_claude() {
  local prompt="$1"
  local max_turns="${2:-$MAX_TURNS_PER_INVOCATION}"
  local log_file="${3:-/dev/null}"

  if [ "$VERBOSE" = true ]; then
    claude -p "$prompt" --yes --max-turns "$max_turns" -d "$PROJECT_DIR" 2>&1 | tee -a "$log_file"
  else
    claude -p "$prompt" --yes --max-turns "$max_turns" -d "$PROJECT_DIR" 2>&1 >> "$log_file"
  fi
}

# Remplace les placeholders {{VAR}} dans un fichier phase
render_phase() {
  local phase_file="$1"
  shift
  local content
  content=$(cat "$SCRIPT_DIR/phases/$phase_file")

  # Remplace chaque paire clé=valeur passée en argument
  while [ $# -gt 0 ]; do
    local key="${1%%=*}"
    local value="${1#*=}"
    content="${content//\{\{$key\}\}/$value}"
    shift
  done

  echo "$content"
}

# Lit la prochaine feature non cochée de la ROADMAP
next_feature() {
  grep -m1 '^\- \[ \]' "$PROJECT_DIR/ROADMAP.md" 2>/dev/null | sed 's/^- \[ \] //' || true
}

# Nom court pour les branches git
branch_name() {
  echo "$1" | sed 's/ |.*//;s/[^a-zA-Z0-9]/-/g' | tr '[:upper:]' '[:lower:]' | head -c 40
}

# Pause pour intervention humaine
human_pause() {
  local reason="$1"
  log PHASE "PAUSE HUMAINE — $reason"
  echo ""
  echo -e "${YELLOW}═══════════════════════════════════════════════════${NC}"
  echo -e "${YELLOW}  PAUSE — Intervention humaine requise${NC}"
  echo -e "${YELLOW}  Raison : $reason${NC}"
  echo -e "${YELLOW}  Features complétées : $FEATURE_COUNT${NC}"
  echo -e "${YELLOW}═══════════════════════════════════════════════════${NC}"
  echo ""
  echo -e "  Commandes :"
  echo -e "    ${GREEN}c${NC} — continuer"
  echo -e "    ${GREEN}r${NC} — voir la roadmap"
  echo -e "    ${GREEN}l${NC} — voir les logs récents"
  echo -e "    ${GREEN}q${NC} — quitter"
  echo ""

  while true; do
    read -rp "→ " choice
    case "$choice" in
      c|C) return 0 ;;
      r|R) cat "$PROJECT_DIR/ROADMAP.md" 2>/dev/null || echo "Pas de ROADMAP encore." ; echo "" ;;
      l|L) tail -30 "$LOG_DIR/orchestrator.log" 2>/dev/null ; echo "" ;;
      q|Q) log INFO "Arrêt demandé par l'utilisateur." ; exit 0 ;;
      *) echo "Choix invalide. Tapez c, r, l ou q." ;;
    esac
  done
}

# ============================================================
# VÉRIFICATIONS PRÉALABLES
# ============================================================

if ! command -v claude &> /dev/null; then
  echo -e "${RED}Erreur : 'claude' CLI non trouvé. Installez Claude Code.${NC}"
  exit 1
fi

if [ ! -f "$SCRIPT_DIR/BRIEF.md" ]; then
  echo -e "${RED}Erreur : BRIEF.md non trouvé.${NC}"
  echo "Copiez BRIEF.template.md vers BRIEF.md et remplissez-le."
  exit 1
fi

mkdir -p "$LOG_DIR"

log PHASE "DÉMARRAGE DE L'AGENT AUTONOME"
log INFO "Config : MAX_FEATURES=$MAX_FEATURES | MAX_FIX=$MAX_FIX_ATTEMPTS | EPIC_SIZE=$EPIC_SIZE"
log INFO "Recherche : $ENABLE_RESEARCH | Approbation humaine : $REQUIRE_HUMAN_APPROVAL"

# ============================================================
# PHASE 0 — BOOTSTRAP
# ============================================================

if [ ! -d "$PROJECT_DIR/.git" ]; then
  log PHASE "PHASE 0 — BOOTSTRAP"

  mkdir -p "$PROJECT_DIR"
  cp "$SCRIPT_DIR/BRIEF.md" "$PROJECT_DIR/BRIEF.md"
  cd "$PROJECT_DIR" && git init && cd - > /dev/null

  # Créer la structure research/
  mkdir -p "$PROJECT_DIR/research/competitors" \
           "$PROJECT_DIR/research/trends" \
           "$PROJECT_DIR/research/user-needs" \
           "$PROJECT_DIR/research/regulations" \
           "$PROJECT_DIR/logs"

  # Copier les skills templates
  mkdir -p "$PROJECT_DIR/.claude/skills"
  cp "$SCRIPT_DIR/skills-templates/"*.md "$PROJECT_DIR/.claude/skills/"

  # Lancer le bootstrap Claude
  local_prompt=$(render_phase "00-bootstrap.md")
  run_claude "$local_prompt" 60 "$LOG_DIR/00-bootstrap.log"

  log INFO "Bootstrap terminé."
else
  log INFO "Projet existant détecté, reprise en cours..."
fi

# ============================================================
# PHASE 1 — RECHERCHE INITIALE
# ============================================================

if [ "$ENABLE_RESEARCH" = true ] && [ ! -f "$PROJECT_DIR/research/INDEX.md" ]; then
  log PHASE "PHASE 1 — RECHERCHE INITIALE"

  local_prompt=$(render_phase "01-research.md")
  run_claude "$local_prompt" "$MAX_TURNS_RESEARCH_INITIAL" "$LOG_DIR/01-research.log"

  log INFO "Recherche initiale terminée."
fi

# ============================================================
# PHASE 2 — STRATÉGIE
# ============================================================

# Vérifie s'il y a déjà des features dans la ROADMAP
if ! grep -q '^\- \[ \]' "$PROJECT_DIR/ROADMAP.md" 2>/dev/null; then
  log PHASE "PHASE 2 — STRATÉGIE"

  local_prompt=$(render_phase "02-strategy.md")
  run_claude "$local_prompt" 30 "$LOG_DIR/02-strategy.log"

  log INFO "Roadmap générée."
fi

# ============================================================
# PHASE 3 — BOUCLE PRINCIPALE
# ============================================================

log PHASE "PHASE 3 — BOUCLE DE DÉVELOPPEMENT"

while [ $FEATURE_COUNT -lt $MAX_FEATURES ]; do

  # --- Lire la prochaine feature ---
  feature_raw=$(next_feature)

  if [ -z "$feature_raw" ]; then
    log INFO "Roadmap vide — passage en phase d'évolution."
    break
  fi

  feature_name=$(echo "$feature_raw" | sed 's/ |.*//')
  feature_branch=$(branch_name "$feature_name")

  FEATURE_COUNT=$((FEATURE_COUNT + 1))
  EPIC_FEATURE_COUNT=$((EPIC_FEATURE_COUNT + 1))

  log PHASE "FEATURE #$FEATURE_COUNT : $feature_name"

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
    )" "$MAX_TURNS_RESEARCH_EPIC" "$LOG_DIR/research-epic-$FEATURE_COUNT.log"
  fi

  # --- Implémentation ---
  log INFO "Implémentation en cours..."
  impl_prompt=$(render_phase "03-implement.md" \
    "FEATURE_NAME=$feature_name" \
    "FEATURE_BRANCH=$feature_branch")
  run_claude "$impl_prompt" "$MAX_TURNS_PER_INVOCATION" "$LOG_DIR/feature-$FEATURE_COUNT-impl.log"

  # --- Test & Fix Loop ---
  attempt=0
  tests_passed=false

  while [ $attempt -lt $MAX_FIX_ATTEMPTS ]; do
    log INFO "Tests — tentative $((attempt + 1))/$MAX_FIX_ATTEMPTS"

    cd "$PROJECT_DIR"
    BUILD_OUTPUT=$($BUILD_COMMAND 2>&1) && BUILD_EXIT=0 || BUILD_EXIT=$?
    TEST_OUTPUT=$($TEST_COMMAND 2>&1) && TEST_EXIT=0 || TEST_EXIT=$?
    cd - > /dev/null

    if [ $BUILD_EXIT -eq 0 ] && [ $TEST_EXIT -eq 0 ]; then
      tests_passed=true
      log INFO "Build + tests OK !"
      break
    fi

    attempt=$((attempt + 1))

    if [ $attempt -lt $MAX_FIX_ATTEMPTS ]; then
      log WARN "Échec — correction en cours (tentative $attempt)..."
      fix_prompt=$(render_phase "04-test-fix.md" \
        "ATTEMPT=$attempt" \
        "MAX_FIX=$MAX_FIX_ATTEMPTS" \
        "BUILD_EXIT=$BUILD_EXIT" \
        "BUILD_OUTPUT=${BUILD_OUTPUT: -3000}" \
        "TEST_EXIT=$TEST_EXIT" \
        "TEST_OUTPUT=${TEST_OUTPUT: -3000}")
      run_claude "$fix_prompt" 30 "$LOG_DIR/feature-$FEATURE_COUNT-fix-$attempt.log"
    fi
  done

  if [ "$tests_passed" = false ]; then
    log ERROR "Feature '$feature_name' abandonnée après $MAX_FIX_ATTEMPTS tentatives."
    TOTAL_FAILURES=$((TOTAL_FAILURES + 1))
  fi

  # --- Reflect & Evolve ---
  log INFO "Rétrospective..."
  reflect_prompt=$(render_phase "05-reflect.md" \
    "FEATURE_NAME=$feature_name" \
    "TESTS_PASSED=$tests_passed" \
    "FIX_ATTEMPTS=$attempt" \
    "N=$FEATURE_COUNT")
  run_claude "$reflect_prompt" 20 "$LOG_DIR/feature-$FEATURE_COUNT-reflect.log"

  # --- Merge si OK ---
  if [ "$tests_passed" = true ]; then
    if [ "$REQUIRE_HUMAN_APPROVAL" = true ]; then
      human_pause "Approuver le merge de : $feature_name"
    fi

    cd "$PROJECT_DIR"
    current_branch=$(git branch --show-current 2>/dev/null || echo "")
    if [ -n "$current_branch" ] && [ "$current_branch" != "main" ]; then
      git checkout main 2>/dev/null && git merge --no-ff "$current_branch" -m "feat: $feature_name" 2>/dev/null || true
    fi
    cd - > /dev/null

    log INFO "Feature '$feature_name' mergée."
  fi

  # --- Reset compteur epic ---
  if [ "$EPIC_FEATURE_COUNT" -ge "$EPIC_SIZE" ]; then
    EPIC_FEATURE_COUNT=0
  fi

  # --- Méta-rétrospective toutes les N features ---
  if [ $((FEATURE_COUNT % META_RETRO_FREQUENCY)) -eq 0 ]; then
    log PHASE "MÉTA-RÉTROSPECTIVE — $FEATURE_COUNT features"
    retro_prompt=$(render_phase "06-meta-retro.md" "FEATURE_COUNT=$FEATURE_COUNT")
    run_claude "$retro_prompt" "$MAX_TURNS_RESEARCH_TREND" "$LOG_DIR/meta-retro-$FEATURE_COUNT.log"
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
  run_claude "$evolve_prompt" 30 "$LOG_DIR/07-evolve.log"

  # Si Claude a ajouté de nouvelles features et pas déclaré DONE, relancer
  if [ ! -f "$PROJECT_DIR/DONE.md" ] && grep -q '^\- \[ \]' "$PROJECT_DIR/ROADMAP.md" 2>/dev/null; then
    log INFO "Nouvelles features ajoutées — relancement de la boucle."
    exec "$0"  # Relance l'orchestrateur
  fi
fi

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

echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Agent terminé.${NC}"
echo -e "${GREEN}  Features : $FEATURE_COUNT | Échecs : $TOTAL_FAILURES${NC}"
echo -e "${GREEN}  Logs : $LOG_DIR/${NC}"
echo -e "${GREEN}  Projet : $PROJECT_DIR/${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════${NC}"
