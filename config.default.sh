#!/bin/bash
# ============================================================
# Configuration de l'agent autonome
# Modifier ces valeurs selon votre projet
# ============================================================

# === PROJET ===
PROJECT_DIR="./project"                  # Dossier du projet généré
PROJECT_NAME=""                          # Nom du projet (rempli par init.sh)

# === GARDE-FOUS ===
MAX_FIX_ATTEMPTS=5                       # Tentatives de correction par feature
MAX_FEATURES=50                          # Nombre total de features avant arrêt
MAX_TURNS_PER_INVOCATION=50              # Limite de turns par appel Claude

# === RYTHME ===
EPIC_SIZE=3                              # Nombre de features par epic avant veille ciblée
META_RETRO_FREQUENCY=5                   # Méta-rétrospective toutes les N features

# === INTERVENTION HUMAINE ===
PAUSE_EVERY_N_FEATURES=0                 # Pause humaine toutes les N features (0 = jamais)
REQUIRE_HUMAN_APPROVAL=false             # true = attend validation avant chaque merge
AUTO_EVOLVE_ROADMAP=true                 # Claude peut ajouter des features à la roadmap
MAX_EVOLVE_CYCLES=2                      # Nombre max de cycles evolve (0 = illimité)
MAX_AI_ROADMAP_ADDS=5                    # Max features ajoutées par l'IA entre deux pauses humaines

# === GITHUB (optionnel — tout fonctionne sans) ===
# Principe : local = source de vérité, GitHub = miroir de visibilité.
# Chaque option est indépendante et off par défaut. Activer selon les besoins.
GIT_STRATEGY="local"                     # "local" (git merge direct) | "pr" (GitHub Pull Requests)
                                         # "pr" nécessite gh CLI authentifié + remote GitHub
GITHUB_TRACKING_ISSUE=false              # Créer une issue de suivi sur GitHub (résumé du run)
                                         # Fonctionne en mode local et pr. Requiert gh CLI.
GITHUB_SIGNALS=false                     # Lire les labels GitHub comme signaux (pause/stop/continue)
                                         # Labels attendus : "orc:pause", "orc:stop", "orc:continue"
                                         # Les signaux locaux (.orc/pause-requested etc.) marchent toujours.
GITHUB_REMOTE="origin"                   # Remote Git pour push/PR (défaut: origin)
GITHUB_SYNC_ROADMAP=false                # Miroir ROADMAP.md → GitHub Issues (push-only)
                                         # Crée/ferme des issues, ne lit jamais les issues comme source.
GITHUB_FEEDBACK=false                    # Lire les commentaires GitHub (tracking issue) comme feedback additionnel
                                         # Ajouté aux notes mid-run, en plus de .orc/human-notes.md
GITHUB_CI=false                          # Valider le CI distant (GitHub Actions) en plus des tests locaux
                                         # Les tests locaux font toujours foi. CI distant = validation bonus.
GITHUB_RELEASES=false                    # Créer une GitHub Release après chaque meta-rétro / fin de projet
                                         # Changelog auto-généré + cost summary

# === NOTIFICATIONS ===
NOTIFY_COMMAND=""                        # Commande de notification (vide = désactivé)
                                         # Ex: "notify-send 'ORC'" ou "curl -X POST https://slack.webhook/..."
                                         # Recevra le message en argument : $NOTIFY_COMMAND "message"

# === RECHERCHE ===
ENABLE_RESEARCH=true                     # Activer la veille marché
MAX_TURNS_RESEARCH_INITIAL=80            # Budget recherche initiale
MAX_TURNS_RESEARCH_EPIC=40               # Budget veille ciblée par epic
MAX_TURNS_RESEARCH_TREND=50              # Budget veille tendances (méta-rétro)

# === TECHNIQUE ===
BUILD_COMMAND="npm run build"            # Commande de build
TEST_COMMAND="npx playwright test"       # Commande de test
DEV_COMMAND="npm run dev"                # Commande serveur dev
LINT_COMMAND="npm run lint"              # Commande lint (vide = désactivé)
QUALITY_COMMAND=""                       # Commande quality gate post-tests (vide = désactivé)
                                         # Ex: "npm run lighthouse -- --budget=80" ou "npx bundle-size-check"
CLAUDE_MODEL=""                          # Modèle Claude (vide = défaut CLI). Ex: "claude-sonnet-4-6-20250514"

# === BUDGET ===
MAX_BUDGET_USD=""                        # Budget max en USD (vide = illimité). Ex: "5.00"

# === TIMEOUTS ===
CLAUDE_TIMEOUT=1200                      # Timeout par invocation Claude en secondes (0 = illimité)
                                         # 1200 = 20min. Les phases WebSearch peuvent être longues.

# === LOGS ===
LOG_DIR="./.orc/logs"                    # Dossier des logs orchestrateur (dans .orc/)
VERBOSE=true                             # Logs détaillés dans la console
