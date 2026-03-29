#!/bin/bash
# ============================================================
# orc-roadmap.sh — Gestion kanban des roadmaps projet
# ============================================================
#
# Fonctions : cmd_roadmap_ticket, cmd_roadmap_brainstorm
#             + utilitaires kanban (init, migration, affichage)
#
# Variables attendues de orc.sh :
#   ORC_DIR, PROJECTS_DIR, RED, GREEN, YELLOW, BLUE, CYAN, BOLD, DIM, NC, die()
# ============================================================

# ============================================================
# UTILITAIRES KANBAN
# ============================================================

# Initialise la structure kanban pour un projet
kanban_init() {
  local project_dir="$1"
  mkdir -p "$project_dir/.orc/roadmap"/{backlog,todo,in-progress,done}
}

# Prochain ID disponible dans le kanban
kanban_next_id() {
  local project_dir="$1"
  local max=0
  for f in "$project_dir/.orc/roadmap"/*/*.md; do
    [ -f "$f" ] || continue
    local num
    num=$(basename "$f" | grep -o '^[0-9]*' || echo 0)
    [ "$num" -gt "$max" ] && max="$num"
  done
  echo $((max + 1))
}

# Lit un champ du frontmatter YAML d'un ticket
kanban_field() {
  local file="$1" field="$2"
  sed -n '/^---$/,/^---$/p' "$file" 2>/dev/null | grep "^${field}:" | head -1 | sed "s/^${field}: *//;s/^\"//;s/\"$//"
}

# Lit le titre d'un ticket
kanban_title() {
  kanban_field "$1" "title"
}

# Lit la priorité d'un ticket
kanban_priority() {
  kanban_field "$1" "priority"
}

# Lit le type d'un ticket
kanban_type() {
  kanban_field "$1" "type"
}

# Lit l'effort d'un ticket
kanban_effort() {
  kanban_field "$1" "effort"
}

# Lit l'ID d'un ticket
kanban_id() {
  kanban_field "$1" "id"
}

# Lit le contenu markdown (après le frontmatter) d'un ticket
kanban_content() {
  local file="$1"
  # Skip le frontmatter (entre les deux ---)
  awk 'BEGIN{c=0} /^---$/{c++; next} c>=2{print}' "$file" 2>/dev/null
}

# Liste les tickets d'un statut, triés par priorité puis ID
kanban_list_sorted() {
  local project_dir="$1" status="$2"
  local dir="$project_dir/.orc/roadmap/$status"
  [ -d "$dir" ] || return 0

  # Construire une liste triable : "priority_num|id|filepath"
  local entries=""
  for f in "$dir"/*.md; do
    [ -f "$f" ] || continue
    local prio
    prio=$(kanban_priority "$f")
    local prio_num
    case "$prio" in
      P0) prio_num=0 ;; P1) prio_num=1 ;; P2) prio_num=2 ;; P3) prio_num=3 ;; *) prio_num=9 ;;
    esac
    local id_num
    id_num=$(basename "$f" | grep -o '^[0-9]*' || echo 999)
    entries="${entries}${prio_num}|${id_num}|${f}
"
  done

  # Trier et retourner les chemins
  echo "$entries" | sort -t'|' -k1,1n -k2,2n | while IFS='|' read -r _ _ path; do
    [ -n "$path" ] && echo "$path"
  done
}

# Compte les tickets par statut
kanban_count() {
  local project_dir="$1" status="$2"
  local dir="$project_dir/.orc/roadmap/$status"
  [ -d "$dir" ] || { echo 0; return; }
  local count=0
  for f in "$dir"/*.md; do
    [ -f "$f" ] && count=$((count + 1))
  done
  echo "$count"
}

# Génère la vue ROADMAP.md (compat dashboard/status)
kanban_regenerate_view() {
  local project_dir="$1"
  local roadmap="$project_dir/.orc/ROADMAP.md"
  local project_name
  project_name=$(basename "$project_dir")

  {
    echo "# ROADMAP — $project_name"
    echo ""
    echo "_Vue auto-generee depuis .orc/roadmap/ — ne pas editer manuellement_"
    echo ""

    # In-progress
    local has_inprogress=false
    for f in "$project_dir/.orc/roadmap/in-progress"/*.md; do
      [ -f "$f" ] || continue
      if [ "$has_inprogress" = false ]; then
        echo "## En cours"
        has_inprogress=true
      fi
      echo "- [ ] $(kanban_title "$f")"
    done
    [ "$has_inprogress" = true ] && echo ""

    # Todo (trié par priorité)
    local has_todo=false
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      if [ "$has_todo" = false ]; then
        echo "## MVP"
        has_todo=true
      fi
      echo "- [ ] $(kanban_title "$f")"
    done < <(kanban_list_sorted "$project_dir" "todo")
    [ "$has_todo" = true ] && echo ""

    # Backlog
    local has_backlog=false
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      if [ "$has_backlog" = false ]; then
        echo "## Backlog"
        has_backlog=true
      fi
      echo "- [ ] $(kanban_title "$f")"
    done < <(kanban_list_sorted "$project_dir" "backlog")
    [ "$has_backlog" = true ] && echo ""

    # Done
    local has_done=false
    for f in "$project_dir/.orc/roadmap/done"/*.md; do
      [ -f "$f" ] || continue
      if [ "$has_done" = false ]; then
        echo "## Termine"
        has_done=true
      fi
      echo "- [x] $(kanban_title "$f")"
    done
  } > "$roadmap"
}

# Génère un slug depuis un titre
kanban_slug() {
  echo "$1" | sed 's/[^a-zA-Z0-9]/-/g' | tr '[:upper:]' '[:lower:]' | sed 's/^-*//;s/-*$//;s/--*/-/g' | head -c 40
}

