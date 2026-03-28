#!/bin/bash
set -euo pipefail

# ============================================================
# Autonome Agent — CLI de gestion des projets
# ============================================================
#
# Usage :
#   agent new <nom>                     Créer un projet
#   agent new <nom> --brief briefs/x.md Avec un brief existant
#   agent start <nom>                   Lancer en background
#   agent stop <nom>                    Arrêter proprement
#   agent restart <nom>                 Redémarrer
#   agent status                        Vue d'ensemble
#   agent status <nom>                  Détail d'un projet
#   agent logs <nom>                    Logs temps réel
#   agent logs <nom> --full             Log complet
#   agent update                        Mettre à jour le template
# ============================================================

# Résoudre le chemin du template (là où agent.sh est installé)
TEMPLATE_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
PROJECTS_DIR="$HOME/projects"
ENV_FILE="$TEMPLATE_DIR/.env"

# Charger les clés API
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

# ============================================================
# FONCTIONS UTILITAIRES
# ============================================================

die() { printf "${RED}Erreur : %s${NC}\n" "$1" >&2; exit 1; }

project_dir() {
  echo "$PROJECTS_DIR/$1"
}

# Vérifie qu'un projet existe
require_project() {
  local name="$1"
  local dir
  dir=$(project_dir "$name")
  [ -d "$dir" ] || die "Projet '$name' non trouvé. Voir : agent status"
}

# Vérifie si l'orchestrateur tourne pour un projet
is_running() {
  local name="$1"
  local dir
  dir=$(project_dir "$name")
  local pidfile="$dir/.orc/.pid"

  if [ -f "$pidfile" ]; then
    local pid
    pid=$(cat "$pidfile")
    if kill -0 "$pid" 2>/dev/null; then
      return 0
    fi
    # PID mort, nettoyer
    rm -f "$pidfile"
  fi
  return 1
}

# ============================================================
# COMMANDE : new
# ============================================================

cmd_new() {
  local name="${1:-}"
  [ -z "$name" ] && die "Usage : agent new <nom> [--brief briefs/x.md]"

  local dir
  dir=$(project_dir "$name")
  [ -d "$dir" ] && die "Le projet '$name' existe déjà ($dir)"

  shift
  local brief_file=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --brief)
        brief_file="${2:-}"
        [ -z "$brief_file" ] && die "--brief nécessite un chemin de fichier"
        shift 2
        ;;
      *) die "Option inconnue : $1" ;;
    esac
  done

  printf "${BOLD}Création du projet '%s'...${NC}\n\n" "$name"

  # Créer le workspace
  mkdir -p "$dir"
  ln -sf "$TEMPLATE_DIR/orchestrator.sh" "$dir/orchestrator.sh"
  ln -sf "$TEMPLATE_DIR/phases" "$dir/phases"
  cp "$TEMPLATE_DIR/BRIEF.template.md" "$dir/"
  mkdir -p "$dir/.orc/logs"
  cp "$TEMPLATE_DIR/config.default.sh" "$dir/.orc/config.sh"

  # Initialiser git dans le workspace
  [ -d "$dir/.git" ] || ( cd "$dir" && git init -b main > /dev/null 2>&1 )

  # Structure research/
  mkdir -p "$dir/.orc/research/competitors" \
           "$dir/.orc/research/trends" \
           "$dir/.orc/research/user-needs" \
           "$dir/.orc/research/regulations" \
           "$dir/.orc/logs"

  # Skills
  mkdir -p "$dir/.claude/skills"
  cp "$TEMPLATE_DIR/skills-templates/"*.md "$dir/.claude/skills/"

  printf "  ${GREEN}✓${NC} Workspace créé : %s\n" "$dir"

  if [ -n "$brief_file" ]; then
    # Résoudre le chemin du brief (relatif au template ou absolu)
    local resolved_brief=""
    if [ -f "$brief_file" ]; then
      resolved_brief="$brief_file"
    elif [ -f "$TEMPLATE_DIR/$brief_file" ]; then
      resolved_brief="$TEMPLATE_DIR/$brief_file"
    else
      die "Brief non trouvé : $brief_file"
    fi

    cp "$resolved_brief" "$dir/BRIEF.md"
    cp "$resolved_brief" "$dir/.orc/BRIEF.md"
    printf "  ${GREEN}✓${NC} Brief copié depuis %s\n" "$brief_file"
  else
    # Mode interactif — Claude rédige le brief
    printf "\n  ${CYAN}Claude va te poser des questions pour rédiger le brief...${NC}\n\n"

    local brief_skill
    brief_skill=$(cat "$TEMPLATE_DIR/skills-templates/write-brief.md")

    ( cd "$dir" && claude "$brief_skill

---

L'utilisateur crée un projet appelé \"$name\".
Pose les questions une par une. Écris le résultat dans BRIEF.md." --max-turns 40 )

    if [ -f "$dir/BRIEF.md" ]; then
      cp "$dir/BRIEF.md" "$dir/.orc/BRIEF.md"
      printf "\n  ${GREEN}✓${NC} Brief rédigé\n"
    else
      printf "\n  ${YELLOW}⚠${NC} Brief non créé. Rédige-le manuellement :\n"
      printf "    ${CYAN}vim %s/BRIEF.md${NC}\n" "$dir"
    fi
  fi

  echo ""
  printf "${GREEN}Projet '%s' prêt.${NC}\n" "$name"
  printf "  Lancer : ${CYAN}agent start %s${NC}\n" "$name"
  printf "  Éditer la config : ${CYAN}vim %s/.orc/config.sh${NC}\n" "$dir"
  echo ""
}

