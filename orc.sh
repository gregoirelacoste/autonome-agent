#!/bin/bash
set -euo pipefail

# ============================================================
# orc — CLI unifiée Autonome Agent
# ============================================================
#
# Point d'entrée unique pour tout contrôler :
#
#   orc agent <cmd>     Gestion des projets (new, start, stop, status, logs)
#   orc roadmap [opts]  Suivi de la roadmap (compact, detail, full + filtres)
#   orc admin <cmd>     Administration (config, model, budget, keys, version)
#   orc help            Aide contextuelle
#
# ============================================================

ORC_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
ORC_VERSION="0.6.0"

# Charger les clés API
ENV_FILE="$ORC_DIR/.env"
if [ -f "$ENV_FILE" ]; then
  # shellcheck source=/dev/null
  source "$ENV_FILE"
fi

# === COULEURS ===
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

die() { printf "${RED}Erreur : %s${NC}\n" "$1" >&2; exit 1; }

# === MARKDOWN RENDERER ===
render_markdown() {
  local file="$1"
  if command -v glow &>/dev/null; then
    glow -p "$file"
  elif command -v batcat &>/dev/null; then
    batcat --style=plain --paging=always --language=md "$file"
  elif command -v bat &>/dev/null; then
    bat --style=plain --paging=always --language=md "$file"
  elif command -v less &>/dev/null; then
    less "$file"
  else
    cat "$file"
  fi
}

# ============================================================
# HELP
# ============================================================

orc_help() {
  echo ""
  printf "${BOLD}orc${NC} — Autonome Agent CLI v%s\n" "$ORC_VERSION"
  echo ""
  printf "  ${BOLD}Projets :${NC}\n"
  printf "    ${CYAN}orc agent new <nom>${NC}               Créer (wizard interactif)\n"
  printf "    ${CYAN}orc agent new <nom> --brief x.md${NC}  Créer depuis un brief (+ clarification IA)\n"
  printf "    ${CYAN}orc agent new <nom> --github${NC}      Créer + repo GitHub (private par défaut)\n"
  printf "    ${CYAN}orc agent github <nom>${NC}            Créer le repo GitHub d'un projet existant\n"
  printf "    ${CYAN}orc agent env <nom>${NC}              Configurer les variables d'environnement\n"
  printf "    ${CYAN}orc chat <nom>${NC}                   Chat Claude avec contexte projet (brief, roadmap, état)\n"
  printf "    ${CYAN}orc agent start <nom>${NC}             Lancer en background\n"
  printf "    ${CYAN}orc agent stop <nom>${NC}              Arrêter proprement\n"
  printf "    ${CYAN}orc agent status${NC}                  Vue d'ensemble (avec progression)\n"
  printf "    ${CYAN}orc agent status <nom>${NC}            Détail + barre de progression + ETA\n"
  printf "    ${CYAN}orc dashboard <nom>${NC}               Dashboard live (auto-refresh)\n"
  printf "    ${CYAN}orc agent logs <nom>${NC}              Logs temps réel\n"
  echo ""
  printf "  ${BOLD}Roadmap :${NC}\n"
  printf "    ${CYAN}orc roadmap${NC}                       Roadmap orc (développement du template)\n"
  printf "    ${CYAN}orc roadmap <projet>${NC}              Roadmap d'un projet\n"
  printf "    ${CYAN}orc roadmap --detail${NC}              + contexte, dépendances\n"
  printf "    ${CYAN}orc roadmap --full${NC}                + specs, critères\n"
  printf "    ${CYAN}orc roadmap --priority P1${NC}         Filtrer par priorité\n"
  echo ""
  printf "  ${BOLD}Administration :${NC}\n"
  printf "    ${CYAN}orc admin config${NC}                  Voir la config globale\n"
  printf "    ${CYAN}orc admin config set KEY VAL${NC}      Modifier une config\n"
  printf "    ${CYAN}orc admin model${NC}                   Modèle Claude actuel\n"
  printf "    ${CYAN}orc admin model set <model>${NC}       Changer le modèle\n"
  printf "    ${CYAN}orc admin budget${NC}                  Coûts tous projets\n"
  printf "    ${CYAN}orc admin key${NC}                     Voir les clés API\n"
  printf "    ${CYAN}orc admin key set <key>${NC}           Configurer clé Anthropic\n"
  printf "    ${CYAN}orc admin version${NC}                 Version + vérifications\n"
  printf "    ${CYAN}orc admin update${NC}                  Mettre à jour le template\n"
  echo ""
  printf "  ${BOLD}Documentation :${NC}\n"
  printf "    ${CYAN}orc docs${NC}                          Index de la documentation\n"
  printf "    ${CYAN}orc docs <sujet>${NC}                  Ouvrir une page (getting-started, commands, etc.)\n"
  echo ""
  printf "  ${DIM}Raccourcis : 'orc s' = status, 'orc l <nom>' = logs, 'orc r' = roadmap, 'orc dash <nom>' = dashboard${NC}\n"
  echo ""
}

