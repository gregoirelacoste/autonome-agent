#!/bin/bash
set -euo pipefail

# ============================================================
# Agent Autonome Claude — Initialisation d'un nouveau projet
# ============================================================
#
# Usage :
#   ./init.sh                                    — init interactif
#   ./init.sh mon-projet                         — init avec nom de projet
#   ./init.sh mon-projet --skip-brief            — init sans brief interactif
#   ./init.sh mon-projet --brief briefs/x.md     — init avec brief existant (clarification IA)
#   ./init.sh mon-projet --brief x.md --no-clarify — brief existant sans clarification
#
# Crée un dossier SÉPARÉ (par défaut ../mon-projet/) contenant
# tout le nécessaire. Le repo orc reste un template propre.
# ============================================================

TEMPLATE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# === COULEURS ===
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# === PARSE ARGS ===
PROJECT_ARG=""
SKIP_BRIEF=false
BRIEF_FILE=""
NO_CLARIFY=false

while [ $# -gt 0 ]; do
  case "$1" in
    --skip-brief) SKIP_BRIEF=true; shift ;;
    --brief)
      BRIEF_FILE="${2:-}"
      [ -z "$BRIEF_FILE" ] && { echo -e "${RED}--brief nécessite un chemin de fichier${NC}"; exit 1; }
      shift 2
      ;;
    --no-clarify) NO_CLARIFY=true; shift ;;
    -*) echo -e "${RED}Option inconnue : $1${NC}"; exit 1 ;;
    *) PROJECT_ARG="$1"; shift ;;
  esac
done

# ============================================================
# EN-TÊTE
# ============================================================

clear
echo ""
echo -e "${BLUE}╔═══════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                                                       ║${NC}"
echo -e "${BLUE}║   ${BOLD}Agent Autonome Claude${NC}${BLUE}                                ║${NC}"
echo -e "${BLUE}║   Initialisation d'un nouveau projet                  ║${NC}"
echo -e "${BLUE}║                                                       ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════╝${NC}"
echo ""

# ============================================================
# VÉRIFICATIONS
# ============================================================

echo -e "${CYAN}Vérifications...${NC}"

if ! command -v claude &> /dev/null; then
  echo -e "${RED}  ✗ Claude Code CLI non trouvé.${NC}"
  echo "  Installez-le : https://docs.anthropic.com/en/docs/claude-code"
  exit 1
fi
echo -e "  ${GREEN}✓${NC} Claude Code CLI"

if ! command -v git &> /dev/null; then
  echo -e "${RED}  ✗ Git non trouvé.${NC}"
  exit 1
fi
echo -e "  ${GREEN}✓${NC} Git"

HAS_GH=false
if command -v gh &> /dev/null; then
  echo -e "  ${GREEN}✓${NC} GitHub CLI (gh)"
  HAS_GH=true
else
  echo -e "  ${YELLOW}⚠${NC} GitHub CLI (gh) non trouvé — repo distant à créer manuellement"
fi

echo ""

# ============================================================
# ÉTAPE 1 — NOM DU PROJET
# ============================================================

echo -e "${BOLD}Étape 1/5 — Nom du projet${NC}"
echo ""

if [ -n "$PROJECT_ARG" ]; then
  PROJECT_NAME="$PROJECT_ARG"
  echo -e "  Nom : ${CYAN}$PROJECT_NAME${NC}"
else
  read -rp "  Nom du projet (ex: pc-builder) : " PROJECT_NAME
  if [ -z "$PROJECT_NAME" ]; then
    echo -e "${RED}  Nom requis.${NC}"
    exit 1
  fi
fi