# ============================================================
# COMMANDE : start
# ============================================================

cmd_start() {
  local name="${1:-}"
  [ -z "$name" ] && die "Usage : agent start <nom>"
  require_project "$name"

  local dir
  dir=$(project_dir "$name")

  if is_running "$name"; then
    local pid
    pid=$(cat "$dir/.orc/.pid")
    die "Déjà en cours (PID $pid). Voir : agent logs $name"
  fi

  [ -f "$dir/BRIEF.md" ] || die "Pas de BRIEF.md dans $dir. Crée-le d'abord."

  # Exporter les clés API
  export ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY:-}"
  export GEMINI_API_KEY="${GEMINI_API_KEY:-}"

  [ -z "$ANTHROPIC_API_KEY" ] && die "ANTHROPIC_API_KEY non configurée. Relancez deploy.sh."

  # Lancer en background
  ( cd "$dir" && nohup ./orchestrator.sh >> .orc/logs/orchestrator.log 2>&1 & echo $! > .orc/.pid )

  local pid
  pid=$(cat "$dir/.orc/.pid")

  printf "${GREEN}Projet '%s' lancé${NC} (PID %s)\n" "$name" "$pid"
  printf "  Logs : ${CYAN}agent logs %s${NC}\n" "$name"
  printf "  Status : ${CYAN}agent status %s${NC}\n" "$name"
  printf "  Stop : ${CYAN}agent stop %s${NC}\n" "$name"
}

# ============================================================
# COMMANDE : stop
# ============================================================

cmd_stop() {
  local name="${1:-}"
  [ -z "$name" ] && die "Usage : agent stop <nom>"
  require_project "$name"

  local dir
  dir=$(project_dir "$name")

  if ! is_running "$name"; then
    printf "${YELLOW}Projet '%s' n'est pas en cours.${NC}\n" "$name"
    return 0
  fi

  local pid
  pid=$(cat "$dir/.orc/.pid")

  printf "Arrêt de '%s' (PID %s)..." "$name" "$pid"

  # SIGTERM — l'orchestrateur gère le cleanup
  kill "$pid" 2>/dev/null || true

  # Attendre max 30s
  local waited=0
  while [ $waited -lt 30 ] && kill -0 "$pid" 2>/dev/null; do
    sleep 1
    waited=$((waited + 1))
    printf "."
  done

  if kill -0 "$pid" 2>/dev/null; then
    printf " ${YELLOW}force kill${NC}"
    kill -9 "$pid" 2>/dev/null || true
  fi

  rm -f "$dir/.orc/.pid"
  printf " ${GREEN}arrêté.${NC}\n"
}

# ============================================================
# COMMANDE : restart
# ============================================================

cmd_restart() {
  local name="${1:-}"
  [ -z "$name" ] && die "Usage : agent restart <nom>"
  cmd_stop "$name"
  sleep 1
  cmd_start "$name"
}

# ============================================================
# COMMANDE : status
# ============================================================