# Crée un ticket dans le kanban
# Usage: kanban_create_ticket <project_dir> <status> <title> <priority> <type> <effort> <epic> <source> <content>
kanban_create_ticket() {
  local project_dir="$1" status="$2" title="$3" priority="$4" type="$5"
  local effort="$6" epic="$7" source="$8" content="$9"

  kanban_init "$project_dir"
  local id
  id=$(kanban_next_id "$project_dir")
  local padded_id
  padded_id=$(printf "%03d" "$id")
  local slug
  slug=$(kanban_slug "$title")
  local filename="$padded_id-$slug.md"
  local filepath="$project_dir/.orc/roadmap/$status/$filename"
  local today
  today=$(date '+%Y-%m-%d')

  cat > "$filepath" <<EOF
---
id: $id
title: "$title"
priority: $priority
type: $type
effort: $effort
tags: []
epic: $epic
created: $today
source: $source
---

$content
EOF

  echo "$filepath"
}

# Liste les titres des tickets d'un statut (pour injection dans les prompts)
kanban_titles_list() {
  local project_dir="$1" status="$2"
  local dir="$project_dir/.orc/roadmap/$status"
  [ -d "$dir" ] || return 0
  for f in "$dir"/*.md; do
    [ -f "$f" ] || continue
    local id_num prio title
    id_num=$(basename "$f" | grep -o '^[0-9]*' || echo "?")
    prio=$(kanban_priority "$f")
    title=$(kanban_title "$f")
    echo "  #$id_num [$prio] $title"
  done
}

# Vérifie si un projet est en cours d'exécution
_is_project_running() {
  local name="$1"
  local dir
  dir=$(project_dir "$name")
  local pidfile="$dir/.orc/.pid"
  if [ -f "$pidfile" ]; then
    local pid
    pid=$(cat "$pidfile")
    kill -0 "$pid" 2>/dev/null && return 0
  fi
  return 1
}

# Vérifie si un projet est "done"
_is_project_done() {
  local dir="$1"
  [ -f "$dir/DONE.md" ]
}

# Archive DONE.md et reset le workflow pour reprendre
_resume_from_done() {
  local dir="$1" name="$2"
  if [ -f "$dir/DONE.md" ]; then
    local archive_name="DONE-$(date '+%Y%m%d-%H%M%S').md"
    mv "$dir/DONE.md" "$dir/.orc/logs/$archive_name"
    printf "${DIM}DONE.md archivé → .orc/logs/%s${NC}\n" "$archive_name"

    # Reset workflow_phase dans state.json
    if [ -f "$dir/.orc/state.json" ] && command -v jq &>/dev/null; then
      local tmp
      tmp=$(jq '.workflow_phase = "features"' "$dir/.orc/state.json" 2>/dev/null)
      [ -n "$tmp" ] && echo "$tmp" > "$dir/.orc/state.json"
    fi
  fi
}

# Propose de lancer/relancer le projet après ajout de tickets
_propose_start() {
  local name="$1" dir="$2" ticket_count="$3"

  echo ""
  if _is_project_running "$name"; then
    printf "${GREEN}Le projet tourne — les tickets seront pris en compte au prochain cycle.${NC}\n"
  else
    printf "${BOLD}%s ticket(s) ajouté(s). Lancer le projet ?${NC}\n" "$ticket_count"
    read -rp "  Démarrer orc agent start $name ? [O/n] " answer
    case "${answer:-O}" in
      [Oo]|[Yy]|"")
        cmd_start "$name"
        ;;
      *)
        printf "${DIM}OK. Lancer manuellement : orc agent start %s${NC}\n" "$name"
        ;;
    esac
  fi
}

# ============================================================
# COMMANDE : orc roadmap ticket <projet>
# ============================================================

cmd_roadmap_ticket() {
  local name="" quick_desc="" forced_type="" forced_priority=""

  # Parser les arguments
  while [ $# -gt 0 ]; do
    case "$1" in
      --quick)  quick_desc="${2:-}"; [ -z "$quick_desc" ] && die "--quick requiert une description"; shift 2 ;;
      --type)   forced_type="${2:-}"; shift 2 ;;
      --priority) forced_priority="${2:-}"; shift 2 ;;
      -h|--help)
        echo ""
        printf "${BOLD}orc roadmap ticket${NC} — Ajouter un ticket assisté par l'IA\n\n"
        printf "  ${CYAN}orc roadmap ticket <projet>${NC}              Mode interactif (dialogue + challenge IA)\n"
        printf "  ${CYAN}orc roadmap ticket <projet> --quick \"desc\"${NC} Mode rapide (skip le dialogue)\n"
        printf "  ${CYAN}orc roadmap ticket <projet> --type bugfix${NC}  Pré-sélectionner le type\n"
        printf "  ${CYAN}orc roadmap ticket <projet> --priority P0${NC}  Forcer la priorité\n"
        echo ""
        return 0
        ;;
      *)
        if [ -z "$name" ]; then
          name="$1"; shift
        else
          die "Argument inattendu : $1"
        fi
        ;;
    esac
  done

  # Inférer le projet si non spécifié
  if [ -z "$name" ]; then
    name=$(infer_project_from_cwd 2>/dev/null) || die "Usage : orc roadmap ticket <projet>"
  fi
  require_project "$name"

  local dir
  dir=$(project_dir "$name")
  kanban_init "$dir"

  echo ""
  printf "${BOLD}Nouveau ticket — %s${NC}\n" "$name"
  printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"

  # --- Choix du type si pas forcé ---
  local ticket_type="$forced_type"
  if [ -z "$ticket_type" ]; then
    echo ""
    printf "  ${BOLD}Type de ticket :${NC}\n"
    printf "    ${CYAN}1${NC}) feature     — Nouvelle fonctionnalité\n"
    printf "    ${CYAN}2${NC}) bugfix      — Correction de bug\n"
    printf "    ${CYAN}3${NC}) evolution   — Amélioration d'une feature existante\n"
    printf "    ${CYAN}4${NC}) refactor    — Refactoring technique\n"
    echo ""
    read -rp "  Choix [1-4] : " type_choice
    case "$type_choice" in
      1) ticket_type="feature" ;;
      2) ticket_type="bugfix" ;;
      3) ticket_type="evolution" ;;
      4) ticket_type="refactor" ;;
      *) ticket_type="feature" ;;
    esac
  fi

  # --- Phase 1 : Échange avec l'humain ---
  local conversation_output=""

  if [ -n "$quick_desc" ]; then
    # Mode rapide : skip la phase dialogue
    conversation_output="L'utilisateur demande : $quick_desc (type: $ticket_type)"
    printf "\n${DIM}Mode rapide — skip du dialogue${NC}\n"
  else
    printf "\n${BOLD}Phase 1 — Dialogue${NC} ${DIM}(décrivez votre besoin, l'IA clarifie)${NC}\n\n"

    # Collecter le contexte projet pour la session
    local brief_summary=""
    [ -f "$dir/.orc/BRIEF.md" ] && brief_summary=$(head -30 "$dir/.orc/BRIEF.md")
    [ -f "$dir/BRIEF.md" ] && [ -z "$brief_summary" ] && brief_summary=$(head -30 "$dir/BRIEF.md")

    local existing_tickets=""
    existing_tickets=$(kanban_titles_list "$dir" "todo")
    local done_tickets=""
    done_tickets=$(kanban_titles_list "$dir" "done")

    local dialog_prompt
    dialog_prompt="Tu es un product manager expérimenté. Un développeur veut créer un ticket de type '$ticket_type' pour le projet '$name'.

CONTEXTE PROJET :
$([ -n "$brief_summary" ] && echo "$brief_summary" || echo "[Brief non disponible]")

TICKETS EN COURS/TODO :
$([ -n "$existing_tickets" ] && echo "$existing_tickets" || echo "[Aucun]")

TICKETS TERMINÉS :
$([ -n "$done_tickets" ] && echo "$done_tickets" || echo "[Aucun]")

TON RÔLE :
- Pose 2-3 questions de clarification pour bien comprendre le besoin
- Comprends le problème utilisateur précis
- Comprends le résultat attendu
- Identifie les contraintes connues
- NE RÉDIGE PAS encore le ticket — juste comprends
- Quand tu as assez d'informations, dis \"J'ai bien compris le besoin, je vais maintenant analyser et rédiger le ticket.\""

    # Session interactive Claude — l'IA écrit le résumé dans un fichier
    local dialog_summary_file="$dir/.orc/logs/ticket-dialog-$(date '+%Y%m%d-%H%M%S').md"

    dialog_prompt="$dialog_prompt

IMPORTANT : Quand tu as compris le besoin, écris un résumé structuré dans $dialog_summary_file avec :
- Le problème utilisateur
- Le résultat attendu
- Les contraintes identifiées
- Le type : $ticket_type
Puis dis à l'humain que tu passes à l'analyse."

    ( cd "$dir" && claude --max-turns 8 \
      --model "${CLAUDE_MODEL:-claude-sonnet-4-6}" \
      -- "$dialog_prompt" ) || true

    if [ -f "$dialog_summary_file" ] && [ -s "$dialog_summary_file" ]; then
      conversation_output=$(cat "$dialog_summary_file")
    else
      # Fallback : demander directement
      echo ""
      read -rp "  Décrivez votre besoin en 1-2 phrases : " manual_desc
      conversation_output="L'utilisateur demande : $manual_desc (type: $ticket_type)"
    fi
  fi

  # --- Phase 2 : Analyse + Recherche + Évaluation + Rédaction ---
  printf "\n${BOLD}Phase 2 — Analyse, recherche et rédaction${NC} ${DIM}(l'IA travaille...)${NC}\n"

  local brief_content="" index_content="" done_content=""
  [ -f "$dir/.orc/BRIEF.md" ] && brief_content=$(cat "$dir/.orc/BRIEF.md")
  [ -f "$dir/BRIEF.md" ] && [ -z "$brief_content" ] && brief_content=$(cat "$dir/BRIEF.md")
  [ -f "$dir/.orc/codebase/INDEX.md" ] && index_content=$(cat "$dir/.orc/codebase/INDEX.md")
  [ -f "$dir/DONE.md" ] && done_content=$(cat "$dir/DONE.md")

  local existing_todo="" existing_done=""
  existing_todo=$(kanban_titles_list "$dir" "todo")
  existing_done=$(kanban_titles_list "$dir" "done")

  local next_id
  next_id=$(kanban_next_id "$dir")
  local padded_id
  padded_id=$(printf "%03d" "$next_id")

  local priority_hint=""
  [ -n "$forced_priority" ] && priority_hint="PRIORITÉ IMPOSÉE : $forced_priority"

  # Charger le prompt depuis le fichier phase
  local challenge_prompt_file="$ORC_DIR/phases/ticket-challenge.md"
  local challenge_prompt=""

  if [ -f "$challenge_prompt_file" ]; then
    challenge_prompt=$(cat "$challenge_prompt_file")
    # Substituer les placeholders
    challenge_prompt="${challenge_prompt//\{\{PROJECT_NAME\}\}/$name}"
    challenge_prompt="${challenge_prompt//\{\{TICKET_TYPE\}\}/$ticket_type}"
    challenge_prompt="${challenge_prompt//\{\{CONVERSATION\}\}/$conversation_output}"
    challenge_prompt="${challenge_prompt//\{\{BRIEF\}\}/${brief_content:-[Brief non disponible]}}"
    challenge_prompt="${challenge_prompt//\{\{INDEX\}\}/${index_content:-[Index non disponible]}}"
    challenge_prompt="${challenge_prompt//\{\{DONE\}\}/${done_content:-[Projet en cours]}}"
    challenge_prompt="${challenge_prompt//\{\{TODO_TICKETS\}\}/${existing_todo:-[Aucun]}}"
    challenge_prompt="${challenge_prompt//\{\{DONE_TICKETS\}\}/${existing_done:-[Aucun]}}"
    challenge_prompt="${challenge_prompt//\{\{NEXT_ID\}\}/$next_id}"
    challenge_prompt="${challenge_prompt//\{\{PADDED_ID\}\}/$padded_id}"
    challenge_prompt="${challenge_prompt//\{\{PRIORITY_HINT\}\}/${priority_hint}}"
    challenge_prompt="${challenge_prompt//\{\{PROJECT_DIR\}\}/$dir}"
  else
    die "Prompt ticket-challenge.md non trouvé dans $ORC_DIR/phases/"
  fi

  # Invocation one-shot Claude pour analyse + rédaction (dans le répertoire du projet)
  ( cd "$dir" && claude -p "$challenge_prompt" \
    --max-turns 15 \
    --model "${CLAUDE_MODEL:-claude-sonnet-4-6}" \
    --allowedTools "Read,Write,WebSearch,WebFetch,Bash" ) 2>/dev/null || {
    die "Erreur lors de l'analyse du ticket."
  }

  # --- Phase 3 : Review humain ---
  # Trouver le ticket créé
  local created_ticket=""
  for f in "$dir/.orc/roadmap/todo/$padded_id"-*.md "$dir/.orc/roadmap/backlog/$padded_id"-*.md; do
    [ -f "$f" ] && created_ticket="$f" && break
  done

  if [ -z "$created_ticket" ] || [ ! -f "$created_ticket" ]; then
    die "Le ticket n'a pas été créé. Vérifiez les logs."
  fi

  printf "\n${BOLD}Phase 3 — Review${NC}\n"
  printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
  echo ""

  # Afficher le ticket
  local t_title t_priority t_type t_effort
  t_title=$(kanban_title "$created_ticket")
  t_priority=$(kanban_priority "$created_ticket")
  t_type=$(kanban_type "$created_ticket")
  t_effort=$(kanban_effort "$created_ticket")

  printf "  ${BOLD}%s${NC}\n" "$t_title"
  printf "  ${CYAN}%s${NC} | ${YELLOW}%s${NC} | ${DIM}%s${NC} | effort: %s\n" "$t_priority" "$t_type" "#$next_id" "$t_effort"
  echo ""
  kanban_content "$created_ticket" | head -30 | while IFS= read -r line; do
    printf "  %s\n" "$line"
  done
  echo ""
  printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"

  # Demander validation
  echo ""
  printf "  ${CYAN}v${NC})alider   ${CYAN}e${NC})diter   ${CYAN}p${NC})riorité   ${RED}r${NC})efuser\n"
  echo ""
  read -rp "  Choix [v/e/p/r] : " review_choice

  case "${review_choice:-v}" in
    v|V|"")
      printf "\n${GREEN}Ticket validé.${NC}\n"
      ;;
    e|E)
      local editor="${EDITOR:-vi}"
      "$editor" "$created_ticket"
      printf "\n${GREEN}Ticket mis à jour.${NC}\n"
      ;;
    p|P)
      echo ""
      printf "  Priorité actuelle : ${BOLD}%s${NC}\n" "$t_priority"
      printf "    ${CYAN}0${NC}) P0 — Critique\n"
      printf "    ${CYAN}1${NC}) P1 — Haute\n"
      printf "    ${CYAN}2${NC}) P2 — Moyenne\n"
      printf "    ${CYAN}3${NC}) P3 — Basse\n"
      read -rp "  Nouvelle priorité [0-3] : " prio_choice
      local new_prio="P${prio_choice:-1}"
      sed -i "s/^priority: .*/priority: $new_prio/" "$created_ticket"
      printf "\n${GREEN}Priorité mise à jour → %s${NC}\n" "$new_prio"
      ;;
    r|R)
      rm -f "$created_ticket"
      printf "\n${RED}Ticket supprimé.${NC}\n"
      return 0
      ;;
  esac

  # Régénérer la vue ROADMAP.md
  kanban_regenerate_view "$dir"

  # Hot injection : si P0 et projet en cours, notifier via human-notes
  local final_priority
  final_priority=$(kanban_priority "$created_ticket")
  if [ "$final_priority" = "P0" ] && _is_project_running "$name"; then
    {
      echo ""
      echo "## Ticket P0 ajouté ($(date '+%Y-%m-%d %H:%M'))"
      echo ""
      echo "Titre : $(kanban_title "$created_ticket")"
      echo "Fichier : $created_ticket"
      echo "Ce ticket est prioritaire, à traiter dès que possible."
    } >> "$dir/.orc/human-notes.md"
    printf "${YELLOW}Ticket P0 — notification injectée dans human-notes.md${NC}\n"
  fi

  # Archiver DONE.md si projet terminé
  if _is_project_done "$dir"; then
    _resume_from_done "$dir" "$name"
  fi

  # Proposer de lancer le projet
  _propose_start "$name" "$dir" 1
}

