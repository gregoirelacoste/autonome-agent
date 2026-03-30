#!/bin/bash
# ============================================================
# orc-agent.sh — Gestion des projets (sourcé par orc.sh)
# ============================================================
#
# Fonctions : cmd_new, cmd_start, cmd_stop, cmd_restart,
#             cmd_status, cmd_logs, cmd_roadmap, cmd_chat, cmd_watch
#
# Variables attendues de orc.sh :
#   ORC_DIR, PROJECTS_DIR (via env ou défaut),
#   RED, GREEN, YELLOW, BLUE, CYAN, BOLD, DIM, NC, die()
# ============================================================

PROJECTS_DIR="${PROJECTS_DIR:-$HOME/projects}"

# ============================================================
# UTILITAIRES
# ============================================================

project_dir() {
  echo "$PROJECTS_DIR/$1"
}

require_project() {
  local name="$1"
  local dir
  dir=$(project_dir "$name")
  [ -d "$dir" ] || die "Projet '$name' non trouvé. Voir : orc agent status"
}

# Infère le nom du projet depuis le répertoire courant
# Retourne le nom si cwd == $PROJECTS_DIR/<nom>, sinon retourne 1
infer_project_from_cwd() {
  local cwd pdir
  cwd=$(realpath "$(pwd)" 2>/dev/null) || return 1
  pdir=$(realpath "$PROJECTS_DIR" 2>/dev/null) || return 1
  [ "$(dirname "$cwd")" = "$pdir" ] || return 1
  basename "$cwd"
}

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
    rm -f "$pidfile"
  fi
  return 1
}

# ============================================================
# STATUT DU RUN
# ============================================================

# Détermine le statut d'un projet : running, completed, crashed, stopped
# Retourne : status_label status_color
get_run_status() {
  local name="$1"
  local dir
  dir=$(project_dir "$name")

  if is_running "$name"; then
    echo "en cours|$CYAN"
  elif [ -f "$dir/DONE.md" ]; then
    echo "terminé|$GREEN"
  elif [ -f "$dir/.orc/state.json" ] && command -v jq &>/dev/null; then
    local saved_status
    saved_status=$(jq -r '.run_status // ""' "$dir/.orc/state.json" 2>/dev/null)
    case "$saved_status" in
      completed)          echo "terminé|$GREEN" ;;
      crashed)            echo "crashé|$RED" ;;
      stopped)            echo "arrêté|$YELLOW" ;;
      budget_exceeded)    echo "budget dépassé|$RED" ;;
      alignment_pending)  echo "alignement requis|$BLUE" ;;
      *)                  echo "arrêté|$YELLOW" ;;
    esac
  else
    echo "arrêté|$YELLOW"
  fi
}

# ============================================================
# GITHUB : création repo
# ============================================================

setup_github_repo() {
  local name="$1"
  local visibility="${2:-private}"
  local dir
  dir=$(project_dir "$name")
  command -v gh &>/dev/null || die "GitHub CLI (gh) non installé. Installer : https://cli.github.com"
  [ -d "$dir/.git" ] || die "Git non initialisé dans $dir"

  if git -C "$dir" remote get-url origin &>/dev/null 2>&1; then
    die "Remote 'origin' existe déjà : $(git -C "$dir" remote get-url origin)"
  fi

  # Commit initial si aucun commit
  if ! git -C "$dir" rev-parse HEAD &>/dev/null 2>&1; then
    git -C "$dir" add -A > /dev/null 2>&1 || true
    git -C "$dir" commit -m "chore: initial project structure" --allow-empty > /dev/null 2>&1 || true
  fi

  local description=""
  [ -f "$dir/BRIEF.md" ] && description=$(head -1 "$dir/BRIEF.md" | sed 's/^#[[:space:]]*//')

  local gh_output
  if ! gh_output=$(gh repo create "$name" \
    --"$visibility" \
    --source="$dir" \
    --push \
    --description "${description:-Projet $name}" 2>&1); then
    die "gh repo create a échoué :\n  $gh_output"
  fi

  local repo_url
  repo_url=$(echo "$gh_output" | head -1)
  printf "  ${GREEN}✓${NC} Repo GitHub créé : ${CYAN}%s${NC}\n" "${repo_url:-erreur}"
}

cmd_github() {
  local name="${1:-}"
  [ -z "$name" ] && die "Usage : orc agent github <nom> [--public]"
  require_project "$name"
  shift

  local visibility="private"
  while [ $# -gt 0 ]; do
    case "$1" in
      --public)  visibility="public"; shift ;;
      --private) visibility="private"; shift ;;
      *) die "Option inconnue : $1" ;;
    esac
  done

  printf "${BOLD}Création du repo GitHub pour '%s' (%s)...${NC}\n\n" "$name" "$visibility"
  setup_github_repo "$name" "$visibility"
}

# ============================================================
# ENV : configuration des variables d'environnement
# ============================================================

cmd_env() {
  local name="${1:-}"
  [ -z "$name" ] && die "Usage : orc agent env <nom>"
  require_project "$name"

  local dir
  dir=$(project_dir "$name")

  # Chercher le fichier template (.env.example, .env.template, .env.sample)
  local env_template=""
  for candidate in ".env.example" ".env.template" ".env.sample"; do
    if [ -f "$dir/$candidate" ]; then
      env_template="$dir/$candidate"
      break
    fi
  done

  if [ -z "$env_template" ]; then
    die "Aucun fichier .env.example trouvé dans $dir"
  fi

  local env_file="$dir/.env.local"

  # Header
  echo ""
  if [ -f "$env_file" ] && ! grep -q 'your_' "$env_file" 2>/dev/null; then
    printf "${BOLD}Variables d'environnement de '%s'${NC}\n" "$name"
    printf "${DIM}Appuie sur Entrée pour garder la valeur actuelle.${NC}\n"
  else
    printf "${BOLD}Configuration des variables d'environnement de '%s'${NC}\n" "$name"
    printf "${DIM}Colle les valeurs depuis ton dashboard. Entrée = passer.${NC}\n"
  fi

  local tmp_env
  tmp_env=$(mktemp)

  while IFS= read -r line; do
    # Lignes vides : recopier
    if [[ -z "$line" ]]; then
      echo "" >> "$tmp_env"
      continue
    fi

    # Commentaires : afficher comme section + aide contextuelle
    if [[ "$line" =~ ^[[:space:]]*# ]]; then
      echo "$line" >> "$tmp_env"
      local section="${line#\#}"
      section="${section# }"
      echo ""
      printf "  ${BOLD}── %s ──${NC}\n" "$section"
      # Aide contextuelle pour les services connus
      _env_hint "$section"
      continue
    fi

    local key value current_value
    key="${line%%=*}"
    value="${line#*=}"
    key=$(echo "$key" | xargs)  # trim

    [ -z "$key" ] && continue

    # Chercher la valeur actuelle dans .env.local
    current_value=""
    if [ -f "$env_file" ]; then
      current_value=$(grep "^${key}=" "$env_file" 2>/dev/null | head -1 | cut -d= -f2- || true)
    fi

    # Afficher le prompt
    if [ -n "$current_value" ] && [[ ! "$current_value" =~ ^your_ ]]; then
      local display_val
      if [[ "$key" =~ KEY|SECRET|TOKEN|PASSWORD ]]; then
        if [ ${#current_value} -gt 8 ]; then
          display_val="***${current_value: -4}"
        else
          display_val="***"
        fi
      else
        display_val="$current_value"
      fi
      printf "  ${CYAN}%-40s${NC} ${DIM}[%s]${NC} : " "$key" "$display_val"
    else
      printf "  ${CYAN}%-40s${NC} : " "$key"
    fi

    local input
    read -r input < /dev/tty

    # Priorité : input > existant > template
    if [ -n "$input" ]; then
      echo "$key=$input" >> "$tmp_env"
    elif [ -n "$current_value" ] && [[ ! "$current_value" =~ ^your_ ]]; then
      echo "$key=$current_value" >> "$tmp_env"
    elif [[ ! "$value" =~ ^your_ ]] && [ -n "$value" ]; then
      echo "$key=$value" >> "$tmp_env"
    else
      echo "$key=" >> "$tmp_env"
    fi
  done < "$env_template"

  # Écrire le fichier final
  mv "$tmp_env" "$env_file"
  chmod 600 "$env_file"

  local final_count empty_count
  final_count=$(grep -c '=' "$env_file" 2>/dev/null || true)
  empty_count=$(grep -c '=$' "$env_file" 2>/dev/null || true)

  echo ""
  printf "  ${GREEN}✓${NC} .env.local écrit (%s variables" "$final_count"
  if [ "$empty_count" -gt 0 ]; then
    printf ", ${YELLOW}%s vides${NC}" "$empty_count"
  fi
  printf ")\n"
  printf "  ${DIM}Fichier : %s (chmod 600)${NC}\n" "$env_file"

  # Effacer action-required si présent
  rm -f "$dir/.orc/action-required"
  echo ""
}

# Aide contextuelle pour les services courants
_env_hint() {
  local section="$1"
  case "${section,,}" in
    *supabase*)
      printf "  ${DIM}→ Dashboard : https://supabase.com/dashboard/project/_/settings/api${NC}\n" ;;
    *openai*)
      printf "  ${DIM}→ API keys : https://platform.openai.com/api-keys${NC}\n" ;;
    *stripe*)
      printf "  ${DIM}→ API keys : https://dashboard.stripe.com/apikeys${NC}\n" ;;
    *firebase*|*google*|*gemini*)
      printf "  ${DIM}→ Console : https://console.cloud.google.com/apis/credentials${NC}\n" ;;
    *github*)
      printf "  ${DIM}→ Tokens : https://github.com/settings/tokens${NC}\n" ;;
    *resend*)
      printf "  ${DIM}→ API keys : https://resend.com/api-keys${NC}\n" ;;
    *cloudflare*|*turnstile*)
      printf "  ${DIM}→ Dashboard : https://dash.cloudflare.com/?to=/:account/turnstile${NC}\n" ;;
    *anthropic*|*claude*)
      printf "  ${DIM}→ API keys : https://console.anthropic.com/settings/keys${NC}\n" ;;
    *vercel*)
      printf "  ${DIM}→ Settings : https://vercel.com/account/tokens${NC}\n" ;;
    *aws*|*s3*)
      printf "  ${DIM}→ Console : https://console.aws.amazon.com/iam/home#/security_credentials${NC}\n" ;;
    *database*|*postgres*|*mysql*)
      printf "  ${DIM}→ Connection string depuis ton provider (Supabase, Neon, PlanetScale...)${NC}\n" ;;
    *redis*)
      printf "  ${DIM}→ Dashboard : https://app.redislabs.com/ ou Upstash${NC}\n" ;;
    *api*|*ia*|*ai*)
      printf "  ${DIM}→ Clés API depuis le dashboard de chaque provider${NC}\n" ;;
  esac
}

