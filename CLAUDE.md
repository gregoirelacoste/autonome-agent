# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Projet

Autonome Agent est un **meta-outil** : un orchestrateur bash qui pilote Claude Code CLI en boucle autonome pour construire des produits logiciels de A à Z. C'est le projet de l'outil lui-même, pas un projet généré par l'outil.

## Stack

- **Bash** (bash 5+) — orchestrateur principal (`orchestrator.sh`, `init.sh`)
- **Markdown** — prompts des phases (`phases/*.md`), skills (`skills-templates/*.md`)
- **JSON** — tracking tokens (`.orc/tokens.json`), état (`.orc/state.json`)
- **jq** — parsing JSON (dépendance optionnelle, dégradation gracieuse si absent)
- **Claude Code CLI** — `claude -p` en mode non-interactif avec `--dangerously-skip-permissions`
- **GitHub CLI** (`gh`) — optionnel, pour création de repos et intégration GitHub

## Architecture

```
orc/                         ← CE REPO (template, jamais modifié par un projet)
├── orc.sh                   ← CLI unifiée : point d'entrée unique (orc agent|roadmap|admin)
├── orc-agent.sh             ← Sous-commandes projets (new, start, stop, status, logs, roadmap)
├── orc-admin.sh             ← Sous-commandes admin (config, model, budget, key, version)
├── orchestrator.sh          ← Boucle principale (2300+ lignes) : bootstrap → research → strategy → feature loop → evolve
├── agent.sh                 ← CLI legacy (compatibilité, redirige vers orc)
├── init.sh                  ← Wizard interactif : crée un workspace SÉPARÉ (../mon-projet/)
├── deploy.sh                ← Script d'installation VPS (Ubuntu 22+ / Debian 12+, idempotent)
├── config.default.sh        ← Template de config (copié et personnalisé par init.sh)
├── phases/                  ← Prompts Markdown avec placeholders {{VAR}} pour chaque phase (00-07)
├── skills-templates/        ← Skills copiées dans .claude/skills/ au bootstrap
├── codebase/                ← Documentation structurée du système orc lui-même (INDEX.md, functions.md, etc.)
├── docs/                    ← Documentation utilisateur : guides, tutos, FAQ (→ docs/INDEX.md)
├── learnings/               ← Insights inter-projets, copiés au bootstrap, lus par phase 00
├── briefs/                  ← Exemples de briefs produit
├── roadmap/                 ← Items de roadmap structurés (backlog → planned → in-progress → done)
├── BRIEF.template.md        ← Template de brief produit
├── ROADMAP.md               ← Historique des versions et roadmap globale
└── ARCHITECTURE.md          ← Documentation complète du système
```

**Le workspace créé par `orc agent new` :**
```
../mon-projet/               ← Repo git unique, structure aplatie
├── orchestrator.sh          → symlink vers orc/orchestrator.sh
├── phases/                  → symlink vers orc/phases/
├── BRIEF.md                 ← Brief produit
├── CLAUDE.md                ← Auto-généré par l'orchestrateur
├── .claude/skills/          ← Skills agent (enrichies au fil du run)
├── .orc/                    ← État orchestrateur + artéfacts (partiellement gitté)
│   ├── config.sh            ← Personnalisé (gitté)
│   ├── BRIEF.md             ← Copie du brief (gitté)
│   ├── ROADMAP.md           ← Roadmap features (gitté)
│   ├── codebase/            ← Doc technique pour l'IA (gitté)
│   ├── research/            ← Veille marché (gitté)
│   ├── state.json           ← Runtime (ignoré)
│   ├── tokens.json          ← Coûts (ignoré)
│   ├── .lock, .pid          ← Runtime (ignoré)
│   └── logs/                ← Logs orchestrateur (ignoré)
├── src/                     ← Code applicatif
├── README.md                ← Doc produit
└── ...
```

## Commandes

