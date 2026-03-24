#!/bin/bash
set -euo pipefail

# ============================================================
# Autonome Agent — Installation sur VPS
# ============================================================
#
# Usage :
#   ssh root@<vps-ip> 'bash -s' < deploy.sh
#   ou :
#   scp deploy.sh root@<vps-ip>: && ssh root@<vps-ip> ./deploy.sh
#
# Compatible Ubuntu 22+ / Debian 12+
# Idempotent — peut être relancé sans risque
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

INSTALL_DIR="/opt/orc"
PROJECTS_DIR="$HOME/projects"
REPO_URL="https://github.com/gregoirelacoste/orc.git"

# ============================================================
echo ""
printf "${CYAN}╔═══════════════════════════════════════════════════╗${NC}\n"
printf "${CYAN}║  ${BOLD}Autonome Agent — Installation VPS${NC}${CYAN}                ║${NC}\n"
printf "${CYAN}╚═══════════════════════════════════════════════════╝${NC}\n"
echo ""

# ============================================================
# DÉTECTION OS
# ============================================================

if [ -f /etc/os-release ]; then
  . /etc/os-release
  OS_NAME="$ID"
  OS_VERSION="$VERSION_ID"
else
  printf "${RED}OS non supporté. Ubuntu 22+ ou Debian 12+ requis.${NC}\n"
  exit 1
fi

printf "  OS détecté : ${CYAN}%s %s${NC}\n" "$OS_NAME" "$OS_VERSION"

case "$OS_NAME" in
  ubuntu|debian) ;;
  *)
    printf "${RED}OS non supporté : %s. Ubuntu ou Debian requis.${NC}\n" "$OS_NAME"
    exit 1
    ;;
esac

# ============================================================
# INSTALLATION DES DÉPENDANCES
# ============================================================

printf "\n${BOLD}1/5 — Dépendances système${NC}\n"

apt-get update -qq

# Git
if command -v git &> /dev/null; then
  printf "  ${GREEN}✓${NC} git (déjà installé)\n"
else
  apt-get install -y -qq git > /dev/null
  printf "  ${GREEN}✓${NC} git installé\n"
fi

# jq
if command -v jq &> /dev/null; then
  printf "  ${GREEN}✓${NC} jq (déjà installé)\n"
else
  apt-get install -y -qq jq > /dev/null
  printf "  ${GREEN}✓${NC} jq installé\n"
fi

# curl
if command -v curl &> /dev/null; then
  printf "  ${GREEN}✓${NC} curl (déjà installé)\n"
else
  apt-get install -y -qq curl > /dev/null
  printf "  ${GREEN}✓${NC} curl installé\n"
fi

# ============================================================
printf "\n${BOLD}2/5 — Node.js 22${NC}\n"

if command -v node &> /dev/null; then
  NODE_VERSION=$(node --version)
  NODE_MAJOR=$(echo "$NODE_VERSION" | sed 's/v//' | cut -d. -f1)
  if [ "$NODE_MAJOR" -ge 22 ]; then
    printf "  ${GREEN}✓${NC} Node.js %s (déjà installé)\n" "$NODE_VERSION"
  else
    printf "  ${YELLOW}⚠${NC} Node.js %s trop ancien, upgrade vers v22...\n" "$NODE_VERSION"
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash - > /dev/null 2>&1
    apt-get install -y -qq nodejs > /dev/null
    printf "  ${GREEN}✓${NC} Node.js %s installé\n" "$(node --version)"
  fi
else
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash - > /dev/null 2>&1
  apt-get install -y -qq nodejs > /dev/null
  printf "  ${GREEN}✓${NC} Node.js %s installé\n" "$(node --version)"
fi

# ============================================================
printf "\n${BOLD}3/5 — Claude Code CLI${NC}\n"

if command -v claude &> /dev/null; then
  printf "  ${GREEN}✓${NC} Claude Code CLI (déjà installé)\n"
else
  npm install -g @anthropic-ai/claude-code > /dev/null 2>&1
  printf "  ${GREEN}✓${NC} Claude Code CLI installé\n"
fi

# ============================================================
printf "\n${BOLD}4/5 — Autonome Agent${NC}\n"

if [ -d "$INSTALL_DIR/.git" ]; then
  printf "  Mise à jour du repo existant...\n"
  git -C "$INSTALL_DIR" pull --ff-only > /dev/null 2>&1 || true
  printf "  ${GREEN}✓${NC} Repo mis à jour\n"
