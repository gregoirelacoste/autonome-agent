#!/bin/bash
# ============================================================
# orc-admin.sh — Administration système (sourcé par orc.sh)
# ============================================================
#
# Sous-commandes : config, model, budget, key, version
#
# Variables attendues de orc.sh :
#   ORC_DIR, ORC_VERSION, PROJECTS_DIR,
#   RED, GREEN, YELLOW, BLUE, CYAN, BOLD, DIM, NC, die()
# ============================================================

PROJECTS_DIR="${PROJECTS_DIR:-$HOME/projects}"

# ============================================================
# COMMANDE : config
# ============================================================

admin_config() {
  local subcmd="${1:-show}"
  shift || true

  case "$subcmd" in
    show)
      echo ""
      printf "${BOLD}Configuration globale${NC}\n"
      printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
      printf "  Install     : %s\n" "$ORC_DIR"
      printf "  Projets     : %s\n" "$PROJECTS_DIR"
      printf "  Version     : %s\n" "$ORC_VERSION"

      # Modèle
      local model_file="$ORC_DIR/.model"
      if [ -f "$model_file" ]; then
        printf "  Modèle      : ${CYAN}%s${NC}\n" "$(cat "$model_file")"
      else
        printf "  Modèle      : ${DIM}défaut (claude code)${NC}\n"
      fi

      # Clés
      echo ""
      printf "  ${BOLD}Clés API :${NC}\n"
      if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
        local masked
        masked="${ANTHROPIC_API_KEY:0:8}...${ANTHROPIC_API_KEY: -4}"
        printf "  ANTHROPIC   : ${GREEN}%s${NC}\n" "$masked"
      else
        printf "  ANTHROPIC   : ${RED}non configurée${NC}\n"
      fi
      if [ -n "${GEMINI_API_KEY:-}" ]; then
        local masked_g
        masked_g="${GEMINI_API_KEY:0:8}...${GEMINI_API_KEY: -4}"
        printf "  GEMINI      : ${GREEN}%s${NC}\n" "$masked_g"
      else
        printf "  GEMINI      : ${DIM}non configurée (optionnel)${NC}\n"
      fi

      # Config par défaut
      echo ""
      printf "  ${BOLD}Config par défaut (config.default.sh) :${NC}\n"
      if [ -f "$ORC_DIR/config.default.sh" ]; then
        grep -E '^[A-Z_]+=' "$ORC_DIR/config.default.sh" 2>/dev/null | while IFS= read -r line; do
          printf "  ${DIM}%s${NC}\n" "$line"
        done
      fi
      echo ""
      ;;

    set)
      local key="${1:-}"
      local value="${2:-}"
      [ -z "$key" ] || [ -z "$value" ] && die "Usage : orc admin config set <KEY> <VALUE>"

      local config_file="$ORC_DIR/config.default.sh"
      [ -f "$config_file" ] || die "config.default.sh non trouvé"

      if grep -q "^${key}=" "$config_file"; then
        sed -i "s|^${key}=.*|${key}=\"${value}\"|" "$config_file"
        printf "${GREEN}%s${NC} = %s (config.default.sh)\n" "$key" "$value"
      else
        printf "\n${key}=\"${value}\"\n" >> "$config_file"
        printf "${GREEN}%s${NC} = %s (ajouté à config.default.sh)\n" "$key" "$value"
      fi
      ;;

    *)
      die "Usage : orc admin config [show|set KEY VALUE]"
      ;;
  esac
}

# ============================================================
# COMMANDE : model
# ============================================================