cmd_status() {
  local name="${1:-}"

  if [ -n "$name" ]; then
    cmd_status_detail "$name"
    return
  fi

  # Vue d'ensemble de tous les projets
  mkdir -p "$PROJECTS_DIR"

  local has_projects=false

  printf "\n${BOLD}%-20s %-10s %-12s %-8s %-10s %s${NC}\n" \
    "PROJET" "STATUS" "FEATURES" "ÉCHECS" "COÛT" "ROADMAP"
  printf "%-20s %-10s %-12s %-8s %-10s %s\n" \
    "────────────────────" "──────────" "────────────" "────────" "──────────" "──────────"

  for proj_dir in "$PROJECTS_DIR"/*/; do
    [ -d "$proj_dir" ] || continue
    has_projects=true

    local proj_name
    proj_name=$(basename "$proj_dir")

    # Status
    local status status_color
    if [ -f "$proj_dir/DONE.md" ]; then
      status="done"
      status_color="$GREEN"
    elif is_running "$proj_name"; then
      status="running"
      status_color="$CYAN"
    else
      status="stopped"
      status_color="$YELLOW"
    fi

    # Features
    local feat_count="0" max_feat="?" failures="0"
    if [ -f "$proj_dir/.orc/state.json" ]; then
      feat_count=$(jq -r '.feature_count // 0' "$proj_dir/.orc/state.json" 2>/dev/null || echo "0")
      failures=$(jq -r '.total_failures // 0' "$proj_dir/.orc/state.json" 2>/dev/null || echo "0")
    fi
    if [ -f "$proj_dir/.orc/config.sh" ]; then
      max_feat=$(grep -oP 'MAX_FEATURES=\K\d+' "$proj_dir/.orc/config.sh" 2>/dev/null || echo "?")
    fi

    # Coût
    local cost="\$0.00"
    if [ -f "$proj_dir/.orc/tokens.json" ]; then
      local raw_cost
      raw_cost=$(jq -r '.total_cost_usd // 0' "$proj_dir/.orc/tokens.json" 2>/dev/null || echo "0")
      cost="\$$raw_cost"
    fi

    # Roadmap
    local remaining="—"
    if [ -f "$proj_dir/.orc/ROADMAP.md" ]; then
      local todo
      todo=$(grep -c '^\- \[ \]' "$proj_dir/.orc/ROADMAP.md" 2>/dev/null || true)
      if [ "$todo" -eq 0 ] && [ "$status" = "done" ]; then
        remaining="terminé"
      else
        remaining="${todo} restantes"
      fi
    fi

    printf "%-20s ${status_color}%-10s${NC} %-12s %-8s %-10s %s\n" \
      "$proj_name" "$status" "${feat_count}/${max_feat}" "$failures" "$cost" "$remaining"
  done

  if [ "$has_projects" = false ]; then
    printf "\n  ${DIM}Aucun projet. Créer : ${CYAN}agent new mon-projet${NC}\n"
  fi

  echo ""
}

cmd_status_detail() {
  local name="$1"
  require_project "$name"

  local dir
  dir=$(project_dir "$name")

  echo ""
  printf "${BOLD}Projet : %s${NC}\n" "$name"
  printf "  Dossier : %s\n" "$dir"

  # Status
  if [ -f "$dir/DONE.md" ]; then
    printf "  Status : ${GREEN}terminé${NC}\n"
  elif is_running "$name"; then
    local pid
    pid=$(cat "$dir/.orc/.pid")
    printf "  Status : ${CYAN}en cours${NC} (PID %s)\n" "$pid"
  else
    printf "  Status : ${YELLOW}arrêté${NC}\n"
  fi

  # State
  if [ -f "$dir/.orc/state.json" ]; then
    local feat fail
    feat=$(jq -r '.feature_count // 0' "$dir/.orc/state.json" 2>/dev/null)
    fail=$(jq -r '.total_failures // 0' "$dir/.orc/state.json" 2>/dev/null)
    printf "  Features : %s | Échecs : %s\n" "$feat" "$fail"
  fi

  # Tokens
  if [ -f "$dir/.orc/tokens.json" ]; then
    local cost invocations tokens_in tokens_out
    cost=$(jq -r '.total_cost_usd // 0' "$dir/.orc/tokens.json" 2>/dev/null)
    invocations=$(jq -r '.invocations // 0' "$dir/.orc/tokens.json" 2>/dev/null)
    tokens_in=$(jq -r '.total_input_tokens // 0' "$dir/.orc/tokens.json" 2>/dev/null)
    tokens_out=$(jq -r '.total_output_tokens // 0' "$dir/.orc/tokens.json" 2>/dev/null)
    printf "  Coût : \$%s (%s invocations, %s in / %s out)\n" "$cost" "$invocations" "$tokens_in" "$tokens_out"
  fi

  # Roadmap
  if [ -f "$dir/.orc/ROADMAP.md" ]; then
    local done todo
    done=$(grep -c '^\- \[x\]' "$dir/.orc/ROADMAP.md" 2>/dev/null || true)
    todo=$(grep -c '^\- \[ \]' "$dir/.orc/ROADMAP.md" 2>/dev/null || true)
    printf "  Roadmap : %s faites, %s restantes\n" "$done" "$todo"
  fi

  # Dernières lignes du log
  if [ -f "$dir/.orc/logs/orchestrator.log" ]; then
    echo ""
    printf "  ${DIM}── Dernières lignes du log ──${NC}\n"
    tail -8 "$dir/.orc/logs/orchestrator.log" 2>/dev/null | sed 's/^/  /'
  fi

  echo ""
}

# ============================================================
# COMMANDE : logs
# ============================================================

cmd_logs() {
  local name="${1:-}"
  [ -z "$name" ] && die "Usage : agent logs <nom> [--full]"
  require_project "$name"

  local dir
  dir=$(project_dir "$name")
  local logfile="$dir/.orc/logs/orchestrator.log"

  [ -f "$logfile" ] || die "Pas de log trouvé pour '$name'"

  shift
  if [ "${1:-}" = "--full" ]; then
    less +G "$logfile"
  else
    tail -f "$logfile"
  fi
}

# ============================================================
# COMMANDE : roadmap
# ============================================================

# Parse le frontmatter YAML d'un fichier roadmap item
# Usage: parse_frontmatter "file.md" "field"
# Retourne la valeur du champ
parse_frontmatter() {
  local file="$1"
  local field="$2"
  # Extraire entre les deux --- et chercher le champ
  awk -v field="$field" '
    /^---$/ { block++; next }
    block == 1 {
      # Gérer les champs simples : "key: value" ou "key: \"value\""
      if ($0 ~ "^" field ":") {
        sub("^" field ":[[:space:]]*", "")
        gsub(/^"|"$/, "")
        print
        exit
      }
    }
    block >= 2 { exit }
  ' "$file"
}

# Parse les tags (array YAML) d'un fichier roadmap item
parse_tags() {
  local file="$1"
  awk '
    /^---$/ { block++; next }
    block == 1 && /^tags:/ {
      sub(/^tags:[[:space:]]*\[/, "")
      sub(/\][[:space:]]*$/, "")
      gsub(/,[ ]*/, ",")
      print
      exit
    }
    block >= 2 { exit }
  ' "$file"
}

