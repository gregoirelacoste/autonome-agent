# orc — Agent Autonome Claude

Un orchestrateur qui pilote Claude Code en boucle autonome pour construire un produit de A à Z : veille marché, roadmap, développement, tests, corrections et auto-amélioration.

## Prérequis

- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) installé
- Clé API Anthropic (`ANTHROPIC_API_KEY`)
- Git
- Node.js 22+
- [GitHub CLI](https://cli.github.com/) (`gh`) — optionnel, pour l'intégration GitHub
- `jq` — optionnel, pour le tracking des coûts

## Installation

### Sur ta machine

```bash
git clone git@github.com:gregoirelacoste/orc.git
cd orc
```

Rendre `orc` disponible partout :

```bash
# Option 1 : symlink (recommandé)
sudo ln -sf "$(pwd)/orc.sh" /usr/local/bin/orc

# Option 2 : alias dans ~/.bashrc ou ~/.zshrc
echo "alias orc='$(pwd)/orc.sh'" >> ~/.zshrc
source ~/.zshrc
```

Configurer ta clé API :

```bash
# Créer un .env dans le dossier orc/
echo 'export ANTHROPIC_API_KEY="sk-ant-..."' > .env
```

### Sur un VPS (Ubuntu 22+ / Debian 12+)

Le script installe tout (Node.js, Claude CLI, orc) et rend `orc` disponible globalement :

```bash
ssh root@<vps-ip> 'bash -s' < deploy.sh
```

## Démarrage rapide

### 1. Créer un projet

```bash
./orc.sh agent new mon-projet
```

Claude te pose ~22 questions pour rédiger le brief produit (`BRIEF.md`).
Le workspace est créé dans `~/projects/mon-projet/`.

Si tu as déjà un brief (Claude le lit, pose des questions, l'enrichit) :

```bash
./orc.sh agent new mon-projet --brief briefs/mon-brief.md
```

Sans clarification (copie le brief tel quel) :

```bash
./orc.sh agent new mon-projet --brief briefs/mon-brief.md --no-clarify
```

### 2. Configurer (optionnel)

Avant de lancer, tu peux ajuster la config du projet :

```bash
vim ~/projects/mon-projet/.orc/config.sh
```

Les paramètres clés :

| Paramètre | Défaut | Description |
|---|---|---|
| `MAX_FEATURES` | 50 | Nombre total de features avant arrêt |
| `MAX_FIX_ATTEMPTS` | 3 | Tentatives de fix par feature |
| `MAX_BUDGET_USD` | 200.00 | Budget max en USD (prédictif + post-hoc) |
| `REQUIRE_HUMAN_APPROVAL` | false | Valider chaque merge manuellement |
| `PAUSE_EVERY_N_FEATURES` | 0 | Pause toutes les N features (0 = jamais) |
| `BUILD_COMMAND` | `npm run build` | Commande de build |
| `TEST_COMMAND` | `npx playwright test` | Commande de test |
| `DEPLOY_COMMAND` | *(vide)* | Déploiement auto en fin de projet |
| `CLAUDE_MODEL` | *(défaut CLI)* | Modèle principal (implement, fix, critic) |
| `CLAUDE_MODEL_LIGHT` | `claude-haiku-4-5` | Modèle léger (plan, reflect, research) |
| `CLAUDE_MODEL_STRONG` | `claude-opus-4-6` | Modèle fort (challenger) |
| `ENABLE_CHALLENGER` | `true` | Enrichissement produit avant chaque feature |
| `ENABLE_PRODUCT_REVIEW` | `true` | Autocritique métier après chaque feature |
| `STALL_KILL_THRESHOLD` | 60 | Checks sans données avant kill auto (x5s) |

Voir `config.default.sh` pour la liste complète.

### 3. Lancer

```bash
./orc.sh agent start mon-projet
```

L'orchestrateur tourne en background. Le code est généré dans `~/projects/mon-projet/`.

### 4. Suivre l'avancement

```bash
./orc.sh s                     # Vue d'ensemble de tous les projets
./orc.sh s mon-projet          # Détail d'un projet (features, coût, roadmap)
./orc.sh l mon-projet          # Logs en temps réel (tail -f)
./orc.sh r                     # Roadmap orc
```

### 5. Intervenir en cours de route

```bash
# Injecter des notes que Claude lira avant la prochaine feature
vim ~/projects/mon-projet/.orc/human-notes.md

# Demander une pause après la feature en cours
touch ~/projects/mon-projet/.orc/pause-requested

# Arrêter proprement après la feature en cours
touch ~/projects/mon-projet/.orc/stop-after-feature

# Sauter la feature en cours (passe à la suivante)
touch ~/projects/mon-projet/.orc/skip-feature

# Arrêt immédiat
./orc.sh agent stop mon-projet
```

## Modes d'autonomie

Configurables dans `.orc/config.sh` :

| Mode | Config | Comportement |
|---|---|---|
| **Pilote auto** | `PAUSE=0, APPROVAL=false` | 100% autonome — prototypes, exploration |
| **Copilote** | `PAUSE=0, APPROVAL=true` | Claude code, tu valides chaque merge |
| **Supervisé** | `PAUSE=3, APPROVAL=false` | Pause toutes les 3 features pour review |

## Commandes

### Projets

```bash
orc agent new <nom>                    # Créer un projet (wizard interactif)
orc agent new <nom> --brief x.md      # Brief existant + clarification IA
orc agent new <nom> --brief x.md --no-clarify  # Brief direct
orc agent new <nom> --github           # Créer + repo GitHub
orc agent github <nom>                 # Créer le repo GitHub après coup
orc agent start <nom>                  # Lancer en background
orc agent stop <nom>                   # Arrêter proprement
orc agent restart <nom>                # Redémarrer
orc agent status                       # Vue d'ensemble
orc agent status <nom>                 # Détail d'un projet
orc agent logs <nom>                   # Logs temps réel
orc agent logs <nom> --full            # Log complet (less)
orc agent update                       # Mettre à jour orc (git pull)
```

### Administration

```bash
orc admin config                       # Config globale
orc admin model                        # Modèle Claude actuel + tarifs
orc admin model set <model-id>         # Changer le modèle
orc admin budget                       # Coûts détaillés par projet
orc admin key                          # Voir les clés API
orc admin key set <key>                # Configurer clé Anthropic
orc admin version                      # Version + vérification dépendances
```

### Raccourcis

```bash
orc s              # → orc agent status
orc s <nom>        # → orc agent status <nom>
orc dash <nom>     # → orc dashboard <nom>
orc l <nom>        # → orc agent logs <nom>
orc r              # → orc roadmap
```

## Comment ça marche

```
BRIEF.md (immuable)
    │
    ▼
BOOTSTRAP ──▶ RECHERCHE INITIALE ──▶ STRATÉGIE & ROADMAP
                                           │
                                           ▼
                                    ┌──────────────────┐
                                    │   BOUCLE x N     │
                                    │                  │
                                    │ Veille ciblée    │
                                    │ Challenger (Opus)│
                                    │ Plan (micro)     │
                                    │ Implement        │
                                    │ Lint             │
                                    │ Critic (review)  │
                                    │ Tests & Fix      │
                                    │ Product Review   │
                                    │ Acceptance (epic) │
                                    │ Tech-Debt (>30%) │
                                    │ Reflect          │
                                    └──────┬───────────┘
                                           │
                                  toutes les N features
                                           │
                                           ▼
                                    MÉTA-RÉTROSPECTIVE
                                    Repriorisation
                                           │
                                           ▼
                                    EVOLVE (maturité /30)
                                    >= 24 → DONE + deploy
                                    < 24  → nouvelles features
```

L'agent améliore ses propres outils au fil du projet :
- **CLAUDE.md** du projet — ajoute des règles quand il découvre des pièges
- **Skills** — crée de nouveaux workflows quand un pattern se répète
- **ROADMAP.md** — ajoute/repriorise des features après chaque veille

## Structure d'un workspace

```
~/projects/mon-projet/       ← Repo git unique
├── BRIEF.md                 ← Brief produit (source de vérité, immuable)
├── orchestrator.sh          → symlink vers orc/
├── phases/                  → symlink vers orc/
├── CLAUDE.md                ← Auto-généré et auto-amélioré
├── .claude/skills/          ← Skills de l'agent
├── .orc/                    ← État orchestrateur + artéfacts
│   ├── config.sh            ← Configuration du projet
│   ├── BRIEF.md             ← Copie du brief
│   ├── ROADMAP.md           ← Roadmap features
│   ├── codebase/            ← Carte sémantique du code
│   ├── research/            ← Veille marché
│   ├── known-issues.md      ← Mémoire inter-features (auto)
│   ├── state.json           ← State machine, compteurs, timeline
│   ├── tokens.json          ← Coûts, métriques par modèle/phase
│   └── logs/                ← Logs orchestrateur
├── src/                     ← Code applicatif
└── README.md                ← Doc produit
```

## GitHub (optionnel)

Tout fonctionne en local sans GitHub. Chaque option est indépendante et off par défaut dans `.orc/config.sh` :

| Option | Description |
|---|---|
| `GIT_STRATEGY="pr"` | Créer des Pull Requests au lieu de merge direct |
| `GITHUB_TRACKING_ISSUE=true` | Issue de suivi commentée à chaque feature |
| `GITHUB_SIGNALS=true` | Contrôle via labels (`orc:pause`, `orc:stop`) |
| `GITHUB_SYNC_ROADMAP=true` | Miroir ROADMAP → GitHub Issues |
| `GITHUB_FEEDBACK=true` | Lire les commentaires GitHub comme feedback |
| `GITHUB_CI=true` | Valider les checks GitHub Actions |
| `GITHUB_RELEASES=true` | Créer des releases automatiques |

## FAQ

**Le workspace est-il un repo git ?**
Oui. Le workspace est directement le repo git du projet.

**Je peux lancer plusieurs projets en parallèle ?**
Oui. Chaque projet est indépendant. `orc s` les affiche tous.

**Reprendre après un crash ?**
L'orchestrateur détecte l'état existant et reprend automatiquement (`orc agent start <nom>`).

**Combien ça coûte ?**
~50-100K tokens par feature. Un projet de 10 features ≈ 500K-1M tokens. Suivre avec `orc admin budget`.

**Modifier les prompts ?**
Oui. Éditer les fichiers dans `~/projects/mon-projet/phases/`. Chaque phase est un prompt Markdown avec des placeholders `{{VAR}}`.

**Changer de modèle Claude ?**
`orc admin model set claude-sonnet-4-6` — appliqué aux prochains lancements.

## Documentation

### Guides utilisateur (dans `docs/`)

- [Démarrage rapide](docs/getting-started.md) — Installation et premier projet
- [Modes d'init](docs/init-modes.md) — Wizard, brief + clarification, brief direct, template
- [Référence CLI](docs/commands-reference.md) — Toutes les commandes avec exemples
- [Configuration](docs/configuration.md) — Paramètres, modes d'autonomie
- [Intégration GitHub](docs/github-integration.md) — PRs, tracking, signals, CI, releases
- [Contrôle humain](docs/human-controls.md) — Pause, stop, notes, feedback
- [FAQ & Troubleshooting](docs/faq.md) — Questions fréquentes et résolution de problèmes

### Documentation technique

- [ARCHITECTURE.md](ARCHITECTURE.md) — Architecture technique complète
- [ROADMAP.md](ROADMAP.md) — Historique des versions et roadmap d'orc
- [codebase/INDEX.md](codebase/INDEX.md) — Carte sémantique du code