admin_model() {
  local subcmd="${1:-show}"
  shift || true

  local model_file="$ORC_DIR/.model"

  case "$subcmd" in
    show)
      echo ""
      printf "${BOLD}Modèle Claude${NC}\n"
      printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
      if [ -f "$model_file" ]; then
        printf "  Actuel : ${CYAN}%s${NC}\n" "$(cat "$model_file")"
      else
        printf "  Actuel : ${DIM}défaut (modèle par défaut de Claude Code CLI)${NC}\n"
      fi
      echo ""
      printf "  ${BOLD}Modèles disponibles :${NC}\n"
      printf "  ${CYAN}claude-sonnet-4-6${NC}  — Rapide, économique (recommandé)\n"
      printf "  ${CYAN}claude-opus-4-6${NC}   — Plus capable, plus cher\n"
      printf "  ${CYAN}claude-haiku-4-5${NC}  — Ultra-rapide, très économique\n"
      echo ""
      printf "  ${BOLD}Tarifs API (par million de tokens) :${NC}\n"
      printf "  %-30s ${DIM}Input       Output${NC}\n" ""
      printf "  %-30s \$3.00       \$15.00\n" "Sonnet 4.6"
      printf "  %-30s \$15.00      \$75.00\n" "Opus 4.6"
      printf "  %-30s \$0.80       \$4.00\n" "Haiku 4.5"
      echo ""
      printf "  ${DIM}Changer : orc admin model set <model-id>${NC}\n"
      printf "  ${DIM}Reset   : orc admin model reset${NC}\n"
      echo ""
      ;;

    set)
      local model="${1:-}"
      [ -z "$model" ] && die "Usage : orc admin model set <model-id>"

      echo "$model" > "$model_file"
      printf "${GREEN}Modèle configuré : %s${NC}\n" "$model"
      printf "${DIM}Les prochains lancements utiliseront ce modèle.${NC}\n"
      printf "${DIM}Projets en cours non affectés (restart nécessaire).${NC}\n"
      ;;

    reset)
      rm -f "$model_file"
      printf "${GREEN}Modèle reset au défaut Claude Code CLI.${NC}\n"
      ;;

    *)
      die "Usage : orc admin model [show|set <model>|reset]"
      ;;
  esac
}

# ============================================================
# COMMANDE : budget
# ============================================================

