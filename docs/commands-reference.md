# Référence des commandes

## Projets (`orc agent`)

### `orc agent new <nom> [options]`

Crée un nouveau projet.

| Option | Description |
|---|---|
| *(aucune)* | Lance le wizard interactif (Claude pose ~22 questions) |
| `--brief <fichier>` | Utilise un brief existant. Claude le lit, pose des questions, l'enrichit |
| `--brief <fichier> --no-clarify` | Copie le brief tel quel sans clarification |
| `--skip-brief` | Copie le template vide (à remplir manuellement) |
| `--github [public\|private]` | Crée aussi le repo GitHub (private par défaut) |

```bash
orc agent new mon-app
orc agent new mon-app --brief briefs/idee.md
orc agent new mon-app --brief spec.md --no-clarify
orc agent new mon-app --brief spec.md --no-clarify --github
orc agent new mon-app --github public
```

### `orc agent start <nom>`

Lance l'orchestrateur en background. Reprend automatiquement si le projet a déjà avancé (crash recovery).

```bash
orc agent start mon-app
```

### `orc agent stop <nom>`

Arrête proprement l'orchestrateur (tue le process Claude en cours, sauve l'état).

```bash
orc agent stop mon-app
```

### `orc agent restart <nom>`

Stop + start en une commande.

### `orc agent github <nom> [--public]`

Crée un repo GitHub pour un projet existant. Utile si le repo n'a pas été créé à l'init. Vérifie que le remote n'existe pas déjà.

```bash
orc agent github mon-app            # Repo privé
orc agent github mon-app --public   # Repo public
```

### `orc agent status [nom]`

Sans argument : vue d'ensemble de tous les projets avec statut (en cours / terminé / crashé / arrêté), features, coût, progression.
Avec argument : détail d'un projet avec barre de progression, feature en cours, phase, ETA estimée, état fonctionnel de l'app.

```bash
orc agent status          # Tous les projets (avec % progression)
orc agent status mon-app  # Détail + barre de progression + ETA
```

### `orc agent dashboard <nom> [--refresh N]`

Dashboard live auto-refresh (toutes les 5s par défaut) avec :
- Barre de progression visuelle
- Feature en cours et phase
- Coût / budget
- ETA estimée (basée sur la durée moyenne par feature)
- Roadmap colorée (✅ done, 🔄 en cours, ⬚ à faire)
- Dernière activité (6 dernières lignes du log)
- État fonctionnel de l'app (si `FUNCTIONAL_CHECK_COMMAND` configuré)

```bash
orc dashboard mon-app             # Dashboard live (refresh 5s)
orc dash mon-app                  # Raccourci
orc agent dashboard mon-app --refresh 10  # Refresh toutes les 10s
```

### `orc agent logs <nom> [--full]`

Affiche les logs orchestrateur en temps réel (`tail -f`). Avec `--full` : ouvre le log complet dans `less`.
Ces logs contiennent les transitions de phases, coûts, erreurs — mais pas les actions détaillées de Claude.

```bash
orc agent logs mon-app         # Temps réel
orc agent logs mon-app --full  # Historique complet
orc l mon-app                  # Raccourci
```

### `orc agent logs <nom> --debug`

Actions de Claude en temps réel (activé par défaut, **zéro token Claude**).

Contenu du log :
- En-tête de phase (modèle, max_turns, feature en cours)
- 50 premières lignes du prompt envoyé (contexte injecté)
- Actions toutes les ~5s : `→ Read file_path=src/...`, `→ Write`, `→ Bash cmd=...`
- Texte généré par Claude (raisonnement, commentaires)
- Erreurs d'outils immédiatement visibles : `❌ ERROR: ...`

```bash
orc logs mon-app --debug       # tail -f sur orc-debug-live.log
orc l mon-app --debug          # raccourci
```

**Cas d'usage : supervision en temps réel**
Ouvrir une seconde instance de Claude Code avec `orc logs <nom> --debug` pour diagnostiquer et corriger les problèmes pendant qu'orc tourne.

### `orc agent update`

Met à jour le template orc (`git pull` dans le dossier orc).

## Roadmap (`orc roadmap`)

### `orc roadmap [options]`

Affiche la roadmap d'orc (le meta-outil).

| Option | Description |
|---|---|
| *(aucune)* | Vue compacte (titre + priorité + effort) |
| `--detail` | + contexte, dépendances |
| `--full` | + specs complètes, critères d'acceptance |
| `--priority P1` | Filtrer par priorité (P0, P1, P2, P3) |
| `--tag <tag>` | Filtrer par tag |
| `--epic <epic>` | Filtrer par epic |

```bash
orc roadmap
orc roadmap --detail --priority P1
orc roadmap --full --tag adoption
```

### `orc roadmap <projet> [options]`

Affiche la roadmap d'un projet spécifique (ROADMAP.md du projet).

```bash
orc roadmap mon-app
orc roadmap mon-app --detail
```

## Administration (`orc admin`)

### `orc admin config [set KEY VAL]`

Affiche ou modifie la configuration globale.

```bash
orc admin config                        # Voir la config
orc admin config set CLAUDE_MODEL xxx   # Modifier
```

### `orc admin model [set <model-id>]`

Affiche le modèle Claude actuel avec les tarifs. Avec `set` : change le modèle par défaut.

```bash
orc admin model
orc admin model set claude-sonnet-4-6-20250514
```

### `orc admin budget`

Affiche les coûts détaillés de tous les projets (tokens input/output, coût estimé).

### `orc admin key [set <key>]`

Affiche ou configure la clé API Anthropic.

```bash
orc admin key
orc admin key set sk-ant-...
```

### `orc admin version`

Affiche la version d'orc et vérifie les dépendances (Claude CLI, git, gh, jq).

### `orc admin update`

Met à jour le template orc.

## Raccourcis

| Raccourci | Équivalent |
|---|---|
| `orc s` | `orc agent status` |
| `orc s <nom>` | `orc agent status <nom>` |
| `orc dash <nom>` | `orc dashboard <nom>` |
| `orc db <nom>` | `orc dashboard <nom>` |
| `orc l <nom>` | `orc agent logs <nom>` |
| `orc r` | `orc roadmap` |

## init.sh (legacy)

Le wizard original avec 5 étapes (nom, description, config, workspace, brief). Supporte `--brief` et `--skip-brief`.

```bash
./init.sh mon-projet
./init.sh mon-projet --brief briefs/x.md
./init.sh mon-projet --brief x.md --no-clarify
./init.sh mon-projet --skip-brief
```

Différence avec `orc agent new` : inclut la configuration interactive (mode d'autonomie, recherche, max features) et propose la création de repo GitHub en fin de wizard.