# ============================================================
# COMMANDE : orc roadmap brainstorm <projet>
# ============================================================

cmd_roadmap_brainstorm() {
  local name=""

  # Parser les arguments
  while [ $# -gt 0 ]; do
    case "$1" in
      -h|--help)
        echo ""
        printf "${BOLD}orc roadmap brainstorm${NC} — Brainstorm IA pour la prochaine itération\n\n"
        printf "  ${CYAN}orc roadmap brainstorm <projet>${NC}   Dialogue + recherche + génération de 10-15 tickets\n"
        echo ""
        printf "  Pipeline :\n"
        printf "    ${DIM}Phase 1${NC} — Vision : dialogue avec l'humain sur la direction\n"
        printf "    ${DIM}Phase 2${NC} — Recherche : audit MVP, concurrence, tendances\n"
        printf "    ${DIM}Phase 3${NC} — Sélection : l'humain choisit parmi les propositions\n"
        printf "    ${DIM}Phase 4${NC} — Rédaction : tickets détaillés écrits\n"
        printf "    ${DIM}Phase 5${NC} — Validation : confirmation finale\n"
        echo ""
        return 0
        ;;
      *)
        if [ -z "$name" ]; then
          name="$1"; shift
        else
          die "Argument inattendu : $1"
        fi
        ;;
    esac
  done

  # Inférer le projet si non spécifié
  if [ -z "$name" ]; then
    name=$(infer_project_from_cwd 2>/dev/null) || die "Usage : orc roadmap brainstorm <projet>"
  fi
  require_project "$name"

  local dir
  dir=$(project_dir "$name")
  kanban_init "$dir"

  echo ""
  printf "${BOLD}Brainstorm — %s${NC}\n" "$name"
  printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
  printf "${DIM}Pipeline : Vision → Recherche → Propositions → Sélection → Rédaction${NC}\n"

  # --- Collecter le contexte projet ---
  local brief_content="" index_content="" done_content=""
  [ -f "$dir/.orc/BRIEF.md" ] && brief_content=$(cat "$dir/.orc/BRIEF.md")
  [ -f "$dir/BRIEF.md" ] && [ -z "$brief_content" ] && brief_content=$(cat "$dir/BRIEF.md")
  [ -f "$dir/.orc/codebase/INDEX.md" ] && index_content=$(cat "$dir/.orc/codebase/INDEX.md")
  [ -f "$dir/DONE.md" ] && done_content=$(cat "$dir/DONE.md")

  local existing_todo="" existing_done="" existing_backlog=""
  existing_todo=$(kanban_titles_list "$dir" "todo")
  existing_done=$(kanban_titles_list "$dir" "done")
  existing_backlog=$(kanban_titles_list "$dir" "backlog")

  # --- Phase 1 : Vision (dialogue interactif) ---
  printf "\n${BOLD}Phase 1 — Vision${NC} ${DIM}(partagez votre vision pour la suite)${NC}\n\n"

  local vision_prompt
  vision_prompt="Tu es un product strategist expérimenté. Le projet '$name' a un MVP fonctionnel et l'humain veut planifier la prochaine itération.

