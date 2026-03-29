#!/bin/bash
# ============================================================
# Configuration de l'agent autonome
# Modifier ces valeurs selon votre projet
# ============================================================

# === PROJET ===
PROJECT_DIR="."                          # Racine du workspace (= le projet)
PROJECT_NAME=""                          # Nom du projet (rempli par init.sh)

# === GARDE-FOUS ===
MAX_FIX_ATTEMPTS=3                       # Tentatives de correction par feature
MAX_FEATURES=50                          # Nombre total de features avant arrêt
MAX_TURNS_PER_INVOCATION=50              # Limite de turns par appel Claude
MAX_TURNS_PLAN=8                         # Turns pour la phase plan (5 = souvent trop juste sur gros codebase)

# === RYTHME ===
EPIC_SIZE=3                              # Nombre de features par epic avant veille ciblée
META_RETRO_FREQUENCY=5                   # Méta-rétrospective toutes les N features

# === INTERVENTION HUMAINE ===
PAUSE_EVERY_N_FEATURES=0                 # Pause humaine toutes les N features (0 = jamais)
REQUIRE_HUMAN_APPROVAL=false             # true = attend validation avant chaque merge
AUTO_EVOLVE_ROADMAP=true                 # Claude peut ajouter des features à la roadmap
MAX_EVOLVE_CYCLES=2                      # Nombre max de cycles evolve (0 = illimité)
MAX_AI_ROADMAP_ADDS=5                    # Max features ajoutées par l'IA entre deux pauses humaines
ALIGNMENT_CHECK=true                     # Checkpoint d'alignement brief/code/roadmap entre les cycles evolve
                                         # Génère un rapport, pose des questions ciblées à l'humain au prochain start.
                                         # false = enchaîne les cycles sans pause d'alignement.
ENABLE_AUTO_BRAINSTORM=true              # Brainstorm auto en fin de cycle (recherche web + 10 tickets)
                                         # L'IA s'interroge elle-même : analyse gaps, recherche concurrence,
                                         # propose et rédige des tickets structurés. false = evolve classique (3-5 tickets).
MAX_AUTO_BRAINSTORM_TICKETS=10           # Max tickets générés par auto-brainstorm

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
MAX_TURNS_RESEARCH_INITIAL=50            # Budget recherche initiale
MAX_TURNS_RESEARCH_EPIC=20               # Budget veille ciblée par epic
MAX_TURNS_RESEARCH_TREND=30              # Budget veille tendances (méta-rétro)

# === TECHNIQUE ===
BUILD_COMMAND="npm run build"            # Commande de build
TEST_COMMAND="npx playwright test"       # Commande de test
DEV_COMMAND="npm run dev"                # Commande serveur dev
DEV_PORT=3000                            # Port du serveur dev (pour les tests QA)
LINT_COMMAND="npm run lint"              # Commande lint (vide = désactivé)
QUALITY_COMMAND=""                       # Commande quality gate post-tests (vide = désactivé)
                                         # Ex: "npm run lighthouse -- --budget=80" ou "npx bundle-size-check"
DEPLOY_COMMAND=""                        # Commande de déploiement (vide = désactivé)
                                         # Ex: "scripts/deploy.sh" ou "vercel deploy --prod"
                                         # Exécuté en fin de projet si le run est complet.
COVERAGE_COMMAND=""                      # Commande de couverture de tests (vide = désactivé)
                                         # Ex: "npx vitest run --coverage --reporter=json" ou "pytest --cov --cov-report=term"
                                         # Doit afficher un % de couverture dans son output.
MAX_FILES_PER_FEATURE=30                 # Alerte si une feature modifie plus de N fichiers
MAX_DELETIONS_PER_FEATURE=500            # Bloque le merge si > N suppressions avec ratio > 3:1
FUNCTIONAL_CHECK_COMMAND=""              # Vérification fonctionnelle post-feature (vide = désactivé)
                                         # L'app DOIT être fonctionnelle après chaque feature.
                                         # Ex: "npm start -- --check" ou "curl -sf http://localhost:3000/health"
                                         # ou "docker compose up -d && sleep 5 && curl -sf localhost:3000 && docker compose down"
