# FAQ & Troubleshooting

## Questions fréquentes

### Le workspace est-il un repo git ?

Oui. Le workspace est directement le repo git du projet. `orchestrator.sh` et `phases/` sont des symlinks vers le template orc (ignorés par `.gitignore`).

### Puis-je lancer plusieurs projets en parallèle ?

Oui. Chaque projet est indépendant avec son propre process, état et logs. `orc s` les affiche tous.

### Combien ça coûte ?

~50-100K tokens par feature. Un projet de 10 features ~500K-1M tokens. Suivre avec `orc admin budget`. Limiter avec `MAX_BUDGET_USD` dans la config.

### Comment reprendre après un crash ?

```bash
orc agent start mon-projet
```

L'orchestrateur détecte l'état existant (`.orc/state.json`) et reprend là où il s'est arrêté. Les guards vérifient : CLAUDE.md existe ? INDEX.md existe ? Tickets dans `.orc/roadmap/todo/` ?

### Mon projet est "terminé" mais je veux continuer — comment faire ?

Deux options :

```bash
# Option 1 : Ajouter un ticket manuellement
orc roadmap ticket mon-projet

# Option 2 : Brainstorm complet pour la V2 (10-15 tickets)
orc roadmap brainstorm mon-projet
```

Les deux commandes archivent automatiquement `DONE.md`, reset le workflow, et proposent de relancer le projet.

### Comment ajouter un ticket en urgence pendant un run ?

```bash
orc roadmap ticket mon-projet --quick "fix le bug de login" --type bugfix --priority P0
```

Le ticket P0 sera pris en priorité (avant les P1/P2/P3). Si le projet tourne, une notification est injectée dans `human-notes.md`.

### Qu'est-ce que le kanban projet ?

Chaque projet a un kanban dans `.orc/roadmap/` avec 4 colonnes (backlog, todo, in-progress, done). Chaque ticket est un fichier `.md` avec frontmatter YAML (priorité, type, effort, etc.) et des sections structurées (Contexte, Spécification, Critères).

L'orchestrateur lit les tickets par priorité (P0 d'abord), les déplace en `in-progress` puis `done`. `ROADMAP.md` est auto-généré comme vue de compatibilité.

### Comment modifier les prompts ?

Éditer les fichiers dans `~/projects/mon-projet/phases/`. Chaque phase est un prompt Markdown avec des placeholders `{{VAR}}`.

### Comment changer de modèle Claude ?

```bash
orc admin model set claude-sonnet-4-6
```

Appliqué aux prochains lancements.

### Quelle est la différence entre `init.sh` et `orc agent new` ?

`init.sh` est le wizard legacy avec 5 étapes interactives (nom, description, mode d'autonomie, workspace, brief) + création GitHub.

`orc agent new` est plus direct : crée le workspace avec les défauts, lance le brief. La config se fait après via `vim .orc/config.sh`.

### Mon brief est en anglais, ça marche ?

Oui. L'orchestrateur et les prompts sont en français mais Claude s'adapte à la langue du brief. Le code généré sera dans la langue spécifiée.

## Troubleshooting

### "Un orchestrateur tourne déjà"

Le lockfile `.orc/.lock` existe avec un PID valide. Si le process est mort :

```bash
rm ~/projects/mon-projet/.orc/.lock
orc agent start mon-projet
```

### L'orchestrateur boucle sur le même fix

Le système détecte les boucles via `error_hash()`. Même erreur 2x → change d'approche. 3x → abandon. Si ça persiste, ajoute une note :

```bash
echo "L'erreur X vient de Y, essayer Z" > ~/projects/mon-projet/.orc/human-notes.md
```

### Le brief n'a pas été créé

Si le wizard Claude n'a pas produit de `BRIEF.md` :

```bash
cp ~/projects/mon-projet/BRIEF.template.md ~/projects/mon-projet/BRIEF.md
vim ~/projects/mon-projet/BRIEF.md
```

### Les coûts ne sont pas trackés

Vérifier que `jq` est installé. Le tracking tokens est désactivé si `jq` est absent (dégradation gracieuse, pas de crash).

```bash
apt install jq    # ou brew install jq
```

### L'orchestrateur ne démarre pas

Vérifier :
1. `BRIEF.md` existe dans le workspace
2. `claude` CLI est installé et dans le PATH
3. `ANTHROPIC_API_KEY` est défini (`orc admin key`)
4. Pas de lockfile orphelin (`.orc/.lock`)
