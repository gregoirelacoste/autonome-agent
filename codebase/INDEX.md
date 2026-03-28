# ORC — Codebase Index
> Carte sémantique de l'orchestrateur. Consulter avant toute modification.
> Pour le détail, voir le fichier indiqué.

## Scripts principaux (→ codebase/scripts.md)
CLI unifiée (orc.sh → orc-agent.sh / orc-admin.sh) + orchestrateur (orchestrator.sh) + wizard (init.sh).

## Phases d'orchestration (→ codebase/phases.md)
9 phases séquentielles : bootstrap → research → strategy → plan → implement → lint → critic → test-fix → reflect. Plus meta-retro et evolve en boucle externe.

## Fonctions clés de orchestrator.sh (→ codebase/functions.md)
run_claude(), render_phase(), generate_repo_map(), error_hash(), smart_truncate(), check_signals(), notify(), human_pause(), adaptive_max_turns(), resolve_model(), get_model_pricing(), workflow_transition(), migrate_config(), mark_feature_done_bash().

## Configuration (→ codebase/config-params.md)
38+ paramètres dans config.default.sh : garde-fous, rythme, intervention humaine, recherche, technique, modèles, budget, timeouts, GitHub, notifications.

## Système de connaissance projet (→ codebase/knowledge-system.md)
Index sémantique codebase/, auto-map, stack-conventions, learnings inter-projets, réflexions structurées, contexte adaptatif.

## Skills templates (→ codebase/skills.md)
8 skills copiées dans chaque projet au bootstrap. Auto-enrichies par l'IA.
Inclut clarify-brief.md pour le mode --brief avec clarification.

## Documentation utilisateur (→ docs/INDEX.md)
7 guides dans docs/ : getting-started, init-modes, commands-reference, configuration, github-integration, human-controls, faq.
Maintenu via le skill .claude/skills/maintain-docs.md.

## Roadmap ORC (→ roadmap/)
Items de roadmap pour l'outil lui-même. Fichiers .md dans backlog/planned/in-progress/done.