CLAUDE_MODEL=""                          # Modèle principal (implement, fix). Ex: "claude-sonnet-4-6"
                                         # Vide = modèle par défaut de la CLI.
CLAUDE_MODEL_LIGHT="claude-haiku-4-5"  # Modèle léger pour phases simples (plan, critic, reflect, research, etc.)
                                         # Économise ~35-45% du budget total. Vide = utilise CLAUDE_MODEL.
CLAUDE_MODEL_STRONG="claude-opus-4-6"  # Modèle fort pour phases de réflexion profonde (challenger)
                                         # Vide = utilise CLAUDE_MODEL. Hiérarchie : STRONG > CLAUDE_MODEL > LIGHT.

# === CHALLENGER (enrichissement feature pré-implémentation) ===
ENABLE_CHALLENGER=true                   # Challenger chaque feature avant plan (modèle fort)
                                         # Analyse produit : complétude, edge cases, UX, sécurité, cohérence
                                         # false = skip directement au plan
MAX_TURNS_CHALLENGER=3                   # Turns pour le challenger (contexte pré-injecté → 1-2 suffisent)

# === PRODUCT REVIEW (autocritique métier post-implémentation) ===
ENABLE_PRODUCT_REVIEW=true               # Review produit après chaque feature (modèle fort)
                                         # Vérifie la valeur livrée, l'UX, l'adéquation au brief
                                         # Applique max 3 quick wins cosmétiques (libellés, messages, états)
                                         # false = skip, passe directement à reflect
MAX_TURNS_PRODUCT_REVIEW=5               # Turns pour la review produit (analyse + quick wins éventuels)

# === BUDGET ===
MAX_BUDGET_USD="200.00"                  # Budget max en USD. Garde-fou par défaut. Ajuster selon le projet.
                                         # Budget prédictif : refuse de lancer si le coût estimé dépasse le restant.

# === TIMEOUTS ===
CLAUDE_TIMEOUT=900                       # Timeout par défaut en secondes (0 = illimité). 900 = 15min.
                                         # Surchargé par PHASE_TIMEOUTS si défini pour la phase.
STALL_KILL_THRESHOLD=60                  # Nombre de checks sans données avant kill auto (×5s = durée)
                                         # 60 = 5min sans données → kill. 0 = désactivé (warning seul).
# Timeouts par phase (secondes). Les phases non listées utilisent CLAUDE_TIMEOUT.
# Ajuster selon vos besoins. Commenter pour tout ramener à CLAUDE_TIMEOUT.
declare -A PHASE_TIMEOUTS=(
  ["challenger"]=120        # 2min  — challenge feature (analyse produit, pas code)
  ["product-review"]=180   # 3min  — review produit post-feature (analyse + quick wins)
  ["plan"]=120              # 2min  — planification rapide
  ["critic"]=600            # 10min — review adversariale (modèle principal, 10 turns)
  ["reflect"]=180           # 3min  — rétrospective feature
  ["quality"]=180           # 3min  — correction quality gate
  ["self-improve"]=300      # 5min  — auto-amélioration
  ["strategy"]=300          # 5min  — génération roadmap
  ["evolve"]=300            # 5min  — évolution roadmap
  ["alignment"]=120         # 2min  — rapport d'alignement
  ["research-initial"]=600  # 10min — recherche web
  ["research-epic"]=300     # 5min  — veille ciblée
  ["acceptance"]=300         # 5min  — validation acceptance epic
  ["qa"]=600                  # 10min — tests fonctionnels réels (curl + navigateur)
  ["tech-debt"]=600          # 10min — refactoring tech-debt
  ["user-docs"]=300          # 5min  — génération doc utilisateur
  ["meta-retro"]=600        # 10min — méta-rétrospective
  ["implement"]=900         # 15min — implémentation
  ["fix"]=600               # 10min — correction
)

# === LOGS ===
LOG_DIR="./.orc/logs"                    # Dossier des logs orchestrateur (dans .orc/)
VERBOSE=true                             # Logs détaillés dans la console
ORC_DEBUG=true                           # Log temps réel des actions Claude dans orc-debug-live.log
                                         # Tool calls, texte généré, erreurs — zéro token Claude
                                         # Suivre en live : orc logs <nom> --debug
