# ORC — Phases d'orchestration

## Phase 00 — Bootstrap (phases/00-bootstrap.md)
- Placeholders : aucun
- Crée : CLAUDE.md, codebase/, skills, ROADMAP.md vide
- Lit : BRIEF.md, learnings/
- Guard : skip si CLAUDE.md existe

## Phase 01 — Research (phases/01-research.md)
- Placeholders : aucun
- Crée : research/{competitors,trends,user-needs,regulations}/*.md, INDEX.md, SYNTHESIS.md
- Cross-validation : confidence high/medium/low, 2 sources min
- Guard : skip si research/INDEX.md existe

## Phase 02 — Strategy (phases/02-strategy.md)
- Placeholders : aucun
- Crée : ROADMAP.md structuré en epics
- Guard : skip si ROADMAP a des items non cochés

## Phase 03 — Implement (phases/03-implement.md)
- Placeholders : {{FEATURE_NAME}}, {{FEATURE_BRANCH}}
- Lit : codebase/INDEX.md, auto-map.md, stack-conventions.md, research/
- Checklist anti-duplication obligatoire

## Phase 04 — Test-Fix (phases/04-test-fix.md)
- Placeholders : {{ATTEMPT}}, {{MAX_FIX}}, {{BUILD_EXIT}}, {{BUILD_OUTPUT}}, {{TEST_EXIT}}, {{TEST_OUTPUT}}
- Note : construit via write_fix_prompt(), pas render_phase()

## Phase 05 — Reflect (phases/05-reflect.md)
- Placeholders : {{FEATURE_NAME}}, {{TESTS_PASSED}}, {{FIX_ATTEMPTS}}, {{N}}
- Met à jour : codebase/*.md, INDEX.md, stack-conventions.md, CLAUDE.md, skills, ROADMAP.md
- Écrit : logs/retrospective-N.md

## Phase 06 — Meta-Retro (phases/06-meta-retro.md)
- Placeholders : {{FEATURE_COUNT}}
- Fréquence : tous les META_RETRO_FREQUENCY features
- Inclut : WebSearch veille, repriorisation, nettoyage, audit codebase/

## Phase 07 — Evolve (phases/07-evolve.md)
- Placeholders : aucun
- Garde-fous : MAX_EVOLVE_CYCLES, MAX_AI_ROADMAP_ADDS, alignement BRIEF
- Option A : ajoute features → relance boucle (exec $0)
- Option B : crée DONE.md → fin
