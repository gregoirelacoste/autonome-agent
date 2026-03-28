# ORC — Phases d'orchestration

## Phase 00 — Bootstrap (phases/00-bootstrap.md)
- Placeholders : aucun
- Crée : CLAUDE.md, codebase/, skills, ROADMAP.md vide
- Lit : BRIEF.md, learnings/
- Guard : skip si CLAUDE.md existe
- Modèle : principal

## Phase 01 — Research (phases/01-research.md)
- Placeholders : aucun
- Crée : research/{competitors,trends,user-needs,regulations}/*.md, INDEX.md, SYNTHESIS.md
- Cross-validation : confidence high/medium/low, 2 sources min
- Guard : skip si research/INDEX.md existe
- Modèle : léger

## Phase 02 — Strategy (phases/02-strategy.md)
- Placeholders : aucun
- Crée : ROADMAP.md structuré en epics
- Guard : skip si ROADMAP a des items non cochés
- Modèle : léger

## Phase 03a — Plan (phases/03a-plan.md)
- Placeholders : {{FEATURE_NAME}}, {{N}}
- Crée : .orc/logs/plan-N.md (fichiers à modifier, interfaces, tests, risques)
- Max 5 turns, modèle léger
- Injecté dans le prompt d'implémentation

## Phase 03 — Implement (phases/03-implement.md)
- Placeholders : {{FEATURE_NAME}}, {{FEATURE_BRANCH}}
- Lit : codebase/INDEX.md, auto-map.md, stack-conventions.md, research/
- Contexte : INDEX.md + auto-map.md injectés directement (pas de tool call)
- Checklist anti-duplication obligatoire
- Modèle : principal

## Phase 03b — Critic (phases/03b-critic.md)
- Placeholders : {{FEATURE_NAME}}
- Review adversariale : --append-system-prompt avec persona "reviewer senior sceptique"
- Lit : git diff main...HEAD
- Corrige max 3 bugs, modèle principal, 10 turns max
- Multi-agent : persona distinct du coder

## Lint (pas de fichier phase, intégré à orchestrator.sh)
- Exécute LINT_COMMAND entre implement et critic
- Fix auto par Claude (10 turns) si échec

## Phase 04 — Test-Fix (phases/04-test-fix.md + write_fix_prompt())
- Placeholders : {{ATTEMPT}}, {{MAX_FIX}}, {{BUILD_EXIT}}, {{BUILD_OUTPUT}}, {{TEST_EXIT}}, {{TEST_OUTPUT}}
- Note : construit via write_fix_prompt(), pas render_phase()
- Réflexion structurée intégrée au prompt de fix (pas d'invocation séparée)
- known-issues.md injecté pour mémoire inter-features

## Phase 05 — Reflect (phases/05-reflect.md)
- Placeholders : {{FEATURE_NAME}}, {{TESTS_PASSED}}, {{FIX_ATTEMPTS}}, {{N}}
- Met à jour : codebase/*.md, INDEX.md, stack-conventions.md, CLAUDE.md, skills, ROADMAP.md
- Écrit : logs/retrospective-N.md
- Modèle : léger

## Phase 06 — Meta-Retro (phases/06-meta-retro.md)
- Placeholders : {{FEATURE_COUNT}}
- Fréquence : tous les META_RETRO_FREQUENCY features
- Inclut : WebSearch veille, repriorisation, nettoyage, audit codebase/
- Modèle : léger

## Phase 07 — Evolve (phases/07-evolve.md)
- Placeholders : aucun
- Garde-fous : MAX_EVOLVE_CYCLES, MAX_AI_ROADMAP_ADDS, alignement BRIEF
- Option A : ajoute features → relance boucle (while loop interne)
- Option B : crée DONE.md → fin
- Modèle : léger