BRIEF PRODUIT :
${brief_content:-[Brief non disponible]}

$([ -n "$done_content" ] && echo "STATUT : Le projet a été marqué comme terminé (DONE.md existe).
$done_content" || echo "STATUT : Le projet est en cours de développement.")

TICKETS TERMINÉS :
${existing_done:-[Aucun]}

TICKETS EN ATTENTE :
${existing_todo:-[Aucun]}

BACKLOG :
${existing_backlog:-[Aucun]}

$([ -n "$index_content" ] && echo "ARCHITECTURE DU CODE :
$index_content")

TON RÔLE — Phase Vision :
Tu vas avoir un dialogue avec l'humain pour comprendre sa vision. Pose ces questions une par une (pas toutes d'un coup) :

1. Quelles sont tes frustrations avec le produit actuel ? Qu'est-ce qui manque le plus ?
2. Quelle est ta vision pour la V2 ? Quel niveau veux-tu atteindre ?
3. Y a-t-il des features spécifiques que tu veux absolument ?
4. Quel est ton budget/temps pour cette itération ? (nombre de features)
5. Y a-t-il des contraintes techniques ou métier à respecter ?

Quand tu as assez d'informations, RÉSUME la conversation en directives claires.

IMPORTANT : Écris ton résumé dans $dir/.orc/logs/brainstorm-vision.md avec :
- Les frustrations identifiées
- La vision V2
- Les features demandées explicitement
- Les contraintes
- Le budget/scope souhaité
Puis dis à l'humain que tu passes à la phase recherche."

  local vision_file="$dir/.orc/logs/brainstorm-vision.md"

  ( cd "$dir" && claude --max-turns 12 \
    --model "${CLAUDE_MODEL:-claude-sonnet-4-6}" \
    -- "$vision_prompt" ) || true

  local vision_summary=""
  if [ -f "$vision_file" ] && [ -s "$vision_file" ]; then
    vision_summary=$(cat "$vision_file")
  else
    # Fallback : demander directement
    echo ""
    read -rp "  Décrivez votre vision en quelques phrases : " manual_vision
    vision_summary="Vision de l'humain : $manual_vision"
  fi

  [ -z "$vision_summary" ] && die "Phase vision interrompue."

  # --- Phase 2 : Recherche + Analyse + Propositions ---
  printf "\n${BOLD}Phase 2 — Recherche et propositions${NC} ${DIM}(audit, concurrence, tendances...)${NC}\n"

  local next_id
  next_id=$(kanban_next_id "$dir")

  local research_prompt_file="$ORC_DIR/phases/brainstorm-research.md"
  local research_prompt=""

  if [ -f "$research_prompt_file" ]; then
    research_prompt=$(cat "$research_prompt_file")
    research_prompt="${research_prompt//\{\{PROJECT_NAME\}\}/$name}"
    research_prompt="${research_prompt//\{\{VISION_SUMMARY\}\}/$vision_summary}"
    research_prompt="${research_prompt//\{\{BRIEF\}\}/${brief_content:-[Brief non disponible]}}"
    research_prompt="${research_prompt//\{\{INDEX\}\}/${index_content:-[Index non disponible]}}"
    research_prompt="${research_prompt//\{\{DONE\}\}/${done_content:-[Projet en cours]}}"
    research_prompt="${research_prompt//\{\{TODO_TICKETS\}\}/${existing_todo:-[Aucun]}}"
    research_prompt="${research_prompt//\{\{DONE_TICKETS\}\}/${existing_done:-[Aucun]}}"
    research_prompt="${research_prompt//\{\{BACKLOG_TICKETS\}\}/${existing_backlog:-[Aucun]}}"
    research_prompt="${research_prompt//\{\{PROJECT_DIR\}\}/$dir}"
  else
    die "Prompt brainstorm-research.md non trouvé dans $ORC_DIR/phases/"
  fi

  local proposals_file="$dir/.orc/logs/brainstorm-proposals-$(date '+%Y%m%d-%H%M%S').md"

  ( cd "$dir" && claude -p "$research_prompt" \
    --max-turns 20 \
    --model "${CLAUDE_MODEL_STRONG:-${CLAUDE_MODEL:-claude-sonnet-4-6}}" \
    --allowedTools "Read,Write,WebSearch,WebFetch,Bash" ) 2>/dev/null || {
    die "Erreur lors de la phase recherche."
  }

  # --- Phase 3 : Sélection interactive ---
  printf "\n${BOLD}Phase 3 — Sélection${NC} ${DIM}(choisissez les tickets à garder)${NC}\n\n"

  # Lire les propositions générées
  local proposals_content=""
  if [ -f "$proposals_file" ]; then
    proposals_content=$(cat "$proposals_file")
  else
    # Chercher le fichier le plus récent
    local latest_proposals
    latest_proposals=$(ls -t "$dir/.orc/logs"/brainstorm-proposals-*.md 2>/dev/null | head -1)
    [ -f "$latest_proposals" ] && proposals_content=$(cat "$latest_proposals")
  fi

  local selection_prompt="Tu es un product strategist. L'humain va sélectionner les tickets parmi les propositions du brainstorm.

PROPOSITIONS :
${proposals_content:-[Les propositions ont été générées. Lis le fichier le plus récent dans $dir/.orc/logs/brainstorm-proposals-*.md]}

TICKETS EXISTANTS (pour éviter les doublons) :
TODO : ${existing_todo:-[Aucun]}
DONE : ${existing_done:-[Aucun]}

DIALOGUE AVEC L'HUMAIN :
- Présente les propositions de manière claire (tableau ou liste numérotée)
- L'humain peut dire : \"je veux le 1, 3, 5\", \"pas le 4\", \"fusionne 2 et 7\", \"ajoute aussi X\", \"change la priorité de Y\"
- Itère jusqu'à avoir 10-15 tickets validés
- Quand l'humain dit \"ok\", \"c'est bon\", ou \"valide\" :
  Écris la liste finale des tickets sélectionnés dans $dir/.orc/logs/brainstorm-selection.md
  Puis dis à l'humain que tu passes à la rédaction."

  local selection_file="$dir/.orc/logs/brainstorm-selection.md"

  ( cd "$dir" && claude --max-turns 15 \
    --model "${CLAUDE_MODEL:-claude-sonnet-4-6}" \
    -- "$selection_prompt" ) || true

  local selection_summary=""
  if [ -f "$selection_file" ] && [ -s "$selection_file" ]; then
    selection_summary=$(cat "$selection_file")
  elif [ -n "$proposals_content" ]; then
    # Fallback : si pas de fichier de sélection, utiliser toutes les propositions
    selection_summary="$proposals_content"
    printf "${YELLOW}Pas de fichier de sélection — toutes les propositions seront rédigées.${NC}\n"
  fi

  [ -z "$selection_summary" ] && die "Phase sélection interrompue."

  # --- Phase 4 : Rédaction des tickets ---
  printf "\n${BOLD}Phase 4 — Rédaction des tickets${NC} ${DIM}(écriture des fichiers détaillés...)${NC}\n"

  local write_prompt_file="$ORC_DIR/phases/brainstorm-write.md"
  local write_prompt=""

  if [ -f "$write_prompt_file" ]; then
    write_prompt=$(cat "$write_prompt_file")
    write_prompt="${write_prompt//\{\{PROJECT_NAME\}\}/$name}"
    write_prompt="${write_prompt//\{\{SELECTION_SUMMARY\}\}/$selection_summary}"
    write_prompt="${write_prompt//\{\{PROPOSALS\}\}/${proposals_content:-[Lis $dir/.orc/logs/brainstorm-proposals-*.md]}}"
    write_prompt="${write_prompt//\{\{BRIEF\}\}/${brief_content:-[Brief non disponible]}}"
    write_prompt="${write_prompt//\{\{NEXT_ID\}\}/$next_id}"
    write_prompt="${write_prompt//\{\{PROJECT_DIR\}\}/$dir}"
  else
    die "Prompt brainstorm-write.md non trouvé dans $ORC_DIR/phases/"
  fi

  ( cd "$dir" && claude -p "$write_prompt" \
    --max-turns 20 \
    --model "${CLAUDE_MODEL:-claude-sonnet-4-6}" \
    --allowedTools "Read,Write,Bash" ) 2>/dev/null || {
    die "Erreur lors de la rédaction des tickets."
  }

  # --- Phase 5 : Validation finale ---
  printf "\n${BOLD}Phase 5 — Validation${NC}\n"
  printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
  echo ""

  # Compter les tickets créés
  local new_tickets=0
  for f in "$dir/.orc/roadmap/todo"/*.md; do
    [ -f "$f" ] || continue
    local tid
    tid=$(kanban_id "$f")
    [ "$tid" -ge "$next_id" ] 2>/dev/null && new_tickets=$((new_tickets + 1))
  done

  if [ "$new_tickets" -eq 0 ]; then
    printf "${YELLOW}Aucun ticket créé. Vérifiez les logs.${NC}\n"
    return 1
  fi

  # Afficher le résumé
  printf "  ${GREEN}%s tickets créés :${NC}\n\n" "$new_tickets"

  for f in "$dir/.orc/roadmap/todo"/*.md; do
    [ -f "$f" ] || continue
    local tid
    tid=$(kanban_id "$f")
    [ "$tid" -ge "$next_id" ] 2>/dev/null || continue
    local t_title t_prio t_type t_effort
    t_title=$(kanban_title "$f")
    t_prio=$(kanban_priority "$f")
    t_type=$(kanban_type "$f")
    t_effort=$(kanban_effort "$f")
    printf "  ${CYAN}#%s${NC} [%s] %s — ${DIM}%s %s${NC}\n" "$tid" "$t_prio" "$t_title" "$t_type" "$t_effort"
  done

  echo ""
  printf "  ${BOLD}Confirmer ?${NC} [O/n/annuler] "
  read -rp "" confirm
  case "${confirm:-O}" in
    [Oo]|[Yy]|"")
      printf "\n${GREEN}Tickets confirmés.${NC}\n"
      ;;
    *)
      # Supprimer les tickets créés
      for f in "$dir/.orc/roadmap/todo"/*.md; do
        [ -f "$f" ] || continue
        local tid
        tid=$(kanban_id "$f")
        [ "$tid" -ge "$next_id" ] 2>/dev/null && rm -f "$f"
      done
      printf "\n${RED}Tickets supprimés.${NC}\n"
      return 0
      ;;
  esac

  # Régénérer la vue
  kanban_regenerate_view "$dir"

  # Archiver DONE.md si projet terminé
  if _is_project_done "$dir"; then
    _resume_from_done "$dir" "$name"
  fi

  # Proposer de lancer
  _propose_start "$name" "$dir" "$new_tickets"
}

# ============================================================
# AFFICHAGE KANBAN PROJET
# ============================================================

# Affiche le kanban d'un projet (remplace cmd_project_roadmap pour les projets migrés)
kanban_display() {
  local dir="$1" name="$2"
  local verbosity="${3:-compact}"

  local count_todo count_done count_inprogress count_backlog
  count_todo=$(kanban_count "$dir" "todo")
  count_done=$(kanban_count "$dir" "done")
  count_inprogress=$(kanban_count "$dir" "in-progress")
  count_backlog=$(kanban_count "$dir" "backlog")
  local count_total=$((count_todo + count_done + count_inprogress + count_backlog))

  echo ""
  printf "${BOLD}ROADMAP — %s${NC}" "$name"
  printf "         ${GREEN}%s faites${NC} | ${CYAN}%s a faire${NC}" "$count_done" "$count_todo"
  [ "$count_inprogress" -gt 0 ] && printf " | ${YELLOW}%s en cours${NC}" "$count_inprogress"
  [ "$count_backlog" -gt 0 ] && printf " | ${DIM}%s backlog${NC}" "$count_backlog"
  echo ""
  printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"

  # In-progress
  local has_section=false
  for f in "$dir/.orc/roadmap/in-progress"/*.md; do
    [ -f "$f" ] || continue
    if [ "$has_section" = false ]; then
      printf "\n ${YELLOW}${BOLD}En cours${NC}\n"
      has_section=true
    fi
    _kanban_display_ticket "$f" "$verbosity"
  done

  # Todo
  has_section=false
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    if [ "$has_section" = false ]; then
      printf "\n ${CYAN}${BOLD}A faire${NC}\n"
      has_section=true
    fi
    _kanban_display_ticket "$f" "$verbosity"
  done < <(kanban_list_sorted "$dir" "todo")

  # Done
  has_section=false
  for f in "$dir/.orc/roadmap/done"/*.md; do
    [ -f "$f" ] || continue
    if [ "$has_section" = false ]; then
      printf "\n ${GREEN}${BOLD}Termine${NC} ${DIM}(%s)${NC}\n" "$count_done"
      has_section=true
    fi
    local t_id t_title
    t_id=$(basename "$f" | grep -o '^[0-9]*' || echo "?")
    t_title=$(kanban_title "$f")
    printf "  ${DIM}%s %s${NC}\n" "$t_id" "$t_title"
  done

  # Backlog
  has_section=false
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    if [ "$has_section" = false ]; then
      printf "\n ${DIM}${BOLD}Backlog${NC} ${DIM}(%s)${NC}\n" "$count_backlog"
      has_section=true
    fi
    _kanban_display_ticket "$f" "$verbosity"
  done < <(kanban_list_sorted "$dir" "backlog")

  echo ""
  printf "${DIM}Dossier : %s/.orc/roadmap/${NC}\n\n" "$dir"
}

# Affiche un ticket individuel selon le niveau de verbosité
_kanban_display_ticket() {
  local file="$1" verbosity="${2:-compact}"
  local t_id t_title t_prio t_type t_effort t_epic

  t_id=$(basename "$file" | grep -o '^[0-9]*' || echo "?")
  t_title=$(kanban_title "$file")
  t_prio=$(kanban_priority "$file")
  t_type=$(kanban_type "$file")
  t_effort=$(kanban_effort "$file")

  # Couleur de priorité
  local prio_color="$NC"
  case "$t_prio" in
    P0) prio_color="$RED" ;;
    P1) prio_color="$YELLOW" ;;
    P2) prio_color="$CYAN" ;;
    P3) prio_color="$DIM" ;;
  esac

  printf "  ${prio_color}%s${NC} %-40s ${prio_color}[%s]${NC} ${DIM}%s %s${NC}\n" \
    "$t_id" "$t_title" "$t_prio" "$t_type" "$t_effort"

  if [ "$verbosity" = "detail" ] || [ "$verbosity" = "full" ]; then
    # Afficher la section Contexte
    local context
    context=$(awk '/^## Contexte/,/^## [^C]/' "$file" 2>/dev/null | sed '1d;$d' | head -3)
    [ -n "$context" ] && printf "     ${DIM}%s${NC}\n" "$context"
  fi

  if [ "$verbosity" = "full" ]; then
    # Afficher les critères de validation
    local criteria
    criteria=$(awk '/^## Crit/,/^## [^C]/' "$file" 2>/dev/null | sed '1d;$d' | head -5)
    [ -n "$criteria" ] && while IFS= read -r cline; do
      printf "     ${DIM}%s${NC}\n" "$cline"
    done <<< "$criteria"
  fi
}

# ============================================================
# COMMANDE : orc roadmap review <projet>
# ============================================================

cmd_roadmap_review() {
  local name=""

  while [ $# -gt 0 ]; do
    case "$1" in
      -h|--help)
        echo ""
        printf "${BOLD}orc roadmap review${NC} — Reviewer les tickets ajoutés par l'IA\n\n"
        printf "  ${CYAN}orc roadmap review <projet>${NC}   Affiche les tickets récents (auto-brainstorm, evolve)\n"
        printf "                                 Permet de valider, éditer, supprimer, rejeter\n"
        echo ""
        return 0
        ;;
      *)
        if [ -z "$name" ]; then
          name="$1"; shift
        else
          die "Argument inattendu : $1"
        fi
        ;;
    esac
  done

  if [ -z "$name" ]; then
    name=$(infer_project_from_cwd 2>/dev/null) || die "Usage : orc roadmap review <projet>"
  fi
  require_project "$name"

  local dir
  dir=$(project_dir "$name")

  local todo_dir="$dir/.orc/roadmap/todo"
  if [ ! -d "$todo_dir" ]; then
    printf "${DIM}Aucun ticket dans le kanban.${NC}\n"
    return 0
  fi

  # Collecter les tickets ajoutés par l'IA (source: auto-brainstorm, evolve, brainstorm)
  local ai_tickets=()
  local human_tickets=()
  for f in "$todo_dir"/*.md; do
    [ -f "$f" ] || continue
    local src
    src=$(kanban_field "$f" "source")
    case "$src" in
      auto-brainstorm|evolve|brainstorm|strategy)
        ai_tickets+=("$f")
        ;;
      *)
        human_tickets+=("$f")
        ;;
    esac
  done

  echo ""
  printf "${BOLD}REVIEW ROADMAP — %s${NC}\n" "$name"
  printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"

  if [ ${#ai_tickets[@]} -eq 0 ]; then
    printf "\n${DIM}  Aucun ticket IA à reviewer dans todo/.${NC}\n\n"
    return 0
  fi

  # Afficher les tickets IA
  printf "\n ${CYAN}${BOLD}Tickets IA a reviewer${NC} ${DIM}(%s tickets)${NC}\n\n" "${#ai_tickets[@]}"

  local idx=0
  for f in "${ai_tickets[@]}"; do
    idx=$((idx + 1))
    local t_id t_title t_prio t_type t_effort t_src t_epic
    t_id=$(basename "$f" | grep -o '^[0-9]*' || echo "?")
    t_title=$(kanban_title "$f")
    t_prio=$(kanban_priority "$f")
    t_type=$(kanban_type "$f")
    t_effort=$(kanban_effort "$f")
    t_src=$(kanban_field "$f" "source")
    t_epic=$(kanban_field "$f" "epic")

    local prio_color="$NC"
    case "$t_prio" in
      P0) prio_color="$RED" ;; P1) prio_color="$YELLOW" ;; P2) prio_color="$CYAN" ;; P3) prio_color="$DIM" ;;
    esac

    printf "  ${BOLD}%2d${NC}) ${prio_color}%s${NC} %-38s ${prio_color}[%s]${NC} ${DIM}%s %s${NC} ${DIM}(%s)${NC}\n" \
      "$idx" "$t_id" "$t_title" "$t_prio" "$t_type" "$t_effort" "$t_src"
  done

  # Stats
  local epic_list=""
  local type_counts=""
  for f in "${ai_tickets[@]}"; do
    epic_list="$epic_list$(kanban_field "$f" "epic")
"
    type_counts="$type_counts$(kanban_type "$f")
"
  done
  local unique_epics
  unique_epics=$(echo "$epic_list" | sort -u | grep -c '.' || echo 0)
  printf "\n  ${DIM}%s epics, %s tickets${NC}\n" "$unique_epics" "${#ai_tickets[@]}"

  if [ ${#human_tickets[@]} -gt 0 ]; then
    printf "\n ${GREEN}${BOLD}Tickets humains${NC} ${DIM}(%s — non concernés par la review)${NC}\n" "${#human_tickets[@]}"
  fi

  # Actions
  echo ""
  printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
  printf "  ${CYAN}v${NC})alider tout   ${CYAN}e${NC})diter N   ${CYAN}d${NC})upprimer N   ${RED}r${NC})ejeter tout   ${DIM}q${NC})uitter\n"
  echo ""

  while true; do
    read -rp "  Action : " action

    case "$action" in
      v|V|"")
        printf "\n${GREEN}Tous les tickets validés — ils seront implémentés au prochain run.${NC}\n\n"
        return 0
        ;;
      e|E|e\ *|E\ *)
        local edit_num
        edit_num=$(echo "$action" | grep -o '[0-9]*')
        if [ -n "$edit_num" ] && [ "$edit_num" -ge 1 ] && [ "$edit_num" -le "${#ai_tickets[@]}" ]; then
          local edit_file="${ai_tickets[$((edit_num - 1))]}"
          local editor="${EDITOR:-vi}"
          "$editor" "$edit_file"
          printf "${GREEN}Ticket mis à jour.${NC}\n"
        else
          printf "${RED}Numéro invalide (1-%s)${NC}\n" "${#ai_tickets[@]}"
        fi
        ;;
      d|D|d\ *|D\ *)
        local del_num
        del_num=$(echo "$action" | grep -o '[0-9]*')
        if [ -n "$del_num" ] && [ "$del_num" -ge 1 ] && [ "$del_num" -le "${#ai_tickets[@]}" ]; then
          local del_file="${ai_tickets[$((del_num - 1))]}"
          local del_title
          del_title=$(kanban_title "$del_file")
          rm -f "$del_file"
          printf "${RED}Supprimé : %s${NC}\n" "$del_title"
          # Recalculer
          unset 'ai_tickets[$((del_num - 1))]'
          ai_tickets=("${ai_tickets[@]}")
        else
          printf "${RED}Numéro invalide (1-%s)${NC}\n" "${#ai_tickets[@]}"
        fi
        ;;
      r|R)
        printf "\n${RED}Suppression de tous les tickets IA...${NC}\n"
        for f in "${ai_tickets[@]}"; do
          [ -f "$f" ] && rm -f "$f"
        done
        kanban_regenerate_view "$dir"
        printf "${RED}%s tickets supprimés.${NC}\n\n" "${#ai_tickets[@]}"
        return 0
        ;;
      q|Q)
        printf "\n${DIM}Tickets inchangés.${NC}\n\n"
        return 0
        ;;
      *)
        printf "${DIM}Commandes : v(alider) e(diter) N d(upprimer) N r(ejeter) q(uitter)${NC}\n"
        ;;
    esac
  done
}