# Vérifie les env vars avant le start (appelé par cmd_start)
preflight_env() {
  local dir="$1" name="$2"

  # Chercher un fichier template
  local env_template=""
  for candidate in ".env.example" ".env.template" ".env.sample"; do
    if [ -f "$dir/$candidate" ]; then
      env_template="$dir/$candidate"
      break
    fi
  done
  [ -z "$env_template" ] && return 0

  # Si .env.local existe et n'a pas de placeholder, OK
  if [ -f "$dir/.env.local" ] && ! grep -q 'your_' "$dir/.env.local" 2>/dev/null; then
    return 0
  fi

  # Si .env existe et n'a pas de placeholder, OK
  if [ -f "$dir/.env" ] && ! grep -q 'your_' "$dir/.env" 2>/dev/null; then
    return 0
  fi

  echo ""
  printf "${YELLOW}Variables d'environnement non configurées${NC}\n"
  printf "  Fichier ${CYAN}%s${NC} détecté mais pas de .env.local\n\n" "$(basename "$env_template")"
  printf "  Configurer maintenant ? [O/n] : "
  read -r choice
  choice="${choice:-O}"

  if [[ "$choice" =~ ^[OoYy]$ ]]; then
    cmd_env "$name"
  else
    printf "\n  ${DIM}Tu peux configurer plus tard : orc agent env %s${NC}\n\n" "$name"
  fi
}

# ============================================================
# COMMANDE : new
# ============================================================

cmd_new() {
  local name="${1:-}"
  [ -z "$name" ] && die "Usage : orc agent new <nom> [--brief briefs/x.md] [--no-clarify] [--github [public]]"

  local dir
  dir=$(project_dir "$name")
  shift
  local brief_file=""
  local no_clarify=false
  local github_enabled=false
  local github_visibility="private"
  while [ $# -gt 0 ]; do
    case "$1" in
      --brief)
        brief_file="${2:-}"
        [ -z "$brief_file" ] && die "--brief nécessite un chemin de fichier"
        shift 2
        ;;
      --no-clarify)
        no_clarify=true
        shift
        ;;
      --github)
        github_enabled=true
        if [ -n "${2:-}" ] && [[ "${2:-}" =~ ^(public|private)$ ]]; then
          github_visibility="$2"
          shift
        fi
        shift
        ;;
      *) die "Option inconnue : $1" ;;
    esac
  done

  # Reprise : si le dossier existe mais pas de BRIEF.md, on reprend
  local resume=false
  if [ -d "$dir" ]; then
    if [ -f "$dir/BRIEF.md" ]; then
      die "Le projet '$name' existe déjà avec un brief ($dir)"
    else
      printf "${YELLOW}Workspace incomplet détecté — reprise...${NC}\n\n"
      resume=true
    fi
  fi

  printf "${BOLD}Création du projet '%s'...${NC}\n\n" "$name"

  # Création/réparation du workspace (idempotent)
  mkdir -p "$dir"
  ln -sf "$ORC_DIR/orchestrator.sh" "$dir/orchestrator.sh"
  ln -sf "$ORC_DIR/phases" "$dir/phases"
  cp "$ORC_DIR/BRIEF.template.md" "$dir/"
  mkdir -p "$dir/.orc/logs" \
           "$dir/.orc/research/competitors" \
           "$dir/.orc/research/trends" \
           "$dir/.orc/research/user-needs" \
           "$dir/.orc/research/regulations"
  [ -f "$dir/.orc/config.sh" ] || cp "$ORC_DIR/config.default.sh" "$dir/.orc/config.sh"

  [ -d "$dir/.git" ] || ( cd "$dir" && git init -b main > /dev/null 2>&1 )

  # .gitignore (symlinks + state runtime)
  if [ ! -f "$dir/.gitignore" ]; then
    cat > "$dir/.gitignore" << 'GITIGNORE'
# Symlinks vers le template orc
orchestrator.sh
phases

# État runtime orchestrateur
.orc/logs/
.orc/state.json
.orc/tokens.json
.orc/.lock
.orc/.pid
.orc/.watch-pid
.orc/tracking-issue
GITIGNORE
  fi

  mkdir -p "$dir/.claude/skills"
  cp "$ORC_DIR/skills-templates/"*.md "$dir/.claude/skills/"

  if [ "$resume" = true ]; then
    printf "  ${GREEN}✓${NC} Workspace réparé : %s\n" "$dir"
  else
    printf "  ${GREEN}✓${NC} Workspace créé : %s\n" "$dir"
  fi

  if [ -n "$brief_file" ]; then
    local resolved_brief=""
    if [ -f "$brief_file" ]; then
      resolved_brief="$brief_file"
    elif [ -f "$ORC_DIR/$brief_file" ]; then
      resolved_brief="$ORC_DIR/$brief_file"
    else
      die "Brief non trouvé : $brief_file"
    fi

    cp "$resolved_brief" "$dir/BRIEF.md"
    printf "  ${GREEN}✓${NC} Brief copié depuis %s\n" "$brief_file"

    if [ "$no_clarify" = false ]; then
      printf "\n  ${CYAN}Claude va analyser le brief et poser des questions pour le clarifier...${NC}\n\n"

      local clarify_skill
      clarify_skill=$(cat "$ORC_DIR/skills-templates/clarify-brief.md")

      ( cd "$dir" && claude --max-turns 40 -- "$clarify_skill

---

Le projet s'appelle \"$name\".
Le brief existant est dans BRIEF.md — lis-le et commence ton analyse.
Pose des questions pour clarifier les zones floues, puis enrichis le brief." )

      if [ -f "$dir/BRIEF.md" ]; then
        printf "\n  ${GREEN}✓${NC} Brief clarifié et enrichi\n"
      else
        printf "\n  ${YELLOW}⚠${NC} Brief non mis à jour. Le brief original est conservé.\n"
      fi
    fi

    cp "$dir/BRIEF.md" "$dir/.orc/BRIEF.md"
  else
    printf "\n  ${CYAN}Claude va te poser des questions pour rédiger le brief...${NC}\n\n"

    local brief_skill
    brief_skill=$(cat "$ORC_DIR/skills-templates/write-brief.md")

    ( cd "$dir" && claude --max-turns 40 -- "$brief_skill

---

L'utilisateur crée un projet appelé \"$name\".
Pose les questions une par une. Écris le résultat dans BRIEF.md." )

    if [ -f "$dir/BRIEF.md" ]; then
      cp "$dir/BRIEF.md" "$dir/.orc/BRIEF.md"
      printf "\n  ${GREEN}✓${NC} Brief rédigé\n"
    else
      printf "\n  ${YELLOW}⚠${NC} Brief non créé. Rédige-le manuellement :\n"
      printf "    ${CYAN}vim %s/BRIEF.md${NC}\n" "$dir"
    fi
  fi

  # GitHub repo
  if [ "$github_enabled" = true ]; then
    echo ""
    setup_github_repo "$name" "$github_visibility"
  fi

  echo ""
  printf "${GREEN}Projet '%s' prêt.${NC}\n" "$name"
  printf "  Lancer : ${CYAN}orc agent start %s${NC}\n" "$name"
  printf "  Config : ${CYAN}vim %s/.orc/config.sh${NC}\n" "$dir"
  echo ""
}

# ============================================================
# COMMANDE : start
# ============================================================

cmd_start() {
  local name="${1:-}"
  if [ -n "$name" ] && [ "${name#-}" = "$name" ]; then shift
  else name=$(infer_project_from_cwd) || die "Usage : orc agent start <nom> [--prompt \"directive\"]"
  fi
  require_project "$name"

  # Parse options
  local user_prompt=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --prompt|-p)
        user_prompt="${2:-}"
        [ -z "$user_prompt" ] && die "--prompt nécessite un texte"
        shift 2
        ;;
      *) die "Option inconnue : $1" ;;
    esac
  done

  local dir
  dir=$(project_dir "$name")

  if is_running "$name"; then
    local pid
    pid=$(cat "$dir/.orc/.pid")
    die "Déjà en cours (PID $pid). Voir : orc logs $name"
  fi

  [ -f "$dir/BRIEF.md" ] || die "Pas de BRIEF.md dans $dir. Crée-le d'abord."

  export ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY:-}"
  export GEMINI_API_KEY="${GEMINI_API_KEY:-}"

  # L'API key n'est pas requise si Claude Code CLI est authentifié (OAuth/login)
  if [ -z "$ANTHROPIC_API_KEY" ] && ! command -v claude &> /dev/null; then
    die "Claude Code CLI non trouvé et ANTHROPIC_API_KEY non configurée. Installer claude ou configurer la clé : orc admin key"
  fi

  # Injecter le modèle si configuré globalement
  local model_file="$ORC_DIR/.model"
  if [ -f "$model_file" ]; then
    export CLAUDE_MODEL
    CLAUDE_MODEL=$(cat "$model_file")
  fi

  # Injecter le prompt dans human-notes.md
  if [ -n "$user_prompt" ]; then
    local notes_file="$dir/.orc/human-notes.md"
    {
      [ -f "$notes_file" ] && [ -s "$notes_file" ] && echo ""
      echo "## Directive de lancement ($(date '+%Y-%m-%d %H:%M'))"
      echo ""
      echo "$user_prompt"
    } >> "$notes_file"
    printf "${DIM}Directive injectée dans .orc/human-notes.md${NC}\n"
  fi

  # Vérifier les variables d'environnement
  preflight_env "$dir" "$name"

  mkdir -p "$dir/.orc/logs"
  nohup bash -c "cd \"$dir\" && exec ./orchestrator.sh" >> "$dir/.orc/logs/orchestrator.log" 2>&1 &
  local pid=$!
  echo "$pid" > "$dir/.orc/.pid"

  printf "${GREEN}Projet '%s' lancé${NC} (PID %s)\n" "$name" "$pid"
  printf "  Logs   : ${CYAN}orc logs %s${NC}\n" "$name"
  printf "  Status : ${CYAN}orc s %s${NC}\n" "$name"
  printf "  Stop   : ${CYAN}orc agent stop %s${NC}\n" "$name"
}

