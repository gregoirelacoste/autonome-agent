# ORC — Paramètres de configuration

Fichier source : config.default.sh → copié en .orc/config.sh par init.sh
Migration auto : migrate_config() ajoute les paramètres manquants au démarrage.

## Projet
- `PROJECT_DIR="."` — racine du workspace
- `PROJECT_NAME=""` — nom du projet (rempli par init.sh)

## Garde-fous
- `MAX_FIX_ATTEMPTS=3` — tentatives de correction par feature
- `MAX_FEATURES=50` — nombre total de features avant arrêt
- `MAX_TURNS_PER_INVOCATION=50` — limite de turns par appel Claude

## Rythme
- `EPIC_SIZE=3` — features par epic avant veille ciblée
- `META_RETRO_FREQUENCY=5` — méta-rétro toutes les N features

## Intervention humaine
- `PAUSE_EVERY_N_FEATURES=0` — pause toutes les N features (0 = jamais)
- `REQUIRE_HUMAN_APPROVAL=false` — validation avant chaque merge
- `AUTO_EVOLVE_ROADMAP=true` — l'IA peut ajouter des features
- `MAX_EVOLVE_CYCLES=2` — cycles evolve max (0 = illimité)
- `MAX_AI_ROADMAP_ADDS=5` — features ajoutées par l'IA avant pause

## Notifications
- `NOTIFY_COMMAND=""` — commande de notification (ex: notify-send, slack webhook)

## Recherche
- `ENABLE_RESEARCH=true` — activer la veille marché
- `MAX_TURNS_RESEARCH_INITIAL=50` — budget recherche initiale
- `MAX_TURNS_RESEARCH_EPIC=20` — budget veille ciblée par epic
- `MAX_TURNS_RESEARCH_TREND=30` — budget veille tendances

## Technique
- `BUILD_COMMAND="npm run build"` — commande de build
- `TEST_COMMAND="npx playwright test"` — commande de test
- `DEV_COMMAND="npm run dev"` — commande serveur dev
- `LINT_COMMAND="npm run lint"` — commande lint (vide = désactivé)
- `QUALITY_COMMAND=""` — quality gate post-tests
- `DEPLOY_COMMAND=""` — commande de déploiement en fin de projet (ex: `scripts/deploy.sh`, `vercel deploy --prod`)
- `FUNCTIONAL_CHECK_COMMAND=""` — vérification fonctionnelle post-feature

## Modèles
- `CLAUDE_MODEL=""` — modèle principal (implement, fix). Vide = défaut CLI
- `CLAUDE_MODEL_LIGHT="claude-haiku-4-5-20251001"` — modèle léger (plan, reflect, research, etc.)
- `CLAUDE_MODEL_STRONG="claude-opus-4-6-20250514"` — modèle fort (challenger). Vide = CLAUDE_MODEL

## Challenger
- `ENABLE_CHALLENGER=true` — activer la phase challenger (enrichissement produit pré-implémentation)
- `MAX_TURNS_CHALLENGER=3` — budget turns du challenger (contexte pré-injecté → 1-2 suffisent)

## Budget
- `MAX_BUDGET_USD="200.00"` — budget max en USD (garde-fou prédictif + post-hoc)

## Timeouts
- `CLAUDE_TIMEOUT=900` — timeout global par invocation (secondes). Surchargé par PHASE_TIMEOUTS
- `STALL_KILL_THRESHOLD=60` — checks sans données avant kill auto (×5s = durée)
- `declare -A PHASE_TIMEOUTS=(...)` — timeouts par phase (plan=120, implement=900, fix=600, etc.)

## GitHub (optionnel)
- `GIT_STRATEGY="local"` — "local" (merge direct) | "pr" (Pull Requests)
- `GITHUB_REMOTE="origin"` — remote Git pour push/PR
- `GITHUB_TRACKING_ISSUE=false` — créer une issue de suivi
- `GITHUB_SIGNALS=false` — labels comme signaux
- `GITHUB_SYNC_ROADMAP=false` — miroir roadmap → GitHub Issues
- `GITHUB_FEEDBACK=false` — lire commentaires GitHub comme feedback
- `GITHUB_CI=false` — attendre les checks GitHub Actions
- `GITHUB_RELEASES=false` — créer des releases automatiques

## Logs
- `LOG_DIR="./.orc/logs"` — dossier des logs
- `VERBOSE=true` — logs détaillés dans la console