admin_budget() {
  echo ""
  printf "${BOLD}Budget — Coûts par projet${NC}\n"
  printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"

  local total_cost=0
  local total_input=0
  local total_output=0
  local total_invocations=0
  local has_data=false

  printf "\n  ${BOLD}%-20s %-12s %-14s %-14s %-8s %s${NC}\n" \
    "PROJET" "COÛT" "INPUT" "OUTPUT" "APPELS" "LIMITE"
  printf "  %-20s %-12s %-14s %-14s %-8s %s\n" \
    "────────────────────" "────────────" "──────────────" "──────────────" "────────" "──────────"

  for proj_dir in "$PROJECTS_DIR"/*/; do
    [ -d "$proj_dir" ] || continue

    local proj_name
    proj_name=$(basename "$proj_dir")

    local cost="0" input_t="0" output_t="0" invocations="0" limit="illimité"

    if [ -f "$proj_dir/.orc/tokens.json" ]; then
      has_data=true
      cost=$(jq -r '.total_cost_usd // 0' "$proj_dir/.orc/tokens.json" 2>/dev/null || echo "0")
      input_t=$(jq -r '.total_input_tokens // 0' "$proj_dir/.orc/tokens.json" 2>/dev/null || echo "0")
      output_t=$(jq -r '.total_output_tokens // 0' "$proj_dir/.orc/tokens.json" 2>/dev/null || echo "0")
      invocations=$(jq -r '.invocations // 0' "$proj_dir/.orc/tokens.json" 2>/dev/null || echo "0")
    fi

    if [ -f "$proj_dir/.orc/config.sh" ]; then
      local max_budget
      max_budget=$(grep -oP 'MAX_BUDGET_USD="\K[^"]+' "$proj_dir/.orc/config.sh" 2>/dev/null || echo "")
      [ -n "$max_budget" ] && limit="\$$max_budget"
    fi

    # Formater les tokens (K/M)
    local input_fmt output_fmt
    if [ "$input_t" -gt 1000000 ] 2>/dev/null; then
      input_fmt="$(echo "scale=1; $input_t / 1000000" | bc 2>/dev/null || echo "$input_t")M"
    elif [ "$input_t" -gt 1000 ] 2>/dev/null; then
      input_fmt="$(echo "scale=1; $input_t / 1000" | bc 2>/dev/null || echo "$input_t")K"
    else
      input_fmt="$input_t"
    fi

    if [ "$output_t" -gt 1000000 ] 2>/dev/null; then
      output_fmt="$(echo "scale=1; $output_t / 1000000" | bc 2>/dev/null || echo "$output_t")M"
    elif [ "$output_t" -gt 1000 ] 2>/dev/null; then
      output_fmt="$(echo "scale=1; $output_t / 1000" | bc 2>/dev/null || echo "$output_t")K"
    else
      output_fmt="$output_t"
    fi

    # Couleur coût
    local cost_color="$NC"
    if [ "$(echo "$cost > 10" | bc 2>/dev/null)" = "1" ]; then
      cost_color="$RED"
    elif [ "$(echo "$cost > 5" | bc 2>/dev/null)" = "1" ]; then
      cost_color="$YELLOW"
    fi

    printf "  %-20s ${cost_color}\$%-11s${NC} %-14s %-14s %-8s %s\n" \
      "$proj_name" "$cost" "$input_fmt" "$output_fmt" "$invocations" "$limit"

    # Accumuler les totaux (utiliser bc pour les décimaux)
    total_cost=$(echo "$total_cost + $cost" | bc 2>/dev/null || echo "$total_cost")
    total_input=$((total_input + input_t))
    total_output=$((total_output + output_t))
    total_invocations=$((total_invocations + invocations))
  done

  if [ "$has_data" = true ]; then
    printf "  %-20s %-12s %-14s %-14s %-8s\n" \
      "────────────────────" "────────────" "──────────────" "──────────────" "────────"
    printf "  ${BOLD}%-20s \$%-11s %-14s %-14s %s${NC}\n" \
      "TOTAL" "$total_cost" "${total_input}" "${total_output}" "$total_invocations"
  else
    printf "\n  ${DIM}Aucune donnée de coût. Lancez un projet pour commencer le tracking.${NC}\n"
  fi

  echo ""
}

# ============================================================
# COMMANDE : key
# ============================================================

admin_key() {
  local subcmd="${1:-show}"
  shift || true

  local env_file="$ORC_DIR/.env"

  case "$subcmd" in
    show)
      echo ""
      printf "${BOLD}Clés API${NC}\n"
      printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"

      if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
        local masked
        masked="${ANTHROPIC_API_KEY:0:12}...${ANTHROPIC_API_KEY: -4}"
        printf "  ANTHROPIC_API_KEY : ${GREEN}%s${NC}\n" "$masked"
      else
        printf "  ANTHROPIC_API_KEY : ${RED}non configurée${NC}\n"
      fi

      if [ -n "${GEMINI_API_KEY:-}" ]; then
        local masked_g
        masked_g="${GEMINI_API_KEY:0:12}...${GEMINI_API_KEY: -4}"
        printf "  GEMINI_API_KEY    : ${GREEN}%s${NC}\n" "$masked_g"
      else
        printf "  GEMINI_API_KEY    : ${DIM}non configurée (optionnel)${NC}\n"
      fi

      echo ""
      printf "  ${DIM}Fichier : %s${NC}\n" "$env_file"
      printf "  ${DIM}Modifier : orc admin key set <clé>${NC}\n"
      printf "  ${DIM}Ajouter Gemini : orc admin key set-gemini <clé>${NC}\n"
      echo ""
      ;;

    set)
      local key="${1:-}"
      [ -z "$key" ] && die "Usage : orc admin key set <ANTHROPIC_API_KEY>"

      # Valider le format basique
      if [[ ! "$key" =~ ^sk-ant- ]]; then
        printf "${YELLOW}Attention : la clé ne commence pas par 'sk-ant-'. Vérifiez le format.${NC}\n"
        read -rp "Continuer ? [o/N] : " confirm
        [[ ! "$confirm" =~ ^[Oo]$ ]] && { echo "Abandon."; return; }
      fi

      # Écrire/remplacer
      if [ -f "$env_file" ]; then
        # Remplacer la ligne existante ou ajouter
        if grep -q "ANTHROPIC_API_KEY" "$env_file"; then
          sed -i "s|^export ANTHROPIC_API_KEY=.*|export ANTHROPIC_API_KEY=\"$key\"|" "$env_file"
        else
          echo "export ANTHROPIC_API_KEY=\"$key\"" >> "$env_file"
        fi
      else
        echo "export ANTHROPIC_API_KEY=\"$key\"" > "$env_file"
      fi

      chmod 600 "$env_file"
      printf "${GREEN}Clé Anthropic configurée.${NC}\n"
      printf "${DIM}Redémarrez les projets en cours pour appliquer.${NC}\n"
      ;;

    set-gemini)
      local key="${1:-}"
      [ -z "$key" ] && die "Usage : orc admin key set-gemini <GEMINI_API_KEY>"

      if [ -f "$env_file" ]; then
        if grep -q "GEMINI_API_KEY" "$env_file"; then
          sed -i "s|^export GEMINI_API_KEY=.*|export GEMINI_API_KEY=\"$key\"|" "$env_file"
        else
          echo "export GEMINI_API_KEY=\"$key\"" >> "$env_file"
        fi
      else
        echo "export GEMINI_API_KEY=\"$key\"" > "$env_file"
      fi

      chmod 600 "$env_file"
      printf "${GREEN}Clé Gemini configurée.${NC}\n"
      ;;

    *)
      die "Usage : orc admin key [show|set <key>|set-gemini <key>]"
      ;;
  esac
}

# ============================================================
# COMMANDE : version
# ============================================================

admin_version() {
  echo ""
  printf "${BOLD}Autonome Agent v%s${NC}\n" "$ORC_VERSION"
  printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
  printf "  Install : %s\n" "$ORC_DIR"

  # Git info
  if [ -d "$ORC_DIR/.git" ]; then
    local branch commit
    branch=$(git -C "$ORC_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "?")
    commit=$(git -C "$ORC_DIR" log --oneline -1 2>/dev/null || echo "?")
    printf "  Branche : %s\n" "$branch"
    printf "  Commit  : %s\n" "$commit"
  fi

  echo ""
  printf "  ${BOLD}Dépendances :${NC}\n"

  # Claude CLI
  if command -v claude &> /dev/null; then
    local claude_ver
    claude_ver=$(claude --version 2>/dev/null | head -1 || echo "installé")
    printf "  ${GREEN}✓${NC} claude CLI (%s)\n" "$claude_ver"
  else
    printf "  ${RED}✗${NC} claude CLI (non trouvé)\n"
  fi

  # Node
  if command -v node &> /dev/null; then
    printf "  ${GREEN}✓${NC} node %s\n" "$(node --version 2>/dev/null)"
  else
    printf "  ${RED}✗${NC} node\n"
  fi

  # jq
  if command -v jq &> /dev/null; then
    printf "  ${GREEN}✓${NC} jq %s\n" "$(jq --version 2>/dev/null)"
  else
    printf "  ${YELLOW}~${NC} jq (optionnel, non installé)\n"
  fi

  # git
  if command -v git &> /dev/null; then
    printf "  ${GREEN}✓${NC} git %s\n" "$(git --version 2>/dev/null | cut -d' ' -f3)"
  else
    printf "  ${RED}✗${NC} git\n"
  fi

  # gh
  if command -v gh &> /dev/null; then
    printf "  ${GREEN}✓${NC} gh %s\n" "$(gh --version 2>/dev/null | head -1 | awk '{print $3}')"
  else
    printf "  ${DIM}~${NC} gh (optionnel, non installé)\n"
  fi

  # bc
  if command -v bc &> /dev/null; then
    printf "  ${GREEN}✓${NC} bc\n"
  else
    printf "  ${DIM}~${NC} bc (optionnel, pour les calculs de coût)\n"
  fi

  # Clé API
  echo ""
  if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
    printf "  ${GREEN}✓${NC} ANTHROPIC_API_KEY configurée\n"
  else
    printf "  ${RED}✗${NC} ANTHROPIC_API_KEY non configurée\n"
  fi

  echo ""
}

# ============================================================
# HELP ADMIN
# ============================================================

admin_help() {
  echo ""
  printf "${BOLD}orc admin — Administration système${NC}\n"
  echo ""
  printf "  ${CYAN}orc admin config${NC}                   Voir la config globale\n"
  printf "  ${CYAN}orc admin config set KEY VAL${NC}       Modifier config.default.sh\n"
  echo ""
  printf "  ${CYAN}orc admin model${NC}                    Modèle Claude actuel + tarifs\n"
  printf "  ${CYAN}orc admin model set <model>${NC}        Changer le modèle\n"
  printf "  ${CYAN}orc admin model reset${NC}              Revenir au modèle par défaut\n"
  echo ""
  printf "  ${CYAN}orc admin budget${NC}                   Coûts détaillés par projet\n"
  echo ""
  printf "  ${CYAN}orc admin key${NC}                      Voir les clés API (masquées)\n"
  printf "  ${CYAN}orc admin key set <key>${NC}            Configurer clé Anthropic\n"
  printf "  ${CYAN}orc admin key set-gemini <key>${NC}     Configurer clé Gemini\n"
  echo ""
  printf "  ${CYAN}orc admin version${NC}                  Version + vérification dépendances\n"
  echo ""
}

# ============================================================
# DISPATCH ADMIN
# ============================================================

admin_dispatch() {
  local subcmd="${1:-help}"
  shift || true

  case "$subcmd" in
    config)  admin_config "$@" ;;
    model)   admin_model "$@" ;;
    budget)  admin_budget "$@" ;;
    key)     admin_key "$@" ;;
    version) admin_version ;;
    help|-h|--help) admin_help ;;
    *) die "Commande inconnue : admin $subcmd. Voir : orc admin help" ;;
  esac
}
