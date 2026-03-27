# Configuration

Chaque projet a sa propre configuration dans `~/projects/<nom>/.orc/config.sh`. La config est générée à partir de `config.default.sh` lors de la création du projet.

## Modes d'autonomie

| Mode | Config | Comportement |
|---|---|---|
| **Pilote auto** | `PAUSE=0, APPROVAL=false` | 100% autonome — prototypes, exploration |
| **Copilote** | `PAUSE=0, APPROVAL=true` | Claude code, tu valides chaque merge |
| **Supervisé** | `PAUSE=3, APPROVAL=false` | Pause toutes les 3 features pour review |

## Paramètres par catégorie

### Projet

| Paramètre | Défaut | Description |
|---|---|---|
| `PROJECT_DIR` | `./project` | Chemin du code produit |
| `PROJECT_NAME` | *(vide)* | Nom du projet (rempli par init) |

### Garde-fous

| Paramètre | Défaut | Description |
|---|---|---|
| `MAX_FIX_ATTEMPTS` | 5 | Tentatives de fix par feature avant abandon |
| `MAX_FEATURES` | 50 | Nombre total de features avant arrêt |
| `MAX_TURNS_PER_INVOCATION` | 50 | Turns Claude par invocation |

### Rythme

| Paramètre | Défaut | Description |
|---|---|---|
| `EPIC_SIZE` | 3 | Features par epic avant veille ciblée |
| `META_RETRO_FREQUENCY` | 5 | Features entre chaque méta-rétrospective |

### Intervention humaine

| Paramètre | Défaut | Description |
|---|---|---|
| `PAUSE_EVERY_N_FEATURES` | 0 | Pause toutes les N features (0 = jamais) |
| `REQUIRE_HUMAN_APPROVAL` | false | Valider chaque merge manuellement |
| `AUTO_EVOLVE_ROADMAP` | true | L'IA peut ajouter des features à la roadmap |
| `MAX_EVOLVE_CYCLES` | 2 | Cycles d'évolution max de la roadmap |
| `MAX_AI_ROADMAP_ADDS` | 5 | Features max ajoutées par l'IA à la roadmap |

### Recherche

| Paramètre | Défaut | Description |
|---|---|---|
| `ENABLE_RESEARCH` | true | Activer la veille marché |
| `MAX_TURNS_RESEARCH_INITIAL` | 80 | Turns pour la recherche initiale |
| `MAX_TURNS_RESEARCH_EPIC` | 40 | Turns pour la veille par epic |
| `MAX_TURNS_RESEARCH_TREND` | 50 | Turns pour la veille tendances |

### Technique

| Paramètre | Défaut | Description |
|---|---|---|
| `BUILD_COMMAND` | `npm run build` | Commande de build |
| `TEST_COMMAND` | `npx playwright test` | Commande de test |
| `DEV_COMMAND` | `npm run dev` | Commande dev server |
| `LINT_COMMAND` | `npm run lint` | Commande lint |
| `QUALITY_COMMAND` | *(vide)* | Commande qualité (après tests, avant merge) |

### Budget

| Paramètre | Défaut | Description |
|---|---|---|
| `MAX_BUDGET_USD` | *(vide)* | Budget max en USD (vide = illimité) |

### Timeouts

| Paramètre | Défaut | Description |
|---|---|---|
| `CLAUDE_TIMEOUT` | 1200 | Timeout par invocation Claude (secondes) |

### Logs

| Paramètre | Défaut | Description |
|---|---|---|
| `LOG_DIR` | `./.orc/logs` | Dossier des logs |
| `VERBOSE` | true | Logs détaillés |

### GitHub (optionnel)

Voir [github-integration.md](github-integration.md) pour le détail.

| Paramètre | Défaut | Description |
|---|---|---|
| `GIT_STRATEGY` | `local` | `local` (merge direct) ou `pr` (Pull Requests) |
| `GITHUB_TRACKING_ISSUE` | false | Créer une issue de suivi |
| `GITHUB_SIGNALS` | false | Labels comme signaux (orc:pause, orc:stop) |
| `GITHUB_SYNC_ROADMAP` | false | Miroir roadmap → GitHub Issues |
| `GITHUB_FEEDBACK` | false | Lire commentaires GitHub comme feedback |
| `GITHUB_CI` | false | Attendre les checks GitHub Actions |
| `GITHUB_RELEASES` | false | Créer des releases automatiques |

## Modifier la config

```bash
# Éditeur
vim ~/projects/mon-projet/.orc/config.sh

# Ou via la CLI (config globale)
orc admin config set CLAUDE_MODEL claude-sonnet-4-6-20250514
```

Les changements sont pris en compte au prochain lancement de l'orchestrateur (ou au restart).