# ============================================================
# DOCS
# ============================================================

cmd_docs() {
  local docs_dir="$ORC_DIR/docs"
  local subject="${1:-}"

  if [ -z "$subject" ]; then
    # Afficher l'index
    if [ -f "$docs_dir/INDEX.md" ]; then
      echo ""
      printf "${BOLD}Documentation orc v%s${NC}\n\n" "$ORC_VERSION"
      printf "  ${CYAN}getting-started${NC}     Installation et premier projet\n"
      printf "  ${CYAN}init-modes${NC}          Modes d'init (wizard, --brief, etc.)\n"
      printf "  ${CYAN}commands${NC}            Référence CLI complète\n"
      printf "  ${CYAN}configuration${NC}       Paramètres et modes d'autonomie\n"
      printf "  ${CYAN}github${NC}              Intégration GitHub\n"
      printf "  ${CYAN}human-controls${NC}      Pause, stop, notes, feedback\n"
      printf "  ${CYAN}faq${NC}                 FAQ et troubleshooting\n"
      echo ""
      printf "  Usage : ${CYAN}orc docs <sujet>${NC}\n"
      printf "  Fichiers : ${DIM}%s/${NC}\n" "$docs_dir"
      echo ""
    else
      die "Dossier docs/ non trouvé dans $ORC_DIR"
    fi
    return
  fi

  # Résoudre le sujet en fichier
  local file=""
  case "$subject" in
    getting-started|start|gs) file="getting-started.md" ;;
    init-modes|init|modes)    file="init-modes.md" ;;
    commands|cmd|ref)         file="commands-reference.md" ;;
    configuration|config|cfg) file="configuration.md" ;;
    github|gh)                file="github-integration.md" ;;
    human-controls|human|hc)  file="human-controls.md" ;;
    faq|help)                 file="faq.md" ;;
    index)                    file="INDEX.md" ;;
    *)
      # Essayer un match direct
      if [ -f "$docs_dir/${subject}.md" ]; then
        file="${subject}.md"
      else
        die "Doc inconnue : $subject. Voir : orc docs"
      fi
      ;;
  esac

  if [ -f "$docs_dir/$file" ]; then
    render_markdown "$docs_dir/$file"
  else
    die "Fichier non trouvé : $docs_dir/$file"
  fi
}

# ============================================================
# DISPATCH
# ============================================================

COMMAND="${1:-help}"
shift || true

case "$COMMAND" in
  agent|a)
    source "$ORC_DIR/orc-agent.sh"
    agent_dispatch "$@"
    ;;
  roadmap|r)
    source "$ORC_DIR/orc-agent.sh"
    # Si le premier arg est un nom de projet existant, afficher sa roadmap
    if [ -n "${1:-}" ] && [ -d "$(project_dir "$1")" ]; then
      cmd_project_roadmap "$@"
    else
      cmd_roadmap "$@"
    fi
    ;;
  admin)
    source "$ORC_DIR/orc-admin.sh"
    admin_dispatch "$@"
    ;;
  docs|d)
    cmd_docs "$@"
    ;;
  # Raccourcis directs pour les commandes les plus fréquentes
  status|s)
    source "$ORC_DIR/orc-agent.sh"
    cmd_status "$@"
    ;;
  dashboard|dash|db)
    source "$ORC_DIR/orc-agent.sh"
    cmd_dashboard "$@"
    ;;
  logs|l)
    source "$ORC_DIR/orc-agent.sh"
    cmd_logs "$@"
    ;;
  chat|c)
    source "$ORC_DIR/orc-agent.sh"
    cmd_chat "$@"
    ;;
  help|-h|--help)
    orc_help
    ;;
  version|-v|--version)
    printf "orc v%s\n" "$ORC_VERSION"
    ;;
  *)
    # Tenter comme sous-commande agent par défaut
    source "$ORC_DIR/orc-agent.sh"
    agent_dispatch "$COMMAND" "$@" 2>/dev/null || {
      die "Commande inconnue : $COMMAND. Voir : orc help"
    }
    ;;
esac