# Slugify
PROJECT_SLUG=$(echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//')

# Le workspace sera créé à côté du template
WORKSPACE_DIR="$(dirname "$TEMPLATE_DIR")/$PROJECT_SLUG"

if [ -d "$WORKSPACE_DIR" ]; then
  echo -e "${RED}  Le dossier $WORKSPACE_DIR existe déjà.${NC}"
  echo "  Supprimez-le ou choisissez un autre nom."
  exit 1
fi

echo -e "  Workspace : ${CYAN}$WORKSPACE_DIR${NC}"
echo ""

# ============================================================
# ÉTAPE 2 — DESCRIPTION COURTE
# ============================================================

echo -e "${BOLD}Étape 2/5 — Description du projet${NC}"
echo ""
echo "  Décris ton projet en 1-2 phrases."
echo "  (Claude utilisera ça comme point de départ pour le brief)"
echo ""
read -rp "  > " PROJECT_DESCRIPTION
echo ""

# ============================================================
# ÉTAPE 3 — CONFIGURATION
# ============================================================

echo -e "${BOLD}Étape 3/5 — Configuration${NC}"
echo ""
echo "  Quel mode d'autonomie ?"
echo ""
echo -e "    ${GREEN}1${NC} — ${BOLD}Pilote automatique${NC} (100% autonome, aucune intervention)"
echo -e "    ${GREEN}2${NC} — ${BOLD}Copilote${NC} (Claude code, tu valides chaque merge)"
echo -e "    ${GREEN}3${NC} — ${BOLD}Supervisé${NC} (pause toutes les 3 features pour review)"
echo ""
read -rp "  Choix [1/2/3] (défaut: 1) : " MODE_CHOICE
MODE_CHOICE="${MODE_CHOICE:-1}"

case "$MODE_CHOICE" in
  1) PAUSE_N=0;  HUMAN_APPROVAL=false; MODE_NAME="pilote automatique" ;;
  2) PAUSE_N=0;  HUMAN_APPROVAL=true;  MODE_NAME="copilote" ;;
  3) PAUSE_N=3;  HUMAN_APPROVAL=false; MODE_NAME="supervisé" ;;
  *) PAUSE_N=0;  HUMAN_APPROVAL=false; MODE_NAME="pilote automatique" ;;
esac

echo -e "  Mode : ${CYAN}$MODE_NAME${NC}"
echo ""

echo "  Activer la veille marché (recherche web) ?"
read -rp "  [O/n] : " RESEARCH_CHOICE
RESEARCH_CHOICE="${RESEARCH_CHOICE:-O}"
if [[ "$RESEARCH_CHOICE" =~ ^[Oo]$ ]]; then
  ENABLE_RESEARCH=true
else
  ENABLE_RESEARCH=false
fi

echo ""
echo "  Nombre max de features avant arrêt ?"
read -rp "  [défaut: 50] : " MAX_FEAT
MAX_FEAT="${MAX_FEAT:-50}"
echo ""

# ============================================================
# ÉTAPE 4 — CRÉATION DU WORKSPACE
# ============================================================

echo -e "${BOLD}Étape 4/5 — Création du workspace${NC}"
echo ""

# Créer le workspace
mkdir -p "$WORKSPACE_DIR"

# Symlinks vers le template (pas de copie)
ln -sf "$TEMPLATE_DIR/orchestrator.sh" "$WORKSPACE_DIR/orchestrator.sh"
ln -sf "$TEMPLATE_DIR/phases" "$WORKSPACE_DIR/phases"
cp "$TEMPLATE_DIR/BRIEF.template.md" "$WORKSPACE_DIR/"

echo -e "  ${GREEN}✓${NC} Orchestrateur lié (symlinks)"

# Créer .orc/ — état et config orchestrateur
mkdir -p "$WORKSPACE_DIR/.orc/logs"

# Générer .orc/config.sh à partir du template
sed \
  -e "s|PROJECT_NAME=\"\"|PROJECT_NAME=\"$PROJECT_SLUG\"|" \
  -e "s|PAUSE_EVERY_N_FEATURES=0|PAUSE_EVERY_N_FEATURES=$PAUSE_N|" \
  -e "s|REQUIRE_HUMAN_APPROVAL=false|REQUIRE_HUMAN_APPROVAL=$HUMAN_APPROVAL|" \
  -e "s|ENABLE_RESEARCH=true|ENABLE_RESEARCH=$ENABLE_RESEARCH|" \
  -e "s|MAX_FEATURES=50|MAX_FEATURES=$MAX_FEAT|" \
  "$TEMPLATE_DIR/config.default.sh" > "$WORKSPACE_DIR/.orc/config.sh"

echo -e "  ${GREEN}✓${NC} .orc/config.sh généré"

# Initialiser git dans le workspace
cd "$WORKSPACE_DIR" && git init -b main > /dev/null 2>&1 && cd - > /dev/null

echo -e "  ${GREEN}✓${NC} Git initialisé"

# Structure .orc/ (research, logs)
mkdir -p "$WORKSPACE_DIR/.orc/research/competitors" \
         "$WORKSPACE_DIR/.orc/research/trends" \
         "$WORKSPACE_DIR/.orc/research/user-needs" \
         "$WORKSPACE_DIR/.orc/research/regulations"