### CLI unifiée (`orc`)
- `orc agent new <nom> [--brief x.md] [--no-clarify] [--github [public]]` — créer un projet (wizard, brief+clarification, ou brief direct, optionnel: repo GitHub)
- `orc agent github <nom> [--public]` — créer le repo GitHub d'un projet existant
- `orc agent start|stop|status|logs <nom>` — gestion des projets
- `orc agent dashboard <nom>` — dashboard live avec progression, roadmap, activité (auto-refresh 5s)
- `orc roadmap [--detail|--full] [--priority P1] [--tag x]` — suivi roadmap
- `orc admin config|model|budget|key|version` — administration
- `orc docs [sujet]` — documentation utilisateur
- `orc s` / `orc r` / `orc l <nom>` / `orc dash <nom>` — raccourcis (status, roadmap, logs, dashboard)

### Développement
- `bash -n orchestrator.sh` — vérifier la syntaxe sans exécuter
- `bash -n orc.sh && bash -n orc-agent.sh && bash -n orc-admin.sh` — vérifier toute la CLI
- `shellcheck orchestrator.sh` — lint statique (si shellcheck installé)
- Pas de test framework — la validation se fait par dry-run sur un projet réel

## Conventions

- **Bash strict mode** : `set -euo pipefail` en haut de chaque script
- **Pas de `cd` nu** : utiliser `run_in_project()` (subshell) pour exécuter dans `$PROJECT_DIR`
- **printf > echo -e** : pour la portabilité des couleurs
- **Chemins absolus** : `PROJECT_DIR` et `LOG_DIR` résolus au démarrage via `realpath`
- **Dégradation gracieuse** : si `jq` absent, le tracking tokens est désactivé (pas de crash)
- **Lockfile** : `.orc/.lock` avec PID pour empêcher l'exécution concurrente
- **Signal handling** : trap `EXIT INT TERM` pour cleanup (kill Claude, rm temp files, save state)
- **State persistence** : `.orc/state.json` sauvegardé après chaque feature pour reprise après crash
- **Dossier `.orc/`** : tout l'état orchestrateur (config, state, tokens, logs, lock, pid) est centralisé dans `.orc/`

## Règles de modification

- **Ne jamais casser la reprise** : le script doit pouvoir reprendre à tout moment (guards sur CLAUDE.md, INDEX.md, ROADMAP.md)
- **Ne jamais hardcoder de valeurs** : tout doit être dans `config.default.sh`
- **Les phases sont des fichiers séparés** : modifier un prompt = modifier un fichier .md, pas le bash
- **Placeholders** : `{{VAR}}` dans les phases, substitués par `render_phase()`
- **Pas de données projet ici** : le template ne contient jamais de BRIEF.md ou config.sh spécifique
- **Tester la syntaxe** : `bash -n orchestrator.sh` avant chaque commit
- **Documenter les changements** : après chaque modification, utiliser le skill `/maintain-docs` pour mettre à jour la doc impactée (docs/, README, help CLI). Lire `docs/INDEX.md` d'abord pour savoir quoi toucher.

## Skills de développement (.claude/skills/)

Skills Claude Code disponibles pour travailler sur orc lui-même :

- `/test-orchestrator` — checklist de validation avant commit : syntaxe bash, shellcheck, cohérence config/phases/docs, dry-run mental
- `/maintain-docs` — mise à jour de la documentation après chaque changement (docs/, README, help CLI, CLAUDE.md)
- `/release` — process de release : pré-checks, semver (patch/minor/major), tag git, post-release
- `/add-phase` — ajouter une nouvelle phase au workflow : créer le prompt, intégrer dans orchestrator.sh, documenter, tester la reprise
- `/stack-conventions` — conventions de stack (template, copié dans les projets générés)

## Patterns importants

### run_claude()
Point central — lance Claude en background, monitore le heartbeat, détecte les stalls, enforce le timeout, track les tokens. Toute modification ici impacte tout le système.

### Modèle adaptatif par phase
`CLAUDE_MODEL` = modèle principal (implement, strategy, fix, bootstrap, research). `CLAUDE_MODEL_LIGHT` = modèle léger pour phases simples (reflection, reflect, self-improve, meta-retro, quality). `resolve_model()` choisit le modèle selon la phase. Si `CLAUDE_MODEL_LIGHT` est vide, toutes les phases utilisent `CLAUDE_MODEL`.

### Pricing dynamique
`MODEL_PRICING` (associative array) contient les tarifs par préfixe de modèle. `get_model_pricing()` résout le coût input/output pour le modèle effectif. Fallback sur tarif Sonnet si modèle inconnu.