else
  if [ -d "$INSTALL_DIR" ]; then
    rm -rf "$INSTALL_DIR"
  fi
  git clone "$REPO_URL" "$INSTALL_DIR" > /dev/null 2>&1
  printf "  ${GREEN}✓${NC} Repo cloné dans %s\n" "$INSTALL_DIR"
fi

chmod +x "$INSTALL_DIR"/*.sh

# Dossier projets
mkdir -p "$PROJECTS_DIR"
printf "  ${GREEN}✓${NC} Dossier projets : %s\n" "$PROJECTS_DIR"

# Symlinks CLI globales
ln -sf "$INSTALL_DIR/orc.sh" /usr/local/bin/orc
ln -sf "$INSTALL_DIR/agent.sh" /usr/local/bin/agent    # compatibilité
printf "  ${GREEN}✓${NC} Commande 'orc' disponible globalement\n"
printf "  ${GREEN}✓${NC} Commande 'agent' disponible (compatibilité)\n"

# ============================================================
printf "\n${BOLD}5/5 — Configuration${NC}\n"

ENV_FILE="$INSTALL_DIR/.env"

if [ -f "$ENV_FILE" ]; then
  printf "  ${GREEN}✓${NC} .env existant conservé\n"
else
  echo ""
  printf "  ${CYAN}Clé API Anthropic (obligatoire) :${NC}\n"
  read -rp "  ANTHROPIC_API_KEY : " ANTHROPIC_KEY

  if [ -z "$ANTHROPIC_KEY" ]; then
    printf "  ${RED}Clé requise. Relancez deploy.sh.${NC}\n"
    exit 1
  fi

  echo "export ANTHROPIC_API_KEY=\"$ANTHROPIC_KEY\"" > "$ENV_FILE"

  echo ""
  printf "  ${CYAN}Clé API Gemini (optionnel, pour la veille IA) :${NC}\n"
  read -rp "  GEMINI_API_KEY (Entrée pour ignorer) : " GEMINI_KEY

  if [ -n "$GEMINI_KEY" ]; then
    echo "export GEMINI_API_KEY=\"$GEMINI_KEY\"" >> "$ENV_FILE"
  fi

  chmod 600 "$ENV_FILE"
  printf "  ${GREEN}✓${NC} .env créé (%s)\n" "$ENV_FILE"
fi

# ============================================================
# VÉRIFICATION
# ============================================================

echo ""
printf "${BOLD}Vérification :${NC}\n"

CHECKS_OK=true

if command -v git &> /dev/null; then
  printf "  ${GREEN}✓${NC} git %s\n" "$(git --version | cut -d' ' -f3)"
else
  printf "  ${RED}✗${NC} git\n"; CHECKS_OK=false
fi

if command -v node &> /dev/null; then
  printf "  ${GREEN}✓${NC} node %s\n" "$(node --version)"
else
  printf "  ${RED}✗${NC} node\n"; CHECKS_OK=false
fi

if command -v jq &> /dev/null; then
  printf "  ${GREEN}✓${NC} jq %s\n" "$(jq --version)"
else
  printf "  ${RED}✗${NC} jq\n"; CHECKS_OK=false
fi

if command -v claude &> /dev/null; then
  printf "  ${GREEN}✓${NC} claude CLI\n"
else
  printf "  ${RED}✗${NC} claude CLI\n"; CHECKS_OK=false
fi

if [ -f "$ENV_FILE" ]; then
  printf "  ${GREEN}✓${NC} .env configuré\n"
else
  printf "  ${RED}✗${NC} .env manquant\n"; CHECKS_OK=false
fi

if [ "$CHECKS_OK" = false ]; then
  printf "\n${RED}Installation incomplète. Corrigez les erreurs ci-dessus.${NC}\n"
  exit 1
fi

# ============================================================
# TERMINÉ
# ============================================================

echo ""
printf "${GREEN}╔═══════════════════════════════════════════════════╗${NC}\n"
printf "${GREEN}║  Installation terminée !                          ║${NC}\n"
printf "${GREEN}╚═══════════════════════════════════════════════════╝${NC}\n"
echo ""
printf "  ${BOLD}Usage :${NC}\n"
printf "    ${CYAN}orc agent new mon-projet${NC}                # Créer un projet\n"
printf "    ${CYAN}orc agent start mon-projet${NC}              # Lancer\n"
printf "    ${CYAN}orc s${NC}                                   # Vue d'ensemble\n"
printf "    ${CYAN}orc logs mon-projet${NC}                     # Logs temps réel\n"
printf "    ${CYAN}orc roadmap${NC}                             # Roadmap\n"
printf "    ${CYAN}orc admin config${NC}                        # Configuration\n"
printf "    ${CYAN}orc help${NC}                                # Aide complète\n"
echo ""