# Parse les dépendances (array YAML)
parse_depends() {
  local file="$1"
  awk '
    /^---$/ { block++; next }
    block == 1 && /^depends:/ {
      sub(/^depends:[[:space:]]*\[/, "")
      sub(/\][[:space:]]*$/, "")
      gsub(/,[ ]*/, ",")
      print
      exit
    }
    block >= 2 { exit }
  ' "$file"
}

# Extraire une section markdown (## Titre) d'un fichier
extract_section() {
  local file="$1"
  local section="$2"
  local max_lines="${3:-999}"
  awk -v section="$section" -v max="$max_lines" '
    /^---$/ { block++; next }
    block < 2 { next }
    $0 ~ "^## " section { found=1; next }
    found && /^## / { exit }
    found { count++; if (count <= max) print }
  ' "$file"
}

# Couleur selon la priorité
priority_color() {
  case "$1" in
    P0) printf "${RED}" ;;
    P1) printf "${YELLOW}" ;;
    P2) printf "${BLUE}" ;;
    P3) printf "${DIM}" ;;
    *)  printf "${NC}" ;;
  esac
}

# Symbole selon le statut (dossier)
status_symbol() {
  case "$1" in
    in-progress) printf "${CYAN}●${NC}" ;;
    planned)     printf "○" ;;
    backlog)     printf "${DIM}◌${NC}" ;;
    done)        printf "${GREEN}✓${NC}" ;;
    *)           printf "?" ;;
  esac
}

