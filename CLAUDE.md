# CLAUDE.md — Autonome Agent

## Projet

Autonome Agent est un **meta-outil** : un orchestrateur bash qui pilote Claude Code CLI en boucle autonome pour construire des produits logiciels de A à Z. C'est le projet de l'outil lui-même, pas un projet généré par l'outil.

## Stack

- **Bash** (bash 5+) — orchestrateur principal (`orchestrator.sh`, `init.sh`)
- **Markdown** — prompts des phases (`phases/*.md`), skills (`skills-templates/*.md`)
- **JSON** — tracking tokens (`logs/tokens.json`), état (`logs/state.json`)
- **jq** — parsing JSON (dépendance optionnelle, dégradation gracieuse si absent)
- **Claude Code CLI** — `claude -p` en mode non-interactif avec `--dangerously-skip-permissions`
- **GitHub CLI** (`gh`) — création de repos dans `init.sh`

## Architecture

```
orc/                         ← CE REPO (template, jamais modifié par un projet)
├── orc.sh                   ← CLI unifiée : point d'entrée unique (orc agent|roadmap|admin)
├── orc-agent.sh             ← Sous-commandes projets (new, start, stop, status, logs, roadmap)
├── orc-admin.sh             ← Sous-commandes admin (config, model, budget, key, version)
├── orchestrator.sh          ← Boucle principale : bootstrap → research → strategy → feature loop → evolve
├── agent.sh                 ← CLI legacy (compatibilité, redirige vers orc)
├── init.sh                  ← Wizard interactif : crée un workspace SÉPARÉ (../mon-projet/)
├── config.default.sh        ← Template de config (copié et personnalisé par init.sh)
├── phases/                  ← Prompts Markdown avec placeholders {{VAR}} pour chaque phase
├── skills-templates/        ← Skills copiées dans project/.claude/skills/ au bootstrap
├── roadmap/                 ← Items de roadmap structurés (backlog → planned → in-progress → done)
│   ├── backlog/             ← Idées non priorisées
│   ├── planned/             ← Priorisées, prêtes à implémenter
│   ├── in-progress/         ← En cours de développement
│   └── done/                ← Terminées
├── BRIEF.template.md        ← Template de brief produit
├── ARCHITECTURE.md          ← Documentation complète du système
└── README.md                ← Mode d'emploi
```

**Le workspace créé par init.sh :**
```
../mon-projet/               ← Auto-contenu, indépendant du template
├── orchestrator.sh          ← Copie
├── BRIEF.md                 ← Brief produit
├── phases/, skills-templates/
├── .orc/                    ← État orchestrateur (partiellement gitté)
│   ├── config.sh            ← Personnalisé (gitté)
│   ├── state.json           ← Runtime (ignoré)
│   ├── tokens.json          ← Coûts (ignoré)
│   ├── .lock                ← Lockfile (ignoré)
│   ├── .pid                 ← PID du process (ignoré)
│   ├── tracking-issue       ← Numéro issue GitHub de tracking (ignoré)
│   └── logs/                ← Logs orchestrateur (ignoré)
└── project/                 ← Code produit (son propre git)
```

## Commandes

### CLI unifiée (`orc`)
- `orc agent new|start|stop|status|logs <nom>` — gestion des projets
- `orc roadmap [--detail|--full] [--priority P1] [--tag x]` — suivi roadmap
- `orc admin config|model|budget|key|version` — administration
- `orc s` / `orc r` / `orc l <nom>` — raccourcis (status, roadmap, logs)

### Développement
- `bash -n orchestrator.sh` — vérifier la syntaxe sans exécuter
- `bash -n orc.sh && bash -n orc-agent.sh && bash -n orc-admin.sh` — vérifier toute la CLI
- `shellcheck orchestrator.sh` — lint statique (si shellcheck installé)
- Pas de test framework — la validation se fait par dry-run sur un projet réel

## Conventions

- **Bash strict mode** : `set -euo pipefail` en haut de chaque script
- **Pas de `cd` nu** : utiliser `run_in_project()` (subshell) pour exécuter dans project/
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

## Patterns importants

### run_claude()
Point central — lance Claude en background, monitore le heartbeat, détecte les stalls, enforce le timeout, track les tokens. Toute modification ici impacte tout le système.