### Budget prédictif
Avant chaque invocation, `run_claude()` estime le coût probable (~4000 tokens input + ~2000 output par turn) et refuse de lancer si le budget restant serait dépassé. Complète le check post-hoc existant.

### Stall kill auto
`STALL_KILL_THRESHOLD` (config, défaut 60 = 5min) : kill automatique si Claude ne produit aucune donnée pendant ce seuil. Complète le warning à 2min et le timeout global.

### Migration config auto
`migrate_config()` s'exécute au démarrage. Compare la config du projet (`.orc/config.sh`) avec `config.default.sh` du template orc. Ajoute automatiquement les paramètres manquants avec leurs valeurs par défaut. Permet aux projets existants de bénéficier des nouvelles options (CLAUDE_MODEL_LIGHT, PHASE_TIMEOUTS, etc.) sans intervention humaine.

### render_phase()
Substitue `{{VAR}}` dans les prompts. Attention : la substitution bash `${content//pattern/replacement}` casse si `replacement` contient `/` ou `\`. Pour les outputs build/test, utiliser `write_fix_prompt()` à la place.

### Reprise après crash
Séquence de guards : `CLAUDE.md` existe ? → skip bootstrap. `.orc/research/INDEX.md` existe ? → skip research. Features non-cochées dans `.orc/ROADMAP.md` ? → skip strategy. `state.json` → restaure les compteurs.

### Contrôle humain mid-run
- `.orc/human-notes.md` : lu et injecté dans le prompt avant chaque feature
- `.orc/pause-requested` / `.orc/stop-after-feature` / `.orc/skip-feature` : signaux file-based pour le mode nohup
- `.orc/logs/human-feedback-N.md` : feedback structuré, prioritaire sur les observations de l'IA

### Mémoire inter-features (known-issues.md)
`.orc/known-issues.md` : alimenté automatiquement quand un fix réussit après des échecs. Contient la réflexion qui a mené au fix. Injecté dans le prompt de fix des features suivantes pour ne pas répéter les mêmes erreurs.

### Review adversariale (critic) — multi-agent
`phases/03b-critic.md` — 10 turns max, modèle **principal** (pas léger). Exécutée entre implement+lint et les tests. Utilise un `--append-system-prompt` adversarial ("reviewer senior sceptique") distinct du coder pour éliminer le biais de confirmation. Review le diff vs main, corrige max 3 bugs AVANT le cycle de test coûteux.

### Apprentissage adaptatif des turns
`adaptive_max_turns()` calcule le max_turns optimal par phase basé sur l'historique réel (p75 + 30% marge). Stocké dans `tokens.json` (`by_phase.X.turns_history[]`). Après 3+ invocations d'une phase, le max_turns est réduit automatiquement si la phase utilise moins que prévu. Le défaut reste comme plafond. Évite de réserver 50 turns pour une phase qui en utilise 12.

### Lint pré-tests
Si `LINT_COMMAND` est défini, exécuté entre implement et la review adversariale. En cas d'échec, correction automatique par Claude (10 turns max) avant de lancer les tests.

### State machine (workflow_phase)
`WORKFLOW_PHASE` dans `state.json` pilote le workflow global. Transitions validées par `workflow_transition()` : init → bootstrap → research → strategy → features → evolve → features (cycle) → post-project → done. Les guards fichier existants (CLAUDE.md, ROADMAP.md, etc.) restent comme filet de sécurité. La reprise après crash utilise `WORKFLOW_PHASE` pour savoir où reprendre.

### GitHub Integration (local-first, GitHub-augmented)
**Principe** : local = source de vérité, GitHub = miroir de visibilité. Tout fonctionne sans GitHub. Chaque option est indépendante et off par défaut.
- **`GIT_STRATEGY`** : `local` (défaut, merge direct) | `pr` (GitHub PRs). Fallback local si PR échoue.
- **Tracking issue** : `GITHUB_TRACKING_ISSUE=true` crée une issue "ORC Run", commentée à chaque feature.
- **Signaux GitHub** : `GITHUB_SIGNALS=true` lit les labels `orc:pause`, `orc:stop`, `orc:continue`. Les signaux locaux (`.orc/`) fonctionnent toujours.
- **Roadmap sync** : `GITHUB_SYNC_ROADMAP=true` miroir push-only de ROADMAP.md → GitHub Issues. L'orchestrateur ne lit jamais les issues comme source de features.
- **Feedback GitHub** : `GITHUB_FEEDBACK=true` lit les commentaires humains sur la tracking issue.
- **CI distant** : `GITHUB_CI=true` attend les checks GitHub Actions après la quality gate. Non-bloquant — les tests locaux font toujours foi.
- **Releases** : `GITHUB_RELEASES=true` crée une release après chaque meta-rétro (`v0.N.0`) et en fin de projet (`v1.0.0`).
- **Dégradation gracieuse** : `gh` absent → tout fonctionne en local sans erreur.
- Fonctions préfixées `gh_*` dans `orchestrator.sh` — Phase 1 (PR/tracking), Phase 2 (roadmap sync/feedback), Phase 3 (CI/releases).

### Détection de boucle fix
`error_hash()` extrait les lignes contenant `error/fail/exception`, supprime les numéros de ligne, trie et hashe. Compare la structure de l'erreur (pas sa position). Même erreur 2x → prompt "change d'approche". 3x → abandon anticipé.

### Quality gate
`QUALITY_COMMAND` exécuté après tests, avant merge. Non-bloquant si échec après correction.

### Vérification fonctionnelle
`FUNCTIONAL_CHECK_COMMAND` exécuté après chaque merge de feature ET en fin de run. Garantit que l'app reste fonctionnelle à tout moment. Si échec : cycle de fix dédié, puis re-vérification. Résultat persisté dans `state.json` (`functional_check_passed`).

### Tracking enrichi (state.json)
`state.json` contient désormais : `current_feature`, `current_phase`, `phase_started_at`, `run_started_at`, `features_timeline[]` (historique avec status/timing/fix_attempts par feature), `functional_check_passed`, `run_status`, `run_ended_at`. Alimenté par `update_phase_tracking()`, `timeline_add()`, `timeline_update_last()`.

### Statut de sortie du run
`run_status` dans `state.json` distingue 4 états : `running` (en cours), `completed` (fin normale), `crashed` (erreur non rattrapée ou signal), `stopped` (arrêt demandé par l'utilisateur). Écrit par `cleanup()` (→ crashed si encore running), la fin du script (→ completed), ou les handlers de stop (→ stopped). Affiché dans `orc status`, `orc dashboard` via `get_run_status()` dans `orc-agent.sh`.

### Cochage fiable de ROADMAP.md
`mark_feature_done_bash()` coche la feature dans ROADMAP.md via `sed` après chaque merge réussi. Double sécurité avec le cochage par Claude en phase reflect.

### Dashboard live
`orc dashboard <projet>` (raccourci `orc dash`) affiche un dashboard live auto-refresh (5s) avec : barre de progression, feature en cours, coût, ETA, roadmap colorée, dernière activité. Basé sur la lecture de `state.json`, `tokens.json`, ROADMAP.md et `orchestrator.log`.

### Connaissance projet (.orc/codebase/ + stack-conventions.md)
- `.orc/codebase/INDEX.md` : carte sémantique du projet (max 40 lignes). Lu AVANT chaque implémentation.
- `.orc/codebase/auto-map.md` : carte auto-générée (grep des exports/classes). Regénérée avant chaque feature.
- Fichiers de détail par domaine : `modules.md`, `utilities.md`, `integrations.md`, `data-models.md`, `architecture.md`, `security.md`.
- `.claude/skills/stack-conventions.md` : conventions spécifiques à la stack, auto-enrichi au fil du projet.

### Structure aplatie du workspace
Le workspace est un repo git unique. `orchestrator.sh` et `phases/` sont des symlinks vers le template orc (mis à jour automatiquement). Les artéfacts orc sont isolés dans `.orc/` (BRIEF, ROADMAP, codebase, research, state, logs). Le code produit (src/, README, etc.) cohabite à la racine.

### Micro-phase plan (avant implement)
`phases/03a-plan.md` — 5 turns max, modèle léger. Produit `.orc/logs/plan-N.md` (fichiers à modifier, interfaces, tests, risques). Le plan est injecté dans le prompt d'implémentation. Détecte les erreurs de conception AVANT de coder → réduit les cycles de fix.

### Contexte adaptatif par phase (injection directe)
`run_claude()` pré-lit `INDEX.md` et `auto-map.md` côté bash et les injecte directement dans le prompt (évite les tool calls de lecture à ~100 tokens d'overhead). Contexte par phase :
- plan → INDEX.md + auto-map.md (injectés)
- implement → INDEX.md + auto-map.md (injectés) + fichiers de détail pertinents + stack-conventions.md (lus par Claude)
- fix → auto-map.md (injecté) + security.md + réflexions passées
- strategy → INDEX.md (injecté) + architecture.md + research/INDEX.md (lus par Claude)
- reflect → auto-map.md (injecté) + INDEX.md + fichiers de détail à mettre à jour
- meta-retro → INDEX.md + auto-map.md (injectés) + audit de cohérence

### Timeouts par phase
`PHASE_TIMEOUTS` (associative array optionnel dans config) surchage `CLAUDE_TIMEOUT` par phase. Permet de limiter les phases légères à 2-3min et les phases lourdes à 10-15min.

### Réflexions structurées (pattern Reflexion)
Après chaque échec de fix, l'IA écrit une réflexion structurée dans `.orc/logs/fix-reflections-N.md` (intégrée au prompt de fix, pas d'invocation séparée). Les réflexions sont injectées dans les tentatives suivantes.

### Phase acceptance (validation epic)
`phases/04b-acceptance.md` — exécutée après chaque epic (toutes les `EPIC_SIZE` features). Valide les user stories du BRIEF de bout en bout : lance l'app, teste les scénarios utilisateur, écrit un rapport `acceptance-N.md` avec score X/Y scénarios passés. Corrige max 5 problèmes critiques directement. Les problèmes non critiques vont en backlog.

### Brief scoring (MVP-first)
La phase strategy (`02-strategy.md`) score le brief sur 5 critères (clarté, scope, stack, succès, users) — note /25. Si score < 15/25, ajoute des hypothèses pour combler les manques. La roadmap est structurée en 2 phases : MVP (5-8 features max) + Améliorations (optionnel). Max 15 features totales. Le MVP doit être fonctionnel seul.

### Phase tech-debt (refactoring auto)
`phases/06b-tech-debt.md` — déclenchée quand >30% des features ont échoué (seuil de dette technique). Diagnostic : fichiers trop gros (>300 lignes), duplication, imports circulaires, tests fragiles, code mort, patterns incohérents. Max 5 refactorings, tous les tests doivent passer. Ne change pas le comportement visible. Met à jour `codebase/*.md` après le refactoring.

### Déploiement auto (DEPLOY_COMMAND)
`DEPLOY_COMMAND` dans config (vide par défaut). Exécuté en fin de projet si le run est complet et l'app fonctionnelle. Exemples : `scripts/deploy.sh`, `vercel deploy --prod`. Complète la chaîne : build → test → quality → functional check → deploy.

### Score de maturité produit
La phase evolve (`07-evolve.md`) évalue 6 critères /30 : parcours utilisateur complet, CRUD fonctionnel, gestion d'erreurs, UX cohérente, couverture de tests, documentation. Score >= 24/30 → DONE (projet terminé). Score >= 18 → 3 features ciblées. Score < 18 → corrections prioritaires. Remplace le critère arbitraire MAX_FEATURES comme signal d'arrêt intelligent.

## Roadmap

Les items de roadmap sont des fichiers `.md` individuels dans `roadmap/`.
Le statut est déterminé par le sous-dossier (`backlog/`, `planned/`, `in-progress/`, `done/`).

Chaque item a un frontmatter YAML avec : `id`, `priority` (P0-P3), `type`, `effort` (XS-XL), `tags`, `epic`, `depends`.

- **Consulter** : `agent roadmap` (compact), `--detail`, `--full`
- **Filtrer** : `--priority P1`, `--tag adoption`, `--epic adopt-mode`
- **Créer un item** : copier `roadmap/TEMPLATE.md`, incrémenter l'ID
- **Changer de statut** : `mv roadmap/planned/ROADMAP-NNN.md roadmap/in-progress/`

## Versioning

Version actuelle : **v0.6.0** (définie dans `orc.sh:ORC_VERSION`)

Semver : **patch** = bugfix/typo, **minor** = nouvelle feature/phase/skill, **major** = changement breaking (format config, structure workspace). Utiliser le skill `/release` pour le process complet.
