# Configuration

Chaque projet a sa propre configuration dans `~/projects/<nom>/.orc/config.sh`. La config est générée à partir de `config.default.sh` lors de la création du projet.

**Migration auto** : au démarrage, l'orchestrateur détecte les paramètres manquants et les ajoute automatiquement avec les valeurs par défaut. Pas d'action requise.

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
| `PROJECT_DIR` | `.` | Chemin du code produit |
| `PROJECT_NAME` | *(vide)* | Nom du projet (rempli par init) |

### Garde-fous

| Paramètre | Défaut | Description |
|---|---|---|
| `MAX_FIX_ATTEMPTS` | 3 | Tentatives de fix par feature avant abandon |
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
| `MAX_TURNS_RESEARCH_INITIAL` | 50 | Turns pour la recherche initiale |
| `MAX_TURNS_RESEARCH_EPIC` | 20 | Turns pour la veille par epic |
| `MAX_TURNS_RESEARCH_TREND` | 30 | Turns pour la veille tendances |

### Technique

| Paramètre | Défaut | Description |
|---|---|---|
| `BUILD_COMMAND` | `npm run build` | Commande de build |
| `TEST_COMMAND` | `npx playwright test` | Commande de test |
| `DEV_COMMAND` | `npm run dev` | Commande dev server |
| `LINT_COMMAND` | `npm run lint` | Commande lint (vide = désactivé) |
| `QUALITY_COMMAND` | *(vide)* | Commande qualité (après tests, avant merge) |
| `FUNCTIONAL_CHECK_COMMAND` | *(vide)* | Vérification fonctionnelle post-feature |

### Modèles

| Paramètre | Défaut | Description |
|---|---|---|
| `CLAUDE_MODEL` | *(vide = défaut CLI)* | Modèle principal (implement, fix) |
| `CLAUDE_MODEL_LIGHT` | `claude-haiku-4-5-20251001` | Modèle léger (plan, reflect, research, etc.) |

### Budget

| Paramètre | Défaut | Description |
|---|---|---|
| `MAX_BUDGET_USD` | `200.00` | Budget max en USD. Garde-fou avec vérification prédictive + post-hoc |

### Timeouts

| Paramètre | Défaut | Description |
|---|---|---|
| `CLAUDE_TIMEOUT` | 900 | Timeout global par invocation (secondes). 900 = 15min |
| `STALL_KILL_THRESHOLD` | 60 | Checks sans données avant kill auto (×5s). 60 = 5min |
| `PHASE_TIMEOUTS` | *(voir ci-dessous)* | Timeouts par phase (declare -A) |

#### Timeouts par phase (PHASE_TIMEOUTS)

| Phase | Timeout | Description |
|---|---|---|
| `plan` | 120s (2min) | Planification rapide |
| `critic` | 600s (10min) | Review adversariale (modèle principal) |
| `reflect` | 180s (3min) | Rétrospective feature |
| `quality` | 180s (3min) | Correction quality gate |
| `self-improve` | 300s (5min) | Auto-amélioration |
| `strategy` | 300s (5min) | Génération roadmap |
| `evolve` | 300s (5min) | Évolution roadmap |
| `research-initial` | 600s (10min) | Recherche web |
| `research-epic` | 300s (5min) | Veille ciblée |
| `meta-retro` | 600s (10min) | Méta-rétrospective |
| `implement` | 900s (15min) | Implémentation |
| `fix` | 600s (10min) | Correction |

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
| `GITHUB_REMOTE` | `origin` | Remote Git pour push/PR |
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

Les changements sont pris en compte au prochain lancement de l'orchestrateur (ou au restart). Les nouveaux paramètres sont migrés automatiquement au démarrage.