# Tri des items : P0 d'abord, puis P1, etc. À effort égal, XL d'abord.
sort_items() {
  # Reçoit des lignes : "priority|effort|status|file"
  # Trie par priorité (P0<P1<P2<P3) puis effort (XL>L>M>S>XS)
  sort -t'|' -k1,1 -k2,2r
}

# Effort en valeur numérique pour le tri
effort_sort_key() {
  case "$1" in
    XL) echo "5" ;;
    L)  echo "4" ;;
    M)  echo "3" ;;
    S)  echo "2" ;;
    XS) echo "1" ;;
    *)  echo "0" ;;
  esac
}

cmd_roadmap() {
  local verbosity="compact"
  local filter_priority="" filter_tag="" filter_epic="" filter_type="" filter_status=""

  # Parse les options
  while [ $# -gt 0 ]; do
    case "$1" in
      --detail)    verbosity="detail"; shift ;;
      --full)      verbosity="full"; shift ;;
      --priority)  filter_priority="${2:-}"; shift 2 ;;
      --tag)       filter_tag="${2:-}"; shift 2 ;;
      --epic)      filter_epic="${2:-}"; shift 2 ;;
      --type)      filter_type="${2:-}"; shift 2 ;;
      --status)    filter_status="${2:-}"; shift 2 ;;
      -h|--help)   cmd_roadmap_help; return ;;
      *) die "Option inconnue : $1. Voir : agent roadmap --help" ;;
    esac
  done

  local roadmap_dir="$TEMPLATE_DIR/roadmap"
  [ -d "$roadmap_dir" ] || die "Dossier roadmap/ non trouvé dans $TEMPLATE_DIR"

  # Compter par priorité
  local count_p0=0 count_p1=0 count_p2=0 count_p3=0 count_total=0

  # Collecter tous les items
  local items_data=""
  for status_dir in in-progress planned backlog done; do
    local dir="$roadmap_dir/$status_dir"
    [ -d "$dir" ] || continue

    # Filtrer par statut si demandé
    if [ -n "$filter_status" ] && [ "$filter_status" != "$status_dir" ]; then
      continue
    fi

    for item_file in "$dir"/ROADMAP-*.md; do
      [ -f "$item_file" ] || continue

      local item_id item_title item_priority item_type item_effort item_tags item_epic

      item_id=$(parse_frontmatter "$item_file" "id")
      item_title=$(parse_frontmatter "$item_file" "title")
      item_priority=$(parse_frontmatter "$item_file" "priority")
      item_type=$(parse_frontmatter "$item_file" "type")
      item_effort=$(parse_frontmatter "$item_file" "effort")
      item_tags=$(parse_tags "$item_file")
      item_epic=$(parse_frontmatter "$item_file" "epic")

      # Appliquer les filtres
      if [ -n "$filter_priority" ] && [ "$item_priority" != "$filter_priority" ]; then
        continue
      fi
      if [ -n "$filter_tag" ]; then
        if ! echo ",$item_tags," | grep -qi ",$filter_tag,"; then
          continue
        fi
      fi
      if [ -n "$filter_epic" ] && [ "$item_epic" != "$filter_epic" ]; then
        continue
      fi
      if [ -n "$filter_type" ] && [ "$item_type" != "$filter_type" ]; then
        continue
      fi

      # Compter par priorité
      case "$item_priority" in
        P0) count_p0=$((count_p0 + 1)) ;;
        P1) count_p1=$((count_p1 + 1)) ;;
        P2) count_p2=$((count_p2 + 1)) ;;
        P3) count_p3=$((count_p3 + 1)) ;;
      esac
      count_total=$((count_total + 1))

      # Stocker pour tri : priority|effort_key|status|file|id|title|priority_raw|type|effort|tags|epic
      local ekey
      ekey=$(effort_sort_key "$item_effort")
      items_data+="${item_priority}|${ekey}|${status_dir}|${item_file}|${item_id}|${item_title}|${item_priority}|${item_type}|${item_effort}|${item_tags}|${item_epic}"$'\n'
    done
  done

  if [ "$count_total" -eq 0 ]; then
    printf "\n${DIM}Aucun item dans la roadmap.${NC}\n\n"
    return
  fi

  # Header
  echo ""
  printf "${BOLD}ROADMAP — autonome-agent${NC}"
  printf "         ${RED}P0: %d${NC} | ${YELLOW}P1: %d${NC} | ${BLUE}P2: %d${NC} | ${DIM}P3: %d${NC}\n" \
    "$count_p0" "$count_p1" "$count_p2" "$count_p3"
  printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"

  # Trier les items
  local sorted_items
  sorted_items=$(echo "$items_data" | grep -v '^$' | sort_items)

  # Afficher par statut
  local current_status=""
  while IFS='|' read -r _prio _ekey status filepath item_id item_title priority item_type effort tags epic; do
    [ -z "$status" ] && continue

    # Nouveau groupe de statut
    if [ "$status" != "$current_status" ]; then
      current_status="$status"
      local status_label count_in_status
      case "$status" in
        in-progress) status_label="EN COURS" ;;
        planned)     status_label="PLANIFIÉ" ;;
        backlog)     status_label="BACKLOG" ;;
        done)        status_label="TERMINÉ" ;;
        *)           status_label="$status" ;;
      esac
      count_in_status=$(echo "$sorted_items" | grep -c "|${status}|" 2>/dev/null || true)
      echo ""
      printf " ${BOLD}%s${NC} (%d)\n" "$status_label" "$count_in_status"
    fi

    # Symbole et couleur
    local sym pcolor
    sym=$(status_symbol "$status")
    pcolor=$(priority_color "$priority")

    # === Niveau COMPACT ===
    printf "  %b ${pcolor}%-12s${NC} [%s/%s] %-42s ${DIM}%s${NC}\n" \
      "$sym" "$item_id" "$priority" "$effort" "$item_title" "$tags"

    # === Niveau DETAIL ===
    if [ "$verbosity" = "detail" ] || [ "$verbosity" = "full" ]; then
      # Contexte (3 premières lignes)
      local context
      context=$(extract_section "$filepath" "Contexte" 3)
      if [ -n "$context" ]; then
        echo "$context" | while IFS= read -r line; do
          printf "    ${DIM}%s${NC}\n" "$line"
        done
      fi

      # Dépendances
      local deps
      deps=$(parse_depends "$filepath")
      if [ -n "$deps" ] && [ "$deps" != "[]" ]; then
        printf "    ${DIM}Dépend de : %s${NC}\n" "$deps"
      fi

      # Epic
      if [ -n "$epic" ] && [ "$epic" != '""' ]; then
        printf "    ${DIM}Epic : %s${NC}\n" "$epic"
      fi

      # Dates
      local created updated
      created=$(parse_frontmatter "$filepath" "created")
      updated=$(parse_frontmatter "$filepath" "updated")
      if [ -n "$created" ]; then
        printf "    ${DIM}Créé : %s | MàJ : %s${NC}\n" "$created" "${updated:-$created}"
      fi
      echo ""
    fi

    # === Niveau FULL ===
    if [ "$verbosity" = "full" ]; then
      # Spécification complète
      local spec
      spec=$(extract_section "$filepath" "Spécification")
      if [ -n "$spec" ]; then
        printf "    ${BOLD}Spécification :${NC}\n"
        echo "$spec" | while IFS= read -r line; do
          printf "    %s\n" "$line"
        done
        echo ""
      fi

      # Critères de validation
      local criteria
      criteria=$(extract_section "$filepath" "Critères de validation")
      if [ -n "$criteria" ]; then
        printf "    ${BOLD}Critères :${NC}\n"
        echo "$criteria" | while IFS= read -r line; do
          printf "    %s\n" "$line"
        done
        echo ""
      fi

      # Notes
      local notes
      notes=$(extract_section "$filepath" "Notes")
      if [ -n "$notes" ]; then
        printf "    ${DIM}Notes : %s${NC}\n" "$(echo "$notes" | head -3 | tr '\n' ' ')"
        echo ""
      fi

      printf "    ──────────────────────────────────────────────────────\n"
    fi

  done <<< "$sorted_items"

  echo ""

  # Filtres actifs
  local active_filters=""
  [ -n "$filter_priority" ] && active_filters+="priority=$filter_priority "
  [ -n "$filter_tag" ] && active_filters+="tag=$filter_tag "
  [ -n "$filter_epic" ] && active_filters+="epic=$filter_epic "
  [ -n "$filter_type" ] && active_filters+="type=$filter_type "
  [ -n "$filter_status" ] && active_filters+="status=$filter_status "
  if [ -n "$active_filters" ]; then
    printf "${DIM}Filtres actifs : %s${NC}\n\n" "$active_filters"
  fi
}