# Copier les skills depuis le template
mkdir -p "$WORKSPACE_DIR/.claude/skills"
cp "$TEMPLATE_DIR/skills-templates/"*.md "$WORKSPACE_DIR/.claude/skills/"

echo -e "  ${GREEN}✓${NC} Skills, .orc/ et .claude/ prêts"

# Créer .gitignore pour le workspace
cat > "$WORKSPACE_DIR/.gitignore" << 'GITIGNORE'
# Symlinks vers le template orc (pas à commiter)
orchestrator.sh
phases

# État runtime orchestrateur
.orc/logs/
.orc/state.json
.orc/tokens.json
.orc/.lock
.orc/.pid
.orc/tracking-issue
GITIGNORE

echo -e "  ${GREEN}✓${NC} .gitignore créé"
echo ""

# ============================================================
# ÉTAPE 5 — RÉDACTION DU BRIEF
# ============================================================

echo -e "${BOLD}Étape 5/5 — Rédaction du BRIEF.md${NC}"
echo ""

if [ -n "$BRIEF_FILE" ]; then
  # Mode --brief : brief fourni, on le copie puis on clarifie
  local_brief=""
  if [ -f "$BRIEF_FILE" ]; then
    local_brief="$BRIEF_FILE"
  elif [ -f "$TEMPLATE_DIR/$BRIEF_FILE" ]; then
    local_brief="$TEMPLATE_DIR/$BRIEF_FILE"
  else
    echo -e "${RED}  Brief non trouvé : $BRIEF_FILE${NC}"
    exit 1
  fi

  cp "$local_brief" "$WORKSPACE_DIR/BRIEF.md"
  echo -e "  ${GREEN}✓${NC} Brief copié depuis $BRIEF_FILE"

  if [ "$NO_CLARIFY" = false ]; then
    echo ""
    echo "  Claude va lire ton brief, poser des questions pour éclaircir"
    echo "  les zones floues, puis l'enrichir."
    echo ""
    echo -e "  ${YELLOW}Appuie sur Entrée pour démarrer...${NC}"
    read -r

    clarify_skill=$(cat "$WORKSPACE_DIR/skills-templates/clarify-brief.md")

    claude "$(cat <<EOF
$clarify_skill

---

Le projet s'appelle "$PROJECT_NAME".
Le brief existant est dans BRIEF.md — lis-le et commence ton analyse.
Pose des questions pour clarifier les zones floues, puis enrichis le brief.

IMPORTANT : Écris le résultat final dans BRIEF.md (dans le dossier courant).
EOF
    )" --max-turns 40 -d "$WORKSPACE_DIR"

    echo ""
    if [ -f "$WORKSPACE_DIR/BRIEF.md" ]; then
      echo -e "  ${GREEN}✓${NC} Brief clarifié et enrichi"
    else
      echo -e "  ${YELLOW}⚠${NC} Brief non mis à jour. Le brief original est conservé."
    fi
  else
    echo -e "  ${YELLOW}Mode --no-clarify :${NC} brief copié tel quel."
  fi

elif [ "$SKIP_BRIEF" = true ]; then
  cp "$WORKSPACE_DIR/BRIEF.template.md" "$WORKSPACE_DIR/BRIEF.md"
  sed -i "s/\[Nom du projet\]/$PROJECT_NAME/" "$WORKSPACE_DIR/BRIEF.md"
  echo -e "  ${YELLOW}Mode --skip-brief :${NC} template copié."
  echo -e "  Remplis-le avant de lancer : ${CYAN}vim $WORKSPACE_DIR/BRIEF.md${NC}"
else
  echo "  Claude va te poser des questions pour rédiger un brief produit complet."
  echo "  Réponds à chaque question. Il rédigera le BRIEF.md à la fin."
  echo ""
  echo -e "  ${YELLOW}Appuie sur Entrée pour démarrer...${NC}"
  read -r

  brief_skill=$(cat "$WORKSPACE_DIR/skills-templates/write-brief.md")

  claude "$(cat <<EOF
$brief_skill

---

L'utilisateur veut créer un projet appelé "$PROJECT_NAME".
Il l'a décrit ainsi : "$PROJECT_DESCRIPTION"

Commence par reformuler ce que tu as compris, puis pose les questions
manquantes pour compléter le brief. Pose les questions une par une ou
par petit groupe thématique pour ne pas submerger l'utilisateur.

