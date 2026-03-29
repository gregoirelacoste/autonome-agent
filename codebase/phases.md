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
- Crée : ROADMAP.md structuré en epics (MVP 5-8 features + améliorations optionnelles, max 15 total)
- Brief scoring : 5 critères (clarté, scope, stack, succès, users) /25. Si < 15, ajoute des hypothèses
- Guard : skip si ROADMAP a des items non cochés
- Modèle : léger

## Phase 03c — Challenger (phases/03c-challenger.md)
- Placeholders : {{FEATURE_NAME}}, {{N}}
- Crée : .orc/logs/challenger-N.md (enrichissements immédiats + idées futures)
- Max 3 turns, modèle fort (`CLAUDE_MODEL_STRONG`, défaut Opus)
- Exécutée AVANT le plan pour chaque feature
- Analyse produit sous 6 angles : complétude, edge cases, UX, cohérence, sécurité, performance
- Contexte : tout pré-injecté (INDEX.md, auto-map.md, BRIEF, ROADMAP, research) — zéro lecture fichier
- Lookahead parallèle : challenger de feature N+1 en arrière-plan (subshell isolée) pendant lint/critic/test/reflect de N
- Config : `ENABLE_CHALLENGER=true` (on/off), `MAX_TURNS_CHALLENGER=3`
- Guard : skip si challenger-N.md existe (crash recovery)

## Phase 03a — Plan (phases/03a-plan.md)
- Placeholders : {{FEATURE_NAME}}, {{N}}
- Crée : .orc/logs/plan-N.md (fichiers à modifier, interfaces, tests, risques)
- Max 5 turns, modèle léger
- Si un challenger a été exécuté, ses enrichissements sont injectés dans le prompt du plan
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

## Phase 04b — Acceptance (phases/04b-acceptance.md)
- Placeholders : {{EPIC_NUMBER}}, {{FEATURE_COUNT}}, {{DEV_COMMAND}}
- Déclenchée : après chaque epic (toutes les EPIC_SIZE features)
- Valide les user stories du BRIEF de bout en bout
- Écrit : .orc/logs/acceptance-N.md (score X/Y scénarios passés)
- Corrige max 5 problèmes critiques directement
- Modèle : principal

## Phase 04c — QA (phases/04c-qa.md)
- Placeholders : {{EPIC_NUMBER}}, {{FEATURE_COUNT}}, {{PORT}}
- Déclenchée : après acceptance, si DEV_COMMAND est configurée
- Teste l'app réellement : discovery routes, curl health check, fix 500, Playwright si dispo
- Étapes bash à zéro tokens (curl) + IA pour diagnostic/fix uniquement
- Écrit : .orc/logs/qa-report-N.md + .orc/logs/qa-screenshot-*.png
- Max 5 fixes, max 5 scénarios navigateur, max 5 screenshots
- Timeout : 10min. Modèle : principal (corrige du code)

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

## Phase 06b — Tech-Debt (phases/06b-tech-debt.md)
- Placeholders : {{FEATURE_COUNT}}, {{TOTAL_FAILURES}}
- Déclenchée : quand >30% des features ont échoué (seuil de dette)
- Diagnostic : fichiers trop gros, duplication, imports circulaires, tests fragiles, code mort
- Max 5 refactorings, tous les tests doivent passer
- Met à jour : codebase/*.md après refactoring
- Modèle : principal

## Phase 07 — Evolve (phases/07-evolve.md)
- Placeholders : aucun
- Garde-fous : MAX_EVOLVE_CYCLES, MAX_AI_ROADMAP_ADDS, alignement BRIEF
- Score de maturité : 6 critères /30 (parcours user, CRUD, erreurs, UX, tests, doc)
- Score >= 24 → DONE, >= 18 → 3 features ciblées, < 18 → corrections prioritaires
- Option A : ajoute features → phase 07b alignment → arrêt (si ALIGNMENT_CHECK=true) ou relance
- Option B : crée DONE.md → fin
- Modèle : léger

## Phase 07b — Alignment (phases/07b-alignment.md)
- Placeholders : CYCLE
- Déclenchement : après evolve Option A (nouvelles features), si ALIGNMENT_CHECK=true
- Génère `.orc/logs/alignment-report-N.md` : état actuel, écarts brief, propositions
- Le run s'arrête en état `alignment_pending` après cette phase
- Au prochain `orc agent start` : wizard interactif (5 questions ciblées)
- Réponses dans `.orc/logs/alignment-response-N.md`, injectées dans les features suivantes
- Modèle : léger, timeout 2min