cmd_roadmap_help() {
  echo ""
  printf "${BOLD}agent roadmap — Suivi de la roadmap${NC}\n"
  echo ""
  printf "  ${CYAN}agent roadmap${NC}                    Vue compacte\n"
  printf "  ${CYAN}agent roadmap --detail${NC}            Vue détaillée (contexte, dépendances)\n"
  printf "  ${CYAN}agent roadmap --full${NC}              Vue exhaustive (specs, critères)\n"
  echo ""
  printf "  ${BOLD}Filtres :${NC}\n"
  printf "  ${CYAN}--priority P0|P1|P2|P3${NC}           Par priorité\n"
  printf "  ${CYAN}--tag <tag>${NC}                      Par tag\n"
  printf "  ${CYAN}--epic <epic>${NC}                    Par epic\n"
  printf "  ${CYAN}--type <type>${NC}                    Par type (feature, bugfix, etc.)\n"
  printf "  ${CYAN}--status <status>${NC}                Par statut (planned, in-progress, etc.)\n"
  echo ""
  printf "  ${DIM}Filtres combinables : agent roadmap --priority P1 --tag adoption${NC}\n"
  echo ""
}

# ============================================================
# COMMANDE : update
# ============================================================

cmd_update() {
  printf "${BOLD}Mise à jour du template...${NC}\n"

  if [ -d "$TEMPLATE_DIR/.git" ]; then
    git -C "$TEMPLATE_DIR" pull --ff-only
    printf "${GREEN}Template mis à jour.${NC}\n"
    printf "${DIM}Note : les workspaces existants ne sont pas affectés.${NC}\n"
  else
    die "$TEMPLATE_DIR n'est pas un repo git."
  fi
}

