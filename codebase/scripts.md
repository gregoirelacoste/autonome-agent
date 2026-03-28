# ORC — Scripts principaux

## orc.sh — Point d'entrée CLI unifiée
- Parse les sous-commandes : `agent`, `roadmap`, `admin` + raccourcis `s`, `r`, `l`
- Délègue à orc-agent.sh ou orc-admin.sh
- Gère --help et --version

## orc-agent.sh — Gestion des projets
- `new <nom>` — crée un workspace via init.sh
- `start <nom>` — lance orchestrator.sh en nohup
- `stop <nom>` — arrêt gracieux (SIGTERM + 30s timeout)
- `restart <nom>` — stop + start
- `status [nom]` — dashboard (features, coût, %, PID)
- `logs <nom>` — tail -f ou --full
- `roadmap` — vue filtrable des items roadmap/

## orc-admin.sh — Administration globale
- `config [show|set]` — configuration globale
- `model [show|set|reset]` — choix du modèle Claude
- `budget` — dépenses totales cross-projets
- `key` — gestion des API keys (masquées)
- `version` — version + checks dépendances
- `update` — git pull du template

## orchestrator.sh — Boucle principale (coeur du système)
- ~2900 lignes bash
- Séquence : bootstrap → research → strategy → feature loop (plan → implement → lint → critic → test/fix → reflect) → evolve
- Voir codebase/functions.md pour le détail des fonctions

## init.sh — Wizard de création de projet
- Crée le workspace séparé (../mon-projet/)
- Copie orchestrator.sh, phases/, skills-templates/, learnings/
- Configure .orc/config.sh
- Optionnel : crée le repo GitHub via `gh`

## agent.sh — Legacy, redirige vers orc.sh

## deploy.sh — Déploiement (optionnel)

## config.default.sh — Template de configuration
- Voir codebase/config-params.md pour le détail
