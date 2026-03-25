# ORC — Codebase Index
> Carte sémantique de l'orchestrateur. Consulter avant toute modification.
> Pour le détail, voir le fichier indiqué.

## Scripts principaux (→ codebase/scripts.md)
CLI unifiée (orc.sh → orc-agent.sh / orc-admin.sh) + orchestrateur (orchestrator.sh) + wizard (init.sh).

## Phases d'orchestration (→ codebase/phases.md)
8 phases séquentielles : bootstrap → research → strategy → implement → test-fix → reflect → meta-retro → evolve.

## Fonctions clés de orchestrator.sh (→ codebase/functions.md)
run_claude(), render_phase(), generate_repo_map(), error_hash(), check_signals(), notify(), human_pause().

## Configuration (→ codebase/config-params.md)
25+ paramètres dans config.default.sh : garde-fous, rythme, intervention humaine, recherche, technique, budget, notifications.

## Système de connaissance projet (→ codebase/knowledge-system.md)
Index sémantique codebase/, auto-map, stack-conventions, learnings inter-projets, réflexions structurées, contexte adaptatif.

## Skills templates (→ codebase/skills.md)
7 skills copiées dans chaque projet au bootstrap. Auto-enrichies par l'IA.

## Roadmap ORC (→ roadmap/)
Items de roadmap pour l'outil lui-même. Fichiers .md dans backlog/planned/in-progress/done.