# ============================================================
# COMMANDE : help
# ============================================================

cmd_help() {
  echo ""
  printf "${BOLD}Autonome Agent — CLI${NC}\n"
  echo ""
  printf "  ${CYAN}agent new <nom>${NC}                     Créer un projet\n"
  printf "  ${CYAN}agent new <nom> --brief briefs/x.md${NC} Avec un brief existant\n"
  printf "  ${CYAN}agent start <nom>${NC}                   Lancer en background\n"
  printf "  ${CYAN}agent stop <nom>${NC}                    Arrêter proprement\n"
  printf "  ${CYAN}agent restart <nom>${NC}                 Redémarrer\n"
  printf "  ${CYAN}agent status${NC}                        Vue d'ensemble\n"
  printf "  ${CYAN}agent status <nom>${NC}                  Détail d'un projet\n"
  printf "  ${CYAN}agent logs <nom>${NC}                    Logs temps réel\n"
  printf "  ${CYAN}agent logs <nom> --full${NC}             Log complet\n"
  printf "  ${CYAN}agent roadmap${NC}                       Roadmap compacte\n"
  printf "  ${CYAN}agent roadmap --detail${NC}              Roadmap détaillée\n"
  printf "  ${CYAN}agent roadmap --full${NC}                Roadmap exhaustive\n"
  printf "  ${CYAN}agent update${NC}                        Mettre à jour le template\n"
  printf "  ${CYAN}agent help${NC}                          Cette aide\n"
  echo ""
}

# ============================================================
# DISPATCH
# ============================================================

COMMAND="${1:-help}"
shift || true

case "$COMMAND" in
  new)     cmd_new "$@" ;;
  start)   cmd_start "$@" ;;
  stop)    cmd_stop "$@" ;;
  restart) cmd_restart "$@" ;;
  status)  cmd_status "$@" ;;
  logs)    cmd_logs "$@" ;;
  roadmap) cmd_roadmap "$@" ;;
  update)  cmd_update ;;
  help|-h|--help) cmd_help ;;
  *) die "Commande inconnue : $COMMAND. Voir : agent help" ;;
esac
