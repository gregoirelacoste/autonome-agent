# ORC — Paramètres de configuration

Fichier source : config.default.sh → copié en .orc/config.sh par init.sh

## Projet
- `PROJECT_DIR` — chemin vers le dossier projet (default: "./project")
- `PROJECT_NAME` — nom du projet (rempli par init.sh)

## Garde-fous
- `MAX_FIX_ATTEMPTS=5` — tentatives de correction par feature
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
- `MAX_TURNS_RESEARCH_INITIAL=80` — budget recherche initiale
- `MAX_TURNS_RESEARCH_EPIC=40` — budget veille ciblée par epic
- `MAX_TURNS_RESEARCH_TREND=50` — budget veille tendances

## Technique
- `BUILD_COMMAND="npm run build"` — commande de build
- `TEST_COMMAND="npx playwright test"` — commande de test
- `DEV_COMMAND="npm run dev"` — commande serveur dev
- `LINT_COMMAND="npm run lint"` — commande lint
- `QUALITY_COMMAND=""` — quality gate post-tests
- `CLAUDE_MODEL=""` — modèle Claude (vide = défaut CLI)

## Budget
- `MAX_BUDGET_USD=""` — budget max en USD (vide = illimité)

## Timeouts
- `CLAUDE_TIMEOUT=1200` — timeout par invocation Claude (secondes)

## Logs
- `LOG_DIR="./.orc/logs"` — dossier des logs
- `VERBOSE=true` — logs détaillés dans la console