IMPORTANT : Écris le résultat final dans BRIEF.md (dans le dossier courant).
EOF
  )" --max-turns 40 -d "$WORKSPACE_DIR"

  echo ""
  if [ -f "$WORKSPACE_DIR/BRIEF.md" ]; then
    echo -e "  ${GREEN}✓${NC} BRIEF.md rédigé"
  else
    echo -e "  ${YELLOW}⚠${NC} BRIEF.md non créé. Tu peux le rédiger manuellement :"
    echo -e "    ${CYAN}cp $WORKSPACE_DIR/BRIEF.template.md $WORKSPACE_DIR/BRIEF.md${NC}"
  fi
fi

# Copier le brief dans .orc/ (cohérent avec orc-agent.sh)
if [ -f "$WORKSPACE_DIR/BRIEF.md" ]; then
  cp "$WORKSPACE_DIR/BRIEF.md" "$WORKSPACE_DIR/.orc/BRIEF.md"
fi

echo ""

# ============================================================
# REPO GITHUB (optionnel)
# ============================================================

if [ "$HAS_GH" = true ]; then
  echo -e "${BOLD}Bonus — Créer un repo GitHub pour le code produit ?${NC}"
  echo ""
  read -rp "  [o/N] : " GH_CHOICE
  GH_CHOICE="${GH_CHOICE:-N}"

  if [[ "$GH_CHOICE" =~ ^[Oo]$ ]]; then
    read -rp "  Visibilité [public/private] (défaut: private) : " GH_VISIBILITY
    GH_VISIBILITY="${GH_VISIBILITY:-private}"

    # Commit initial si aucun commit
    if ! git -C "$WORKSPACE_DIR" rev-parse HEAD &>/dev/null 2>&1; then
      git -C "$WORKSPACE_DIR" add -A > /dev/null 2>&1 || true
      git -C "$WORKSPACE_DIR" commit -m "chore: initial project structure" --allow-empty > /dev/null 2>&1 || true
    fi

    REPO_URL=$(gh repo create "$PROJECT_SLUG" \
      --"$GH_VISIBILITY" \
      --source="$WORKSPACE_DIR" \
      --push \
      --description "$PROJECT_DESCRIPTION" 2>&1 | head -1) || true

    echo -e "  ${GREEN}✓${NC} Repo créé : ${CYAN}${REPO_URL:-erreur}${NC}"
  fi
fi

echo ""

# ============================================================
# RÉCAPITULATIF
# ============================================================

echo -e "${BLUE}╔═══════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  ${BOLD}Projet initialisé !${NC}${BLUE}                                    ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${BOLD}Workspace :${NC}    $WORKSPACE_DIR"
echo -e "  ${BOLD}Projet :${NC}       $PROJECT_NAME"
echo -e "  ${BOLD}Mode :${NC}         $MODE_NAME"
echo -e "  ${BOLD}Recherche :${NC}    $ENABLE_RESEARCH"
echo -e "  ${BOLD}Max features :${NC} $MAX_FEAT"
echo ""
echo -e "  ${BOLD}Structure :${NC}"
echo -e "    $PROJECT_SLUG/"
echo -e "    ├── BRIEF.md            $([ -f "$WORKSPACE_DIR/BRIEF.md" ] && echo -e "${GREEN}✓${NC}" || echo -e "${YELLOW}à rédiger${NC}")"
echo -e "    ├── orchestrator.sh     ${GREEN}→${NC} symlink"
echo -e "    ├── phases/             ${GREEN}→${NC} symlink"
echo -e "    ├── .orc/               ${GREEN}✓${NC} (config, logs, state, roadmap)"
echo -e "    └── .claude/skills/     ${GREEN}✓${NC}"
echo ""
echo -e "  ${BOLD}Prochaines étapes :${NC}"
echo -e "    ${CYAN}cd $WORKSPACE_DIR${NC}"

if [ ! -f "$WORKSPACE_DIR/BRIEF.md" ]; then
  echo -e "    ${CYAN}vim BRIEF.md${NC}              # rédiger le brief"
fi

echo -e "    ${CYAN}./orchestrator.sh${NC}         # lancer l'agent"
echo ""
echo -e "  En arrière-plan :"
echo -e "    ${CYAN}nohup ./orchestrator.sh > .orc/logs/orchestrator.log 2>&1 &${NC}"
echo -e "    ${CYAN}tail -f .orc/logs/orchestrator.log${NC}"
echo ""