# ============================================================
# COMMANDE : stop
# ============================================================

cmd_stop() {
  local name="${1:-}"
  if [ -z "$name" ]; then
    name=$(infer_project_from_cwd) || die "Usage : orc agent stop <nom>"
  fi
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

  kill "$pid" 2>/dev/null || true

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
  if [ -z "$name" ]; then
    name=$(infer_project_from_cwd) || die "Usage : orc agent restart <nom>"
  fi
  cmd_stop "$name"
  sleep 1
  cmd_start "$name"
}

# ============================================================
# UTILITAIRES AFFICHAGE
# ============================================================

# Longueur visible d'une string (sans ANSI escape codes, ajuste pour emojis 2-wide)
visible_len() {
  local stripped
  stripped=$(printf '%s' "$1" | sed 's/\x1b\[[0-9;]*m//g')
  # Compter les caractères multi-width courants (emojis) — approximation simple
  local emoji_count
  emoji_count=$(printf '%s' "$stripped" | grep -oP '[\x{1F300}-\x{1F9FF}]|✅|🔄|✓|✗' 2>/dev/null | wc -l || echo "0")
  echo $(( ${#stripped} + emoji_count ))
}

# Dessine une barre de progression : progress_bar <current> <total> <width>
progress_bar() {
  local current="${1:-0}" total="${2:-1}" width="${3:-30}"
  [ "$total" -eq 0 ] && total=1
  local pct=$((current * 100 / total))
  [ $pct -gt 100 ] && pct=100
  local filled=$((pct * width / 100))
  local empty=$((width - filled))
  local bar=""
  local i
  for ((i=0; i<filled; i++)); do bar+="█"; done
  for ((i=0; i<empty; i++)); do bar+="░"; done

  local color="$CYAN"
  [ $pct -ge 50 ] && color="$YELLOW"
  [ $pct -ge 80 ] && color="$GREEN"
  printf "${color}%s${NC} %3d%%" "$bar" "$pct"
}

# Calcule la durée écoulée en format lisible depuis un timestamp ISO
format_duration_since() {
  local start_ts="$1"
  local start_epoch end_epoch
  start_epoch=$(date -d "$start_ts" +%s 2>/dev/null || echo "0")
  end_epoch=$(date +%s)
  [ "$start_epoch" -eq 0 ] && echo "—" && return
  local diff=$((end_epoch - start_epoch))
  local hours=$((diff / 3600))
  local minutes=$(( (diff % 3600) / 60 ))
  if [ $hours -gt 0 ]; then
    printf "%dh%02dm" "$hours" "$minutes"
  else
    printf "%dm" "$minutes"
  fi
}

# Formate un nombre de tokens en lisible (1234567 → "1.23M", 45678 → "45.7K")
format_tokens() {
  local raw="${1:-0}"
  # Normalise : virgule → point, tronque les décimaux pour avoir un entier
  raw="${raw//,/.}"
  local n="${raw%%.*}"
  n="${n:-0}"
  if [ "$n" -ge 1000000 ]; then
    # Calcul en awk pour éviter les problèmes de locale avec printf/bc
    awk "BEGIN { printf \"%.2fM\", $n / 1000000 }"
  elif [ "$n" -ge 1000 ]; then
    awk "BEGIN { printf \"%.1fK\", $n / 1000 }"
  else
    printf "%d" "$n"
  fi
}

# Formate une durée entre deux timestamps ISO en format lisible
format_duration_between() {
  local start_ts="$1" end_ts="$2"
  local start_epoch end_epoch
  start_epoch=$(date -d "$start_ts" +%s 2>/dev/null || echo "0")
  end_epoch=$(date -d "$end_ts" +%s 2>/dev/null || echo "0")
  [ "$start_epoch" -eq 0 ] || [ "$end_epoch" -eq 0 ] && echo "—" && return
  local diff=$((end_epoch - start_epoch))
  local hours=$((diff / 3600))
  local minutes=$(( (diff % 3600) / 60 ))
  local seconds=$((diff % 60))
  if [ $hours -gt 0 ]; then
    printf "%dh%02dm%02ds" "$hours" "$minutes" "$seconds"
  elif [ $minutes -gt 0 ]; then
    printf "%dm%02ds" "$minutes" "$seconds"
  else
    printf "%ds" "$seconds"
  fi
}

# Raccourcit un nom de modèle pour l'affichage (claude-opus-4-6 → opus-4.6)
short_model_name() {
  local model="$1"
  model="${model#claude-}"      # Supprime le préfixe claude-
  # Convertit le dernier tiret en point pour la version (opus-4-6 → opus-4.6)
  if [[ "$model" =~ ^([a-z]+)-([0-9]+)-([0-9]+) ]]; then
    echo "${BASH_REMATCH[1]}-${BASH_REMATCH[2]}.${BASH_REMATCH[3]}"
  else
    echo "$model"
  fi
}

# Estime le temps restant basé sur la durée moyenne par feature
estimate_remaining() {
  local dir="$1"
  local state_file="$dir/.orc/state.json"
  [ -f "$state_file" ] || return
  if ! command -v jq &> /dev/null; then return; fi

  local feat_count timeline_len run_started
  feat_count=$(jq -r '.feature_count // 0' "$state_file")
  run_started=$(jq -r '.run_started_at // ""' "$state_file")
  timeline_len=$(jq -r '.features_timeline | length' "$state_file" 2>/dev/null || echo "0")

  [ "$feat_count" -eq 0 ] && return
  [ -z "$run_started" ] && return

  local start_epoch now_epoch
  start_epoch=$(date -d "$run_started" +%s 2>/dev/null || echo "0")
  now_epoch=$(date +%s)
  [ "$start_epoch" -eq 0 ] && return

  local elapsed=$((now_epoch - start_epoch))
  local avg_per_feature=$((elapsed / feat_count))

  # Compter les features restantes dans la roadmap
  local roadmap="$dir/.orc/ROADMAP.md"
  [ -f "$roadmap" ] || return
  local remaining
  remaining=$(grep -c '^\- \[ \]' "$roadmap" 2>/dev/null || true)
  [ "$remaining" -eq 0 ] && return

  local eta_s=$((avg_per_feature * remaining))
  local eta_h=$((eta_s / 3600))
  local eta_m=$(( (eta_s % 3600) / 60 ))

  if [ $eta_h -gt 0 ]; then
    printf "~%dh%02dm" "$eta_h" "$eta_m"
  else
    printf "~%dm" "$eta_m"
  fi
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

  mkdir -p "$PROJECTS_DIR"

  local has_projects=false

  printf "\n${BOLD}%-20s %-10s %-12s %-8s %-10s %-14s %s${NC}\n" \
    "PROJET" "STATUS" "FEATURES" "ÉCHECS" "COÛT" "PROGRESSION" "ROADMAP"
  printf "%-20s %-10s %-12s %-8s %-10s %-14s %s\n" \
    "────────────────────" "──────────" "────────────" "────────" "──────────" "──────────────" "──────────"

  for proj_dir in "$PROJECTS_DIR"/*/; do
    [ -d "$proj_dir" ] || continue
    has_projects=true

    local proj_name
    proj_name=$(basename "$proj_dir")

    local status status_color run_info
    run_info=$(get_run_status "$proj_name")
    status="${run_info%%|*}"
    status_color="${run_info##*|}"

    local feat_count="0" max_feat="?" failures="0"
    if [ -f "$proj_dir/.orc/state.json" ]; then
      feat_count=$(jq -r '.feature_count // 0' "$proj_dir/.orc/state.json" 2>/dev/null || echo "0")
      failures=$(jq -r '.total_failures // 0' "$proj_dir/.orc/state.json" 2>/dev/null || echo "0")
    fi
    if [ -f "$proj_dir/.orc/config.sh" ]; then
      max_feat=$(grep -oP 'MAX_FEATURES=\K\d+' "$proj_dir/.orc/config.sh" 2>/dev/null || echo "?")
    fi

    local cost="\$0.00"
    if [ -f "$proj_dir/.orc/tokens.json" ]; then
      local raw_cost
      raw_cost=$(jq -r '.total_cost_usd // 0' "$proj_dir/.orc/tokens.json" 2>/dev/null || echo "0")
      cost="\$$raw_cost"
    fi

    local remaining="—" pct_str="—"
    if [ -f "$proj_dir/.orc/ROADMAP.md" ]; then
      local done_count todo
      done_count=$(grep -c '^\- \[x\]' "$proj_dir/.orc/ROADMAP.md" 2>/dev/null || true)
      todo=$(grep -c '^\- \[ \]' "$proj_dir/.orc/ROADMAP.md" 2>/dev/null || true)
      local total_feats=$((done_count + todo))
      if [ "$todo" -eq 0 ] && [ "$status" = "done" ]; then
        remaining="terminé"
        pct_str="${GREEN}100%${NC}"
      elif [ "$total_feats" -gt 0 ]; then
        local pct=$((done_count * 100 / total_feats))
        remaining="${todo} restantes"
        local pct_color="$CYAN"
        [ $pct -ge 50 ] && pct_color="$YELLOW"
        [ $pct -ge 80 ] && pct_color="$GREEN"
        pct_str="${pct_color}${pct}%${NC}"
      fi
    fi

    printf "%-20s ${status_color}%-10s${NC} %-12s %-8s %-10s " \
      "$proj_name" "$status" "${feat_count}/${max_feat}" "$failures" "$cost"
    printf "${pct_str}%-8s %s\n" "" "$remaining"
  done

  if [ "$has_projects" = false ]; then
    printf "\n  ${DIM}Aucun projet. Créer : ${CYAN}orc agent new mon-projet${NC}\n"
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

  # Status + durée
  local is_done=false
  local run_info status_label status_color
  run_info=$(get_run_status "$name")
  status_label="${run_info%%|*}"
  status_color="${run_info##*|}"

  if [ -f "$dir/DONE.md" ]; then
    is_done=true
  fi

  if is_running "$name"; then
    local pid
    pid=$(cat "$dir/.orc/.pid")
    printf "  Status : ${status_color}%s${NC} (PID %s)\n" "$status_label" "$pid"
  else
    printf "  Status : ${status_color}%s${NC}\n" "$status_label"
  fi

  # ── Session ──
  local run_started="" run_ended="" has_state=false has_tokens=false
  if [ -f "$dir/.orc/state.json" ] && command -v jq &> /dev/null; then
    has_state=true
    run_started=$(jq -r '.run_started_at // ""' "$dir/.orc/state.json" 2>/dev/null)
    run_ended=$(jq -r '.run_ended_at // ""' "$dir/.orc/state.json" 2>/dev/null)
    [ "$run_started" = "null" ] && run_started=""
    [ "$run_ended" = "null" ] && run_ended=""
  fi
  [ -f "$dir/.orc/tokens.json" ] && has_tokens=true

  echo ""
  printf "  ${BOLD}── Session ──${NC}\n"

  # Début
  if [ -n "$run_started" ]; then
    printf "  Début     %s\n" "$(date -d "$run_started" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "$run_started")"
  fi

  # Fin ou durée en cours
  if [ -n "$run_ended" ] && ! is_running "$name"; then
    printf "  Fin       %s\n" "$(date -d "$run_ended" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "$run_ended")"
    if [ -n "$run_started" ]; then
      local duration
      duration=$(format_duration_between "$run_started" "$run_ended")
      printf "  Durée     %s\n" "$duration"
    fi
  elif [ -n "$run_started" ]; then
    local duration
    duration=$(format_duration_since "$run_started")
    printf "  Durée     %s ${DIM}(en cours)${NC}\n" "$duration"
  fi

  # Features
  if [ "$has_state" = true ]; then
    local feat fail
    feat=$(jq -r '.feature_count // 0' "$dir/.orc/state.json" 2>/dev/null)
    fail=$(jq -r '.total_failures // 0' "$dir/.orc/state.json" 2>/dev/null)
    printf "  Features  %s | Échecs : %s\n" "$feat" "$fail"
  fi

  # Tokens + Coût détaillé
  if [ "$has_tokens" = true ]; then
    local cost invocations tokens_in tokens_out
    cost=$(jq -r '.total_cost_usd // 0' "$dir/.orc/tokens.json" 2>/dev/null)
    invocations=$(jq -r '.invocations // 0' "$dir/.orc/tokens.json" 2>/dev/null)
    tokens_in=$(jq -r '.total_input_tokens // 0' "$dir/.orc/tokens.json" 2>/dev/null)
    tokens_out=$(jq -r '.total_output_tokens // 0' "$dir/.orc/tokens.json" 2>/dev/null)
    local total_tokens=$((tokens_in + tokens_out))

    # Tokens
    printf "  Tokens    %s in / %s out (%s total)\n" \
      "$(format_tokens "$tokens_in")" "$(format_tokens "$tokens_out")" "$(format_tokens "$total_tokens")"

    # Coût + budget + pourcentage
    local budget_str="" cost_pct=""
    if [ -f "$dir/.orc/config.sh" ]; then
      local max_budget
      max_budget=$(grep -oP 'MAX_BUDGET_USD="\K[^"]+' "$dir/.orc/config.sh" 2>/dev/null || echo "")
      if [ -n "$max_budget" ] && [ "$max_budget" != "0" ]; then
        budget_str=" / \$$max_budget"
        local pct
        pct=$(awk "BEGIN { printf \"%.1f\", $cost * 100 / $max_budget }" 2>/dev/null || echo "")
        [ -n "$pct" ] && cost_pct=" (${pct}%)"
      fi
    fi

    # Coût par heure
    local cost_per_hour=""
    if [ -n "$run_started" ]; then
      local start_epoch now_epoch
      start_epoch=$(date -d "$run_started" +%s 2>/dev/null || echo "0")
      if [ -n "$run_ended" ] && ! is_running "$name"; then
        now_epoch=$(date -d "$run_ended" +%s 2>/dev/null || echo "0")
      else
        now_epoch=$(date +%s)
      fi
      local elapsed=$((now_epoch - start_epoch))
      if [ "$elapsed" -gt 60 ]; then
        local cph
        cph=$(awk "BEGIN { printf \"%.2f\", $cost * 3600 / $elapsed }" 2>/dev/null || echo "")
        [ -n "$cph" ] && cost_per_hour="  —  \$${cph}/h"
      fi
    fi

    printf "  Coût      \$%s%s%s%s\n" "$cost" "$budget_str" "$cost_pct" "$cost_per_hour"
    printf "  Appels    %s invocations" "$invocations"
    if [ "$invocations" -gt 0 ]; then
      local avg_cost
      avg_cost=$(awk "BEGIN { printf \"%.2f\", $cost / $invocations }" 2>/dev/null || echo "")
      [ -n "$avg_cost" ] && printf " (moy. \$%s/appel)" "$avg_cost"
    fi
    printf "\n"

    # Modèles utilisés (agrégé depuis tokens.json.by_phase.*.models_used)
    # Normalise les noms (supprime suffixes date -20XXXXXX) et filtre les vides/unknown
    local models_json
    models_json=$(jq -r '
      [.by_phase // {} | to_entries[].value.models_used // {} | to_entries[]
       | select(.key != "" and .key != "unknown" and .key != "null")
       | .key |= (gsub("-2025[0-9]+$"; "") | gsub("-2026[0-9]+$"; ""))] |
      group_by(.key) | map({key: .[0].key, value: (map(.value) | add)}) |
      sort_by(-.value) | map("\(.key):\(.value)") | join(",")
    ' "$dir/.orc/tokens.json" 2>/dev/null || echo "")
    if [ -n "$models_json" ]; then
      local models_display=""
      IFS=',' read -ra model_entries <<< "$models_json"
      for entry in "${model_entries[@]}"; do
        local mname="${entry%%:*}"
        local mcount="${entry##*:}"
        local short
        short=$(short_model_name "$mname")
        [ -n "$models_display" ] && models_display+=", "
        models_display+="${short} x${mcount}"
      done
      printf "  Modèles   %s\n" "$models_display"
    fi

    # Top 3 phases par coût
    local top_phases
    top_phases=$(jq -r '
      .by_phase // {} | to_entries |
      sort_by(-.value.cost_usd) | .[0:3] |
      map("\(.key) $\(.value.cost_usd)") | join(", ")
    ' "$dir/.orc/tokens.json" 2>/dev/null || echo "")
    if [ -n "$top_phases" ]; then
      printf "  Top coût  %s\n" "$top_phases"
    fi
  fi

  # Modèle configuré (fallback si pas de tokens.json)
  if [ "$has_tokens" != true ]; then
    local model_file="$ORC_DIR/.model"
    if [ -f "$model_file" ]; then
      printf "  Modèle    %s\n" "$(cat "$model_file")"
    fi
  fi

  # Progress bar + roadmap
  if [ -f "$dir/.orc/ROADMAP.md" ]; then
    local done_count todo total_feats
    done_count=$(grep -c '^\- \[x\]' "$dir/.orc/ROADMAP.md" 2>/dev/null || true)
    todo=$(grep -c '^\- \[ \]' "$dir/.orc/ROADMAP.md" 2>/dev/null || true)
    total_feats=$((done_count + todo))
    echo ""
    printf "  Progress  "
    progress_bar "$done_count" "$total_feats" 30
    printf " (%s/%s features)\n" "$done_count" "$total_feats"
  fi

  # Feature en cours + ETA
  if [ -f "$dir/.orc/state.json" ] && command -v jq &> /dev/null; then
    local cur_feat cur_phase
    cur_feat=$(jq -r '.current_feature // ""' "$dir/.orc/state.json" 2>/dev/null)
    cur_phase=$(jq -r '.current_phase // ""' "$dir/.orc/state.json" 2>/dev/null)
    if [ -n "$cur_feat" ] && [ "$cur_feat" != "null" ] && [ "$cur_feat" != "" ]; then
      printf "  En cours  ${CYAN}%s${NC}" "$cur_feat"
      [ -n "$cur_phase" ] && [ "$cur_phase" != "null" ] && printf " ${DIM}(%s)${NC}" "$cur_phase"
      printf "\n"
    fi

    local eta
    eta=$(estimate_remaining "$dir")
    if [ -n "$eta" ]; then
      printf "  ETA       %s restantes estimées\n" "$eta"
    fi
  fi

  # Functional check
  if [ -f "$dir/.orc/state.json" ] && command -v jq &> /dev/null; then
    local func_check
    func_check=$(jq -r '.functional_check_passed // "null"' "$dir/.orc/state.json" 2>/dev/null)
    if [ "$func_check" = "true" ]; then
      printf "  App       ${GREEN}fonctionnelle ✓${NC}\n"
    elif [ "$func_check" = "false" ]; then
      printf "  App       ${RED}non fonctionnelle ✗${NC}\n"
    fi
  fi

  # Action requise
  if [ -f "$dir/.orc/action-required" ]; then
    echo ""
    printf "  ${RED}${BOLD}── Action requise ──${NC}\n"
    sed 's/^/  /' "$dir/.orc/action-required"
  fi

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
  if [ -n "$name" ] && [ "${name#-}" = "$name" ]; then shift
  else name=$(infer_project_from_cwd) || die "Usage : orc logs <nom> [--full|--debug]"
  fi
  require_project "$name"

  local dir
  dir=$(project_dir "$name")
  local flag="${1:-}"

  if [ "$flag" = "--debug" ]; then
    # Mode debug : actions Claude en temps réel (stream-json formaté)
    local debug_log="$dir/.orc/logs/orc-debug-live.log"
    if [ ! -f "$debug_log" ]; then
      printf "Pas encore de log debug pour '%s'.\n" "$name"
      printf "Le fichier est créé au premier appel Claude (après start).\n"
      exit 0
    fi
    printf "${BOLD}Debug live — %s${NC}  ${DIM}(Ctrl+C pour quitter)${NC}\n\n" "$name"
    if command -v jq &>/dev/null; then
      # Afficher les dernières lignes déjà formatées, puis suivre en temps réel
      tail -n +1 -f "$debug_log" | jq -R --unbuffered '. as $raw |
        try fromjson catch null |
        if . == null then $raw
        elif .type == "orc_phase" then
          "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n[\(.ts)] \(.phase | ascii_upcase) \(if .feature != "" then "| \(.feature)" else "" end)\n     model=\(.model)  turns=\(.max_turns)\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        elif .type == "orc_prompt" then
          "[\(.ts)] prompt \(.chars)c → \(.preview)"
        elif .type == "assistant" then
          ([.message.content[]? |
            if .type == "tool_use" then
              "  → \(.name) \(.input | to_entries | map("\(.key)=\(.value | tostring | .[0:60])") | join(" "))"
            elif .type == "text" and (.text | gsub("^[[:space:]]+";"") | length) > 0 then
              "  💬 \(.text | gsub("^[[:space:]]+";"") | .[0:200] | gsub("\n";" "))"
            else empty end
          ] | join("\n"))
        elif .type == "result" then
          "  ✅ \(.subtype // "done") | turns=\(.num_turns // "?") | cost=$\(.total_cost_usd // "?")\n"
        else empty end
      ' 2>/dev/null
    else
      tail -n +1 -f "$debug_log"
    fi
    return
  fi

  local logfile="$dir/.orc/logs/orchestrator.log"
  [ -f "$logfile" ] || die "Pas de log trouvé pour '$name'"

  if [ "$flag" = "--full" ]; then
    less +G "$logfile"
  else
    # Afficher le contexte récent puis suivre en temps réel
    local total
    total=$(wc -l < "$logfile")
    if [ "$total" -gt 30 ]; then
      printf "${DIM}── %s dernières lignes ──${NC}\n" "30"
      tail -30 "$logfile"
      printf "${DIM}── suivi en temps réel (Ctrl+C pour quitter) ──${NC}\n\n"
    fi
    tail -f "$logfile"
  fi
}

# ============================================================
# COMMANDE : update
# ============================================================

# ============================================================
# COMMANDE : chat
# ============================================================

cmd_chat() {
  local name="${1:-}"
  if [ -n "$name" ] && [ "${name#-}" = "$name" ]; then shift
  else name=$(infer_project_from_cwd) || die "Usage : orc chat <nom> [--prompt \"directive\"]"
  fi
  require_project "$name"

  # Parse options
  local user_prompt=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --prompt|-p)
        user_prompt="${2:-}"
        [ -z "$user_prompt" ] && die "--prompt nécessite un texte"
        shift 2
        ;;
      *) die "Option inconnue : $1" ;;
    esac
  done

  local dir
  dir=$(project_dir "$name")

  command -v claude &>/dev/null || die "Claude Code CLI non installé."

  # Si --prompt : injecter dans human-notes et lancer en one-shot si le run tourne
  if [ -n "$user_prompt" ]; then
    local notes_file="$dir/.orc/human-notes.md"
    {
      [ -f "$notes_file" ] && [ -s "$notes_file" ] && echo ""
      echo "## Directive humaine ($(date '+%Y-%m-%d %H:%M'))"
      echo ""
      echo "$user_prompt"
    } >> "$notes_file"

    printf "${GREEN}✓${NC} Directive injectée dans .orc/human-notes.md\n"
    if is_running "$name"; then
      printf "${DIM}  Le run est en cours — sera lu avant la prochaine feature.${NC}\n"
    else
      printf "${DIM}  Sera lu au prochain 'orc agent start %s'.${NC}\n" "$name"
    fi
    echo ""
    return 0
  fi

  # Mode interactif : construire le contexte orc
  local context=""

  # Brief
  if [ -f "$dir/.orc/BRIEF.md" ]; then
    context="${context}
## Brief produit
$(cat "$dir/.orc/BRIEF.md")
"
  fi

  # Roadmap + progression
  if [ -f "$dir/.orc/ROADMAP.md" ]; then
    local done_count todo_count
    done_count=$(grep -c '^\- \[x\]' "$dir/.orc/ROADMAP.md" 2>/dev/null || true)
    todo_count=$(grep -c '^\- \[ \]' "$dir/.orc/ROADMAP.md" 2>/dev/null || true)
    context="${context}
## Roadmap (${done_count:-0} faites / ${todo_count:-0} restantes)
$(cat "$dir/.orc/ROADMAP.md")
"
  fi

  # État du run
  if [ -f "$dir/.orc/state.json" ] && command -v jq &>/dev/null; then
    local cur_feat cur_phase feat_count run_status workflow_phase cost
    cur_feat=$(jq -r '.current_feature // ""' "$dir/.orc/state.json" 2>/dev/null)
    cur_phase=$(jq -r '.current_phase // ""' "$dir/.orc/state.json" 2>/dev/null)
    feat_count=$(jq -r '.feature_count // 0' "$dir/.orc/state.json" 2>/dev/null)
    run_status=$(jq -r '.run_status // ""' "$dir/.orc/state.json" 2>/dev/null)
    workflow_phase=$(jq -r '.workflow_phase // ""' "$dir/.orc/state.json" 2>/dev/null)
    cost=""
    if [ -f "$dir/.orc/tokens.json" ]; then
      cost=$(jq -r '.total_cost_usd // ""' "$dir/.orc/tokens.json" 2>/dev/null)
    fi
    context="${context}
## État du run
- Status : ${run_status:-inconnu}
- Workflow : ${workflow_phase:-init}
- Features complétées : ${feat_count}
- Feature en cours : ${cur_feat:-aucune}
- Phase : ${cur_phase:-inconnue}
- Coût cumulé : \$${cost:-0}
"
  fi

  # Human notes en cours
  if [ -f "$dir/.orc/human-notes.md" ] && [ -s "$dir/.orc/human-notes.md" ]; then
    context="${context}
## Directives humaines en attente
$(cat "$dir/.orc/human-notes.md")
"
  fi

  # Action requise
  if [ -f "$dir/.orc/action-required" ]; then
    context="${context}
## ACTION REQUISE
$(cat "$dir/.orc/action-required")
"
  fi

  # Dernières réflexions de fix
  local latest_reflection
  latest_reflection=$(ls -t "$dir/.orc/logs/fix-reflections-"*.md 2>/dev/null | head -1 || true)
  if [ -n "$latest_reflection" ]; then
    context="${context}
## Dernières réflexions de fix
$(cat "$latest_reflection")
"
  fi

  local prompt_header="Tu es l'assistant du projet '${name}', orchestré par ORC.
Tu as accès au code source et au CLAUDE.md du projet (chargés automatiquement).
Voici le contexte additionnel de l'orchestrateur :
${context}
Aide l'utilisateur à comprendre l'état du projet, débugger des problèmes, ou prendre des décisions techniques.
Si l'utilisateur veut injecter une directive pour le prochain run, écris-la dans .orc/human-notes.md."

  printf "${BOLD}orc chat${NC} — %s\n" "$name"
  printf "${DIM}Contexte : brief, roadmap, état du run, directives, réflexions.${NC}\n\n"

  cd "$dir" && claude --append-system-prompt "$prompt_header"
}

# ============================================================
# COMMANDE : roadmap
# ============================================================

# Parse le frontmatter YAML d'un fichier roadmap item
parse_frontmatter() {
  local file="$1"
  local field="$2"
  awk -v field="$field" '
    /^---$/ { block++; next }
    block == 1 {
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

priority_color() {
  case "$1" in
    P0) printf "${RED}" ;;
    P1) printf "${YELLOW}" ;;
    P2) printf "${BLUE}" ;;
    P3) printf "${DIM}" ;;
    *)  printf "${NC}" ;;
  esac
}

status_symbol() {
  case "$1" in
    in-progress) printf "${CYAN}●${NC}" ;;
    planned)     printf "○" ;;
    backlog)     printf "${DIM}◌${NC}" ;;
    done)        printf "${GREEN}✓${NC}" ;;
    *)           printf "?" ;;
  esac
}

sort_items() {
  sort -t'|' -k1,1 -k2,2r
}

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
  # Si le premier arg est un nom de projet existant → roadmap projet
  if [ -n "${1:-}" ] && [ "${1#-}" = "$1" ] && [ -d "$(project_dir "$1")" ]; then
    cmd_project_roadmap "$@"
    return
  fi

  # Sinon : roadmap orc (template)
  local verbosity="compact"
  local filter_priority="" filter_tag="" filter_epic="" filter_type="" filter_status=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --detail)    verbosity="detail"; shift ;;
      --full)      verbosity="full"; shift ;;
      --priority)  filter_priority="${2:-}"; shift 2 ;;
      --tag)       filter_tag="${2:-}"; shift 2 ;;
      --epic)      filter_epic="${2:-}"; shift 2 ;;
      --type)      filter_type="${2:-}"; shift 2 ;;
      --status)    filter_status="${2:-}"; shift 2 ;;
      -h|--help)   orc_help; return ;;
      *) die "Option inconnue : $1. Voir : orc roadmap --help" ;;
    esac
  done

  local roadmap_dir="$ORC_DIR/roadmap"
  [ -d "$roadmap_dir" ] || die "Dossier roadmap/ non trouvé dans $ORC_DIR"

  local count_p0=0 count_p1=0 count_p2=0 count_p3=0 count_total=0

  local items_data=""
  for status_dir in in-progress planned backlog done; do
    local dir="$roadmap_dir/$status_dir"
    [ -d "$dir" ] || continue

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

      case "$item_priority" in
        P0) count_p0=$((count_p0 + 1)) ;;
        P1) count_p1=$((count_p1 + 1)) ;;
        P2) count_p2=$((count_p2 + 1)) ;;
        P3) count_p3=$((count_p3 + 1)) ;;
      esac
      count_total=$((count_total + 1))

      local ekey
      ekey=$(effort_sort_key "$item_effort")
      items_data+="${item_priority}|${ekey}|${status_dir}|${item_file}|${item_id}|${item_title}|${item_priority}|${item_type}|${item_effort}|${item_tags}|${item_epic}"$'\n'
    done
  done

  if [ "$count_total" -eq 0 ]; then
    printf "\n${DIM}Aucun item dans la roadmap.${NC}\n\n"
    return
  fi

  echo ""
  printf "${BOLD}ROADMAP — orc${NC}"
  printf "         ${RED}P0: %d${NC} | ${YELLOW}P1: %d${NC} | ${BLUE}P2: %d${NC} | ${DIM}P3: %d${NC}\n" \
    "$count_p0" "$count_p1" "$count_p2" "$count_p3"
  printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"

  local sorted_items
  sorted_items=$(echo "$items_data" | grep -v '^$' | sort_items)

  local current_status=""
  while IFS='|' read -r _prio _ekey status filepath item_id item_title priority item_type effort tags epic; do
    [ -z "$status" ] && continue

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

    local sym pcolor
    sym=$(status_symbol "$status")
    pcolor=$(priority_color "$priority")

    printf "  %b ${pcolor}%-12s${NC} [%s/%s] %-42s ${DIM}%s${NC}\n" \
      "$sym" "$item_id" "$priority" "$effort" "$item_title" "$tags"

    if [ "$verbosity" = "detail" ] || [ "$verbosity" = "full" ]; then
      local context
      context=$(extract_section "$filepath" "Contexte" 3)
      if [ -n "$context" ]; then
        echo "$context" | while IFS= read -r line; do
          printf "    ${DIM}%s${NC}\n" "$line"
        done
      fi

      local deps
      deps=$(parse_depends "$filepath")
      if [ -n "$deps" ] && [ "$deps" != "[]" ]; then
        printf "    ${DIM}Dépend de : %s${NC}\n" "$deps"
      fi

      if [ -n "$epic" ] && [ "$epic" != '""' ]; then
        printf "    ${DIM}Epic : %s${NC}\n" "$epic"
      fi

      local created updated
      created=$(parse_frontmatter "$filepath" "created")
      updated=$(parse_frontmatter "$filepath" "updated")
      if [ -n "$created" ]; then
        printf "    ${DIM}Créé : %s | MàJ : %s${NC}\n" "$created" "${updated:-$created}"
      fi
      echo ""
    fi

    if [ "$verbosity" = "full" ]; then
      local spec
      spec=$(extract_section "$filepath" "Spécification")
      if [ -n "$spec" ]; then
        printf "    ${BOLD}Spécification :${NC}\n"
        echo "$spec" | while IFS= read -r line; do
          printf "    %s\n" "$line"
        done
        echo ""
      fi

      local criteria
      criteria=$(extract_section "$filepath" "Critères de validation")
      if [ -n "$criteria" ]; then
        printf "    ${BOLD}Critères :${NC}\n"
        echo "$criteria" | while IFS= read -r line; do
          printf "    %s\n" "$line"
        done
        echo ""
      fi

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

# ============================================================
# COMMANDE : roadmap projet
# ============================================================

cmd_project_roadmap() {
  local name="${1:-}"
  local verbosity="compact"
  shift || true

  [ -z "$name" ] && die "Usage : orc roadmap <projet> [--detail|--full]"
  require_project "$name"

  # Parser les options
  while [ $# -gt 0 ]; do
    case "$1" in
      --detail) verbosity="detail"; shift ;;
      --full)   verbosity="full"; shift ;;
      *) shift ;;
    esac
  done

  local dir
  dir=$(project_dir "$name")

  # Kanban ? Si le dossier .orc/roadmap/ contient des tickets
  local has_kanban_tickets=false
  for _kdir in "$dir/.orc/roadmap"/*/; do
    [ -d "$_kdir" ] || continue
    for _kf in "$_kdir"*.md; do
      [ -f "$_kf" ] && { has_kanban_tickets=true; break 2; }
    done
  done
  if [ "$has_kanban_tickets" = true ]; then
    kanban_display "$dir" "$name" "$verbosity"
    return
  fi

  # Fallback : affichage legacy (ROADMAP.md plat)
  local roadmap_file="$dir/.orc/ROADMAP.md"

  if [ ! -f "$roadmap_file" ]; then
    die "Pas de ROADMAP.md pour '$name' (le projet n'a peut-etre pas encore demarre)"
  fi

  local done_count todo_count
  done_count=$(grep -c '^\- \[x\]' "$roadmap_file" 2>/dev/null || true)
  todo_count=$(grep -c '^\- \[ \]' "$roadmap_file" 2>/dev/null || true)

  echo ""
  printf "${BOLD}ROADMAP — %s${NC}" "$name"
  printf "         ${GREEN}%s faites${NC} | ${CYAN}%s restantes${NC}\n" "$done_count" "$todo_count"
  printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
  echo ""

  while IFS= read -r line; do
    if [[ "$line" =~ ^-\ \[x\] ]]; then
      printf "  ${GREEN}%s${NC}\n" "$line"
    elif [[ "$line" =~ ^-\ \[\ \] ]]; then
      printf "  ${CYAN}%s${NC}\n" "$line"
    elif [[ "$line" =~ ^## ]]; then
      printf "\n ${BOLD}%s${NC}\n" "$line"
    elif [[ "$line" =~ ^# ]]; then
      : # skip title, we have our own header
    elif [ -n "$line" ]; then
      printf "  %s\n" "$line"
    fi
  done < "$roadmap_file"

  echo ""
  printf "${DIM}Fichier : %s${NC}\n\n" "$roadmap_file"
}

# ============================================================
# COMMANDE : adopt (adopter un projet existant)
# ============================================================

cmd_adopt() {
  local source_dir="${1:-}"
  [ -z "$source_dir" ] && die "Usage : orc agent adopt <chemin-du-projet> [--name nom]"

  # Résoudre le chemin absolu
  source_dir=$(realpath "$source_dir" 2>/dev/null || echo "$source_dir")
  [ -d "$source_dir" ] || die "Dossier non trouvé : $source_dir"

  shift
  local name=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --name) [ -z "${2:-}" ] && die "--name requiert une valeur"; name="$2"; shift 2 ;;
      *) die "Option inconnue : $1" ;;
    esac
  done

  # Déduire le nom depuis le dossier si pas fourni
  [ -z "$name" ] && name=$(basename "$source_dir")

  local dir
  dir=$(project_dir "$name")

  printf "${BOLD}Adoption du projet '%s' depuis %s${NC}\n\n" "$name" "$source_dir"

  # Si le projet est déjà dans PROJECTS_DIR, travailler sur place
  # Sinon, copier/déplacer vers PROJECTS_DIR
  if [ "$source_dir" != "$dir" ]; then
    if [ -d "$dir" ]; then
      die "Le projet '$name' existe déjà dans $PROJECTS_DIR"
    fi
    # Copier le projet dans PROJECTS_DIR (exclut les dossiers volumineux)
    if command -v rsync &>/dev/null; then
      rsync -a --exclude='node_modules' --exclude='.git' --exclude='venv' \
        --exclude='__pycache__' --exclude='target' --exclude='.next' \
        --exclude='dist' --exclude='build' "$source_dir/" "$dir/"
    else
      cp -r "$source_dir" "$dir"
    fi
    printf "  ${GREEN}✓${NC} Projet copié dans %s\n" "$dir"
  fi

  # Créer la structure .orc/ sans toucher au code existant
  mkdir -p "$dir/.orc/logs" \
           "$dir/.orc/research/competitors" \
           "$dir/.orc/research/trends" \
           "$dir/.orc/research/user-needs" \
           "$dir/.orc/research/regulations" \
           "$dir/.orc/codebase"

  # Symlinks vers le template orc
  ln -sf "$ORC_DIR/orchestrator.sh" "$dir/orchestrator.sh"
  ln -sf "$ORC_DIR/phases" "$dir/phases"

  # Config
  [ -f "$dir/.orc/config.sh" ] || cp "$ORC_DIR/config.default.sh" "$dir/.orc/config.sh"
  # sed -i portable (GNU vs BSD)
  if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' "s/^PROJECT_NAME=\"\"/PROJECT_NAME=\"$name\"/" "$dir/.orc/config.sh" 2>/dev/null || true
  else
    sed -i "s/^PROJECT_NAME=\"\"/PROJECT_NAME=\"$name\"/" "$dir/.orc/config.sh" 2>/dev/null || true
  fi

  # Skills
  mkdir -p "$dir/.claude/skills"
  cp -n "$ORC_DIR/skills-templates/"*.md "$dir/.claude/skills/" 2>/dev/null || true

  # Git init si pas déjà fait
  [ -d "$dir/.git" ] || ( cd "$dir" && git init -b main > /dev/null 2>&1 )

  # .gitignore (ajout des entrées orc si absent)
  if ! grep -q "orchestrator.sh" "$dir/.gitignore" 2>/dev/null; then
    {
      echo ""
      echo "# ORC orchestrateur"
      echo "orchestrator.sh"
      echo "phases"
      echo ".orc/logs/"
      echo ".orc/state.json"
      echo ".orc/tokens.json"
      echo ".orc/.lock"
      echo ".orc/.pid"
      echo ".orc/.watch-pid"
    } >> "$dir/.gitignore"
  fi

  printf "  ${GREEN}✓${NC} Structure .orc/ créée\n"

  # Demander à Claude d'analyser le code existant et générer la connaissance projet
  printf "\n  ${CYAN}Claude analyse le code existant...${NC}\n\n"

  if ( cd "$dir" && claude -p "Tu adoptes un projet EXISTANT. Du code est déjà présent.

1. Analyse tout le code source du projet (ls, read les fichiers clés)
2. Identifie : la stack, la structure, les commandes (build, test, dev, lint)
3. Crée CLAUDE.md avec l'architecture, les conventions, les commandes
4. Crée .orc/codebase/INDEX.md (carte sémantique, max 40 lignes)
5. Crée les fichiers de détail : .orc/codebase/modules.md, utilities.md, architecture.md
6. Crée .claude/skills/stack-conventions.md avec les conventions détectées
7. Détecte les commandes build/test/dev/lint et mets-les dans .orc/config.sh :
   - Remplace BUILD_COMMAND, TEST_COMMAND, DEV_COMMAND, LINT_COMMAND
8. Si un .env.example existe, note les variables requises

NE MODIFIE PAS le code existant. Uniquement créer la connaissance projet.
Commite : 'chore: adopt project with ORC'" \
    --dangerously-skip-permissions \
    --max-turns 20 \
    --output-format stream-json > /dev/null 2>&1 ); then
    printf "  ${GREEN}✓${NC} Projet analysé et connaissance générée\n"
  else
    printf "  ${YELLOW}⚠${NC} L'analyse automatique a échoué. Relancez avec : orc agent start %s\n" "$name"
  fi

  # Générer un brief depuis le code existant
  if [ ! -f "$dir/BRIEF.md" ] && [ ! -f "$dir/.orc/BRIEF.md" ]; then
    printf "\n  ${CYAN}Génération du brief depuis le code...${NC}\n\n"
    if ( cd "$dir" && claude -p "Lis CLAUDE.md et le code source. Génère un BRIEF.md qui décrit :
- Le problème que ce projet résout
- Les utilisateurs cibles
- Les fonctionnalités existantes
- Ce qui reste à faire (si détectable)

Format : utilise le template standard de brief ORC. Sois concis." \
      --dangerously-skip-permissions \
      --max-turns 10 \
      --output-format stream-json > /dev/null 2>&1 ); then
      [ -f "$dir/BRIEF.md" ] && cp "$dir/BRIEF.md" "$dir/.orc/BRIEF.md"
      printf "  ${GREEN}✓${NC} Brief généré\n"
    else
      printf "  ${YELLOW}⚠${NC} Génération du brief échouée. Créez BRIEF.md manuellement.\n"
    fi
  fi

  printf "\n${GREEN}Projet '%s' adopté !${NC}\n" "$name"
  printf "  Démarrer : ${CYAN}orc agent start %s${NC}\n" "$name"
  printf "  Config   : ${CYAN}vim %s/.orc/config.sh${NC}\n" "$dir"
  printf "  Status   : ${CYAN}orc agent status %s${NC}\n\n" "$name"
}

cmd_agent_help() {
  echo ""
  printf "${BOLD}orc agent — Gestion des projets${NC}\n"
  echo ""
  printf "  ${CYAN}orc agent new <nom>${NC}               Créer un projet\n"
  printf "  ${CYAN}orc agent new <nom> --brief x.md${NC}  Avec un brief existant\n"
  printf "  ${CYAN}orc agent start <nom>${NC}             Lancer en background\n"
  printf "  ${CYAN}orc agent stop <nom>${NC}              Arrêter proprement\n"
  printf "  ${CYAN}orc agent restart <nom>${NC}           Redémarrer\n"
  printf "  ${CYAN}orc agent status${NC}                  Vue d'ensemble (avec progression)\n"
  printf "  ${CYAN}orc agent status <nom>${NC}            Détail + barre de progression\n"
  printf "  ${CYAN}orc agent dashboard <nom>${NC}         Dashboard live (rafraîchit toutes les 5s)\n"
  printf "  ${CYAN}orc agent logs <nom>${NC}              Logs temps réel (orchestrateur)\n"
  printf "  ${CYAN}orc agent logs <nom> --full${NC}       Log complet\n"
  printf "  ${CYAN}orc agent logs <nom> --debug${NC}      Actions Claude en temps réel\n"
  printf "  ${CYAN}orc agent adopt <dossier>${NC}         Adopter un projet existant\n"
  printf "  ${CYAN}orc agent update${NC}                  Mettre à jour le template\n"
  echo ""
}

# ============================================================
# COMMANDE : dashboard (live monitoring)
# ============================================================

cmd_dashboard() {
  local name="${1:-}"
  if [ -z "$name" ]; then
    name=$(infer_project_from_cwd) || die "Usage : orc dashboard <nom>"
  fi
  require_project "$name"

  local dir
  dir=$(project_dir "$name")
  local state_file="$dir/.orc/state.json"
  local tokens_file="$dir/.orc/tokens.json"
  local roadmap_file="$dir/.orc/ROADMAP.md"
  local logfile="$dir/.orc/logs/orchestrator.log"
  local config_file="$dir/.orc/config.sh"

  local refresh=5
  if [ "${2:-}" = "--refresh" ] && [ -n "${3:-}" ]; then
    refresh="$3"
  fi

  printf "${DIM}Dashboard live — rafraîchissement toutes les %ss (Ctrl+C pour quitter)${NC}\n" "$refresh"
  sleep 1

  while true; do
    clear

    # === HEADER ===
    local status status_color run_info
    run_info=$(get_run_status "$name")
    status="${run_info%%|*}"
    status_color="${run_info##*|}"

    local duration="—"
    if [ -f "$state_file" ] && command -v jq &> /dev/null; then
      local run_started
      run_started=$(jq -r '.run_started_at // ""' "$state_file" 2>/dev/null)
      if [ -n "$run_started" ] && [ "$run_started" != "null" ]; then
        duration=$(format_duration_since "$run_started")
      fi
    fi

    printf "${BOLD}╔══════════════════════════════════════════════════════════════╗${NC}\n"
    printf "${BOLD}║${NC}  ${BOLD}ORC — %s${NC}" "$name"
    # Padding to align right
    local header_left="ORC — $name"
    local header_right="$status | $duration"
    local pad=$((56 - ${#header_left} - ${#header_right}))
    [ $pad -lt 1 ] && pad=1
    printf "%*s" "$pad" ""
    printf "${status_color}%s${NC} | ${CYAN}%s${NC}" "$status" "$duration"
    printf "  ${BOLD}║${NC}\n"
    printf "${BOLD}╠══════════════════════════════════════════════════════════════╣${NC}\n"

    # === PROGRESS + METRICS ===
    local feat_count=0 total_failures=0 max_feat="?"
    if [ -f "$state_file" ] && command -v jq &> /dev/null; then
      feat_count=$(jq -r '.feature_count // 0' "$state_file" 2>/dev/null)
      total_failures=$(jq -r '.total_failures // 0' "$state_file" 2>/dev/null)
    fi
    if [ -f "$config_file" ]; then
      max_feat=$(grep -oP 'MAX_FEATURES=\K\d+' "$config_file" 2>/dev/null || echo "?")
    fi

    local cost="\$0.00" budget_str=""
    if [ -f "$tokens_file" ] && command -v jq &> /dev/null; then
      local raw_cost
      raw_cost=$(jq -r '.total_cost_usd // 0' "$tokens_file" 2>/dev/null)
      cost="\$$raw_cost"
    fi
    if [ -f "$config_file" ]; then
      local max_budget
      max_budget=$(grep -oP 'MAX_BUDGET_USD="\K[^"]+' "$config_file" 2>/dev/null || echo "")
      [ -n "$max_budget" ] && budget_str=" / \$$max_budget"
    fi

    local done_count=0 todo_count=0 total_feats=0
    if [ -f "$roadmap_file" ]; then
      done_count=$(grep -c '^\- \[x\]' "$roadmap_file" 2>/dev/null || true)
      todo_count=$(grep -c '^\- \[ \]' "$roadmap_file" 2>/dev/null || true)
      total_feats=$((done_count + todo_count))
    fi

    # Progress bar
    printf "${BOLD}║${NC}  Progress  "
    progress_bar "$done_count" "$total_feats" 30
    printf " (%s/%s)" "$done_count" "$total_feats"
    local pbar_pad=$((10 - ${#done_count} - ${#total_feats}))
    [ $pbar_pad -lt 0 ] && pbar_pad=0
    printf "%*s${BOLD}║${NC}\n" "$pbar_pad" ""

    # Workflow phase
    local workflow_phase=""
    if [ -f "$state_file" ] && command -v jq &> /dev/null; then
      workflow_phase=$(jq -r '.workflow_phase // ""' "$state_file" 2>/dev/null)
    fi
    if [ -n "$workflow_phase" ] && [ "$workflow_phase" != "null" ] && [ "$workflow_phase" != "init" ]; then
      printf "${BOLD}║${NC}  Workflow   ${BLUE}%s${NC}" "$workflow_phase"
      local wf_pad=$((49 - ${#workflow_phase}))
      [ $wf_pad -lt 0 ] && wf_pad=0
      printf "%*s${BOLD}║${NC}\n" "$wf_pad" ""
    fi

    # Current feature
    local cur_feat="" cur_phase=""
    if [ -f "$state_file" ] && command -v jq &> /dev/null; then
      cur_feat=$(jq -r '.current_feature // ""' "$state_file" 2>/dev/null)
      cur_phase=$(jq -r '.current_phase // ""' "$state_file" 2>/dev/null)
    fi
    if [ -n "$cur_feat" ] && [ "$cur_feat" != "null" ] && [ "$cur_feat" != "" ]; then
      local phase_str=""
      [ -n "$cur_phase" ] && [ "$cur_phase" != "null" ] && phase_str=" ($cur_phase)"
      local feat_display="${cur_feat}${phase_str}"
      # Tronquer si trop long
      [ ${#feat_display} -gt 50 ] && feat_display="${feat_display:0:47}..."
      printf "${BOLD}║${NC}  Phase     ${CYAN}#%s — %s${NC}" "$feat_count" "$feat_display"
      local feat_pad=$((49 - ${#feat_count} - ${#feat_display}))
      [ $feat_pad -lt 0 ] && feat_pad=0
      printf "%*s${BOLD}║${NC}\n" "$feat_pad" ""
    else
      printf "${BOLD}║${NC}  Phase     ${DIM}en attente${NC}%*s${BOLD}║${NC}\n" 40 ""
    fi

    # Cost
    local cost_display="$cost$budget_str"
    printf "${BOLD}║${NC}  Coût      ${YELLOW}%s${NC}" "$cost_display"
    local cost_pad=$((49 - ${#cost_display}))
    [ $cost_pad -lt 0 ] && cost_pad=0
    printf "%*s${BOLD}║${NC}\n" "$cost_pad" ""

    # Failures + ETA
    local eta=""
    eta=$(estimate_remaining "$dir")
    local fail_eta="Échecs: $total_failures"
    [ -n "$eta" ] && fail_eta="$fail_eta | ETA: $eta"
    printf "${BOLD}║${NC}  Infos     %s" "$fail_eta"
    local info_pad=$((49 - ${#fail_eta}))
    [ $info_pad -lt 0 ] && info_pad=0
    printf "%*s${BOLD}║${NC}\n" "$info_pad" ""

    # Functional check
    if [ -f "$state_file" ] && command -v jq &> /dev/null; then
      local func_check
      func_check=$(jq -r '.functional_check_passed // "null"' "$state_file" 2>/dev/null)
      if [ "$func_check" = "true" ]; then
        printf "${BOLD}║${NC}  App       ${GREEN}fonctionnelle ✓${NC}%*s${BOLD}║${NC}\n" 34 ""
      elif [ "$func_check" = "false" ]; then
        printf "${BOLD}║${NC}  App       ${RED}non fonctionnelle ✗${NC}%*s${BOLD}║${NC}\n" 30 ""
      fi
    fi

    printf "${BOLD}╠══════════════════════════════════════════════════════════════╣${NC}\n"

    # === ROADMAP ===
    printf "${BOLD}║${NC}  ${BOLD}ROADMAP${NC}%*s${BOLD}║${NC}\n" 53 ""
    if [ -f "$roadmap_file" ]; then
      local line_count=0
      while IFS= read -r line; do
        if [[ "$line" =~ ^-\ \[x\] ]]; then
          local feat_text="${line#- [x] }"
          feat_text=$(echo "$feat_text" | sed 's/ |.*//')
          [ ${#feat_text} -gt 50 ] && feat_text="${feat_text:0:47}..."
          printf "${BOLD}║${NC}  ${GREEN}  ✅ %s${NC}" "$feat_text"
          local t_pad=$((53 - ${#feat_text}))
          [ $t_pad -lt 0 ] && t_pad=0
          printf "%*s${BOLD}║${NC}\n" "$t_pad" ""
          line_count=$((line_count + 1))
        elif [[ "$line" =~ ^-\ \[\ \] ]]; then
          local feat_text="${line#- [ ] }"
          feat_text=$(echo "$feat_text" | sed 's/ |.*//')
          [ ${#feat_text} -gt 50 ] && feat_text="${feat_text:0:47}..."
          # First unchecked = en cours
          if [ "$line_count" -eq "$done_count" ]; then
            printf "${BOLD}║${NC}  ${CYAN}  🔄 %s${NC}" "$feat_text"
          else
            printf "${BOLD}║${NC}    ⬚ %s" "$feat_text"
          fi
          local t_pad=$((53 - ${#feat_text}))
          [ $t_pad -lt 0 ] && t_pad=0
          printf "%*s${BOLD}║${NC}\n" "$t_pad" ""
          line_count=$((line_count + 1))
        elif [[ "$line" =~ ^##\  ]]; then
          local section="${line#\#\# }"
          [ ${#section} -gt 54 ] && section="${section:0:51}..."
          printf "${BOLD}║${NC}  ${BOLD}%s${NC}" "$section"
          local s_pad=$((56 - ${#section}))
          [ $s_pad -lt 0 ] && s_pad=0
          printf "%*s${BOLD}║${NC}\n" "$s_pad" ""
        fi
      done < "$roadmap_file"
    fi

    printf "${BOLD}╠══════════════════════════════════════════════════════════════╣${NC}\n"

    # === ACTIVITY LOG ===
    printf "${BOLD}║${NC}  ${BOLD}DERNIÈRE ACTIVITÉ${NC}%*s${BOLD}║${NC}\n" 43 ""
    if [ -f "$logfile" ]; then
      tail -6 "$logfile" 2>/dev/null | while IFS= read -r log_line; do
        # Extraire timestamp court et message
        local ts_short msg
        ts_short=$(echo "$log_line" | grep -oP '^\[\K\d{4}-\d{2}-\d{2} \d{2}:\d{2}' 2>/dev/null || echo "")
        if [ -n "$ts_short" ]; then
          local time_only="${ts_short##* }"
          msg=$(echo "$log_line" | sed 's/^\[[^]]*\] \[[^]]*\] //')
          [ ${#msg} -gt 46 ] && msg="${msg:0:43}..."
          printf "${BOLD}║${NC}  ${DIM}%s${NC}  %s" "$time_only" "$msg"
          local l_pad=$((52 - ${#time_only} - ${#msg}))
          [ $l_pad -lt 0 ] && l_pad=0
          printf "%*s${BOLD}║${NC}\n" "$l_pad" ""
        fi
      done
    else
      printf "${BOLD}║${NC}  ${DIM}Pas encore de logs${NC}%*s${BOLD}║${NC}\n" 42 ""
    fi

    printf "${BOLD}╚══════════════════════════════════════════════════════════════╝${NC}\n"
    printf "${DIM}Rafraîchissement : %ss | Ctrl+C pour quitter${NC}\n" "$refresh"

    sleep "$refresh"
  done
}

# ============================================================
# COMMANDE : watch (opérateur autonome)
# ============================================================

cmd_watch() {
  local name="${1:-}"

  # Sous-commande stop
  if [ "$name" = "stop" ]; then
    local target="${2:-}"
    if [ -z "$target" ]; then
      target=$(infer_project_from_cwd) || die "Usage : orc watch stop <nom>"
    fi
    require_project "$target"
    local target_dir
    target_dir=$(project_dir "$target")
    local pid_file="$target_dir/.orc/.watch-pid"
    if [ -f "$pid_file" ]; then
      local wpid
      wpid=$(cat "$pid_file")
      if kill -0 "$wpid" 2>/dev/null; then
        kill "$wpid"
        # Attendre la fin effective (max 5s)
        local wait_count=0
        while kill -0 "$wpid" 2>/dev/null && [ "$wait_count" -lt 10 ]; do
          sleep 0.5
          wait_count=$((wait_count + 1))
        done
        rm -f "$pid_file"
        printf "${GREEN}Watch arrêté${NC} (PID %s)\n" "$wpid"
      else
        rm -f "$pid_file"
        printf "${YELLOW}Watch déjà arrêté${NC} (PID %s mort, fichier nettoyé)\n" "$wpid"
      fi
    else
      printf "${YELLOW}Pas de watch actif pour %s${NC}\n" "$target"
    fi
    return 0
  fi

  # Auto-détection du projet si pas de nom (ou si le premier arg est une option)
  if [ -z "$name" ] || [ "${name#-}" != "$name" ]; then
    name=$(infer_project_from_cwd) || die "Usage : orc watch <nom> [--interval 3m] [--interactive]"
  else
    shift || true
  fi
  require_project "$name"

  local interval="3m"
  local interactive=false

  while [ $# -gt 0 ]; do
    case "$1" in
      --interval|-i)
        interval="${2:-3m}"
        [ -z "${2:-}" ] && die "--interval nécessite une durée (ex: 3m, 5m)"
        shift 2
        ;;
      --interactive|--chat)
        interactive=true
        shift
        ;;
      --loop|-l)
        # --loop est un alias implicite (le mode par défaut est déjà en boucle)
        shift
        ;;
      *) die "Option inconnue : $1. Usage : orc watch <nom> [--interval 3m] [--interactive]" ;;
    esac
  done

  local dir
  dir=$(project_dir "$name")

  command -v claude &>/dev/null || die "Claude Code CLI non installé."

  # Lire le skill orc-watch
  local skill_file="$ORC_DIR/.claude/skills/orc-watch.md"
  [ -f "$skill_file" ] || die "Skill orc-watch.md non trouvé dans $ORC_DIR/.claude/skills/"

  # Extraire le contenu du skill (sans le frontmatter)
  local skill_content
  skill_content=$(awk '/^---$/{n++; next} n>=2' "$skill_file")

  # Construire le contexte opérateur
  local watch_prompt="Tu es l'opérateur du projet '${name}' orchestré par ORC.
Répertoire du projet : ${dir}
Répertoire orc (template) : ${ORC_DIR}

${skill_content}"

  if [ "$interactive" = true ]; then
    # Mode interactif : session Claude avec contexte opérateur
    printf "${BOLD}orc watch${NC} — %s ${CYAN}(interactif)${NC}\n" "$name"
    printf "${DIM}Opérateur autonome avec contexte projet. Tape tes commandes.${NC}\n\n"

    cd "$ORC_DIR" && claude --append-system-prompt "$watch_prompt"
  else
    # Mode boucle : surveillance continue
    local pid_file="$dir/.orc/.watch-pid"
    mkdir -p "$dir/.orc"

    # Vérifier qu'un watch ne tourne pas déjà
    if [ -f "$pid_file" ]; then
      local existing_pid
      existing_pid=$(cat "$pid_file")
      if kill -0 "$existing_pid" 2>/dev/null; then
        die "Watch déjà actif pour $name (PID $existing_pid). Arrêter avec : orc watch stop $name"
      fi
      rm -f "$pid_file"
    fi

    # Écrire le PID et nettoyer à la sortie
    echo $$ > "$pid_file"
    trap 'rm -f "$pid_file"; printf "\n${DIM}Watch arrêté.${NC}\n"; exit 0' INT TERM EXIT

    printf "${BOLD}orc watch${NC} — %s ${CYAN}(boucle toutes les %s)${NC}\n" "$name" "$interval"
    printf "${DIM}Arrêter : Ctrl+C ou 'orc watch stop %s'${NC}\n\n" "$name"

    while true; do
      local timestamp
      timestamp=$(date '+%H:%M:%S')
      printf "${DIM}[%s]${NC} " "$timestamp"

      # Lancer Claude en one-shot avec le skill
      local output
      output=$(cd "$ORC_DIR" && timeout 300 claude -p \
        --model claude-sonnet-4-6 \
        --max-turns 15 \
        --dangerously-skip-permissions \
        --append-system-prompt "$watch_prompt" \
        "Vérifie le projet '${name}' maintenant. Projet dir: ${dir}" \
        2>&1) || true

      # Afficher la sortie (colorée si contient des mots-clés)
      if echo "$output" | grep -qi "crash\|erreur\|bloqué\|fix"; then
        printf "${RED}%s${NC}\n" "$output"
      elif echo "$output" | grep -qi "warning\|roadmap item"; then
        printf "${YELLOW}%s${NC}\n" "$output"
      else
        printf "%s\n" "$output"
      fi

      # Auto-stop si le run est dans un état terminal
      if [ -f "$dir/.orc/state.json" ] && command -v jq &>/dev/null; then
        local run_status
        run_status=$(jq -r '.run_status // ""' "$dir/.orc/state.json" 2>/dev/null)
        case "$run_status" in
          completed)
            printf "\n${GREEN}Run terminé.${NC} Watch arrêté.\n"; exit 0 ;;
          stopped)
            printf "\n${YELLOW}Run arrêté.${NC} Watch arrêté.\n"; exit 0 ;;
          budget_exceeded)
            printf "\n${RED}Budget dépassé.${NC} Watch arrêté.\n"; exit 0 ;;
          alignment_pending)
            printf "\n${BLUE}Alignement requis.${NC} Relancer : ${CYAN}orc agent start %s${NC}\n" "$name"
            printf "Watch arrêté.\n"; exit 0 ;;
        esac
      fi

      # Attendre l'intervalle (interruptible par Ctrl+C)
      sleep "$interval"
    done
  fi
}

# ============================================================
# DISPATCH AGENT
# ============================================================

agent_dispatch() {
  local subcmd="${1:-help}"
  shift || true

  case "$subcmd" in
    new)       cmd_new "$@" ;;
    start)     cmd_start "$@" ;;
    stop)      cmd_stop "$@" ;;
    restart)   cmd_restart "$@" ;;
    status)    cmd_status "$@" ;;
    logs)      cmd_logs "$@" ;;
    dashboard) cmd_dashboard "$@" ;;
    github)    cmd_github "$@" ;;
    env)       cmd_env "$@" ;;
    adopt)     cmd_adopt "$@" ;;
    watch)     cmd_watch "$@" ;;
    help|-h|--help) cmd_agent_help ;;
    *) die "Commande inconnue : agent $subcmd. Voir : orc agent help" ;;
  esac
}