### render_phase()
Substitue `{{VAR}}` dans les prompts. Attention : la substitution bash `${content//pattern/replacement}` casse si `replacement` contient `/` ou `\`. Pour les outputs build/test, utiliser `write_fix_prompt()` à la place.

### Reprise après crash
Séquence de guards : `CLAUDE.md` existe ? → skip bootstrap. `INDEX.md` existe ? → skip research. Features non-cochées dans ROADMAP ? → skip strategy. `state.json` → restaure les compteurs.

### Contrôle humain mid-run
- `.orc/human-notes.md` : lu et injecté dans le prompt avant chaque feature
- `.orc/pause-requested` / `.orc/stop-after-feature` : signaux file-based pour le mode nohup
- `logs/human-feedback-N.md` : feedback structuré, prioritaire sur les observations de l'IA

### GitHub Integration (`GIT_STRATEGY`)
Deux modes : `local` (défaut, merge direct) et `pr` (GitHub Pull Requests).
- **Mode `pr`** : chaque feature crée une PR via `gh`, attend review si `REQUIRE_HUMAN_APPROVAL=true`, merge via GitHub, fallback local si échec.
- **Tracking issue** : `GITHUB_TRACKING_ISSUE=true` crée une issue "ORC Run" au bootstrap, commentée à chaque feature (début/fin/abandon), fermée en fin de run.
- **Signaux GitHub** : `GITHUB_SIGNALS=true` lit les labels `orc:pause`, `orc:stop`, `orc:continue` sur la tracking issue dans `check_signals()`.
- **Features abandonnées** : auto-création d'une issue "bug" avec les fix-reflections quand une feature est abandonnée.
- **Dégradation gracieuse** : si `gh` absent ou non authentifié, tout fonctionne en mode local.
- Fonctions : `gh_available()`, `gh_pr_mode()`, `gh_create_tracking_issue()`, `gh_create_pr()`, `gh_merge_pr()`, `gh_comment()`, `gh_check_signals()`, `gh_create_abandoned_issue()`, `gh_close_tracking_issue()`.

### Détection de boucle fix
`error_hash()` compare les erreurs entre tentatives. Même erreur 2x → prompt "change d'approche". 3x → abandon anticipé.

### Quality gate
`QUALITY_COMMAND` exécuté après tests, avant merge. Non-bloquant si échec après correction.

### Mémoire inter-projets
`learnings/` dans le template accumule les insights. Copiés dans le projet au bootstrap, lus par la phase 00.

### Connaissance projet (codebase/ + stack-conventions.md)
- `codebase/INDEX.md` : carte sémantique du projet (max 40 lignes). Lu AVANT chaque implémentation. Pointe vers les fichiers de détail.
- `codebase/auto-map.md` : carte auto-générée par l'orchestrateur (grep des exports/classes). Vérité du code, pas maintenue par l'IA. Regénérée avant chaque feature.
- `codebase/modules.md`, `utilities.md`, `integrations.md`, `data-models.md`, `architecture.md`, `security.md` : détail par domaine. L'IA ne lit que les fichiers pertinents pour la feature en cours.
- `.claude/skills/stack-conventions.md` : conventions spécifiques à la stack (React, Astro, Java, etc.), patterns adoptés, anti-patterns, utilities réutilisables, patterns de sécurité. Auto-enrichi au fil du projet.

### Réflexions structurées (pattern Reflexion)
Après chaque échec de fix, l'IA écrit une réflexion structurée dans `logs/fix-reflections-N.md` (ce que j'ai tenté, pourquoi ça a échoué, ce que je dois essayer). Ces réflexions sont injectées dans les tentatives suivantes.

### Contexte adaptatif par phase
`run_claude()` injecte un contexte différent selon la phase :
- implement → INDEX.md + auto-map.md + fichiers de détail pertinents + stack-conventions.md
- fix → auto-map.md + security.md + réflexions passées
- strategy → INDEX.md + architecture.md + research/INDEX.md
- reflect → auto-map.md (vérité) + INDEX.md + fichiers de détail à mettre à jour
- meta-retro → INDEX.md + auto-map.md + audit de cohérence de tous les fichiers

## Roadmap

Les items de roadmap sont des fichiers `.md` individuels dans `roadmap/`.
Le statut est déterminé par le sous-dossier (`backlog/`, `planned/`, `in-progress/`, `done/`).

Chaque item a un frontmatter YAML avec : `id`, `priority` (P0-P3), `type`, `effort` (XS-XL), `tags`, `epic`, `depends`.

- **Consulter** : `agent roadmap` (compact), `--detail`, `--full`
- **Filtrer** : `--priority P1`, `--tag adoption`, `--epic adopt-mode`
- **Créer un item** : copier `roadmap/TEMPLATE.md`, incrémenter l'ID
- **Changer de statut** : `mv roadmap/planned/ROADMAP-NNN.md roadmap/in-progress/`
- **Skill** : `skills-templates/roadmap-item.md` guide la création pendant les rétrospectives

## Version actuelle

v0.5.0 — Production-ready
