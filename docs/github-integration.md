# Intégration GitHub

orc fonctionne en **local-first** : tout tourne sans GitHub. Chaque option GitHub est indépendante et off par défaut.

**Principe** : local = source de vérité, GitHub = miroir de visibilité.

## Prérequis

- [GitHub CLI](https://cli.github.com/) (`gh`) installé et authentifié
- Un repo GitHub pour le projet (`gh repo create` ou existant)

Si `gh` est absent, tout fonctionne en local sans erreur.

## Options

Toutes se configurent dans `~/projects/<nom>/.orc/config.sh` :

### GIT_STRATEGY

```bash
GIT_STRATEGY="local"   # Défaut : merge direct sur main
GIT_STRATEGY="pr"      # Créer une PR par feature, merge après review/CI
```

En mode `pr`, si la création de PR échoue, fallback automatique en local.

### GITHUB_TRACKING_ISSUE

```bash
GITHUB_TRACKING_ISSUE=true
```

Crée une issue "ORC Run — <projet>" au démarrage. Commentée automatiquement à chaque feature avec : nom, statut, durée, coût tokens.

### GITHUB_SIGNALS

```bash
GITHUB_SIGNALS=true
```

Permet de contrôler l'orchestrateur via des labels GitHub sur la tracking issue :

| Label | Effet |
|---|---|
| `orc:pause` | Pause après la feature en cours |
| `orc:stop` | Arrêt après la feature en cours |
| `orc:continue` | Reprendre après une pause |

Les signaux locaux (`.orc/pause-requested`, etc.) fonctionnent toujours en parallèle.

### GITHUB_SYNC_ROADMAP

```bash
GITHUB_SYNC_ROADMAP=true
```

Miroir push-only : chaque feature de ROADMAP.md (vue auto-générée depuis le kanban `.orc/roadmap/`) est reflétée comme GitHub Issue. L'orchestrateur ne lit jamais les issues comme source de features — le kanban local reste la source de vérité.

### GITHUB_FEEDBACK

```bash
GITHUB_FEEDBACK=true
```

Lit les commentaires humains sur la tracking issue et les injecte dans le prompt avant la prochaine feature. Complémentaire à `.orc/human-notes.md`.

### GITHUB_CI

```bash
GITHUB_CI=true
```

Après la quality gate locale, attend les checks GitHub Actions. Non-bloquant — les tests locaux font toujours foi. Si les checks échouent, l'info est logguée mais n'empêche pas le merge.

### GITHUB_RELEASES

```bash
GITHUB_RELEASES=true
```

Crée automatiquement :
- Une release `v0.N.0` après chaque méta-rétrospective
- Une release `v1.0.0` en fin de projet

## Combinaisons recommandées

### Solo prototypage rapide
```bash
GIT_STRATEGY="local"
# Tout le reste : false (défaut)
```

### Équipe avec visibilité
```bash
GIT_STRATEGY="pr"
GITHUB_TRACKING_ISSUE=true
GITHUB_FEEDBACK=true
```

### CI/CD complet
```bash
GIT_STRATEGY="pr"
GITHUB_TRACKING_ISSUE=true
GITHUB_CI=true
GITHUB_RELEASES=true
GITHUB_SIGNALS=true
```
