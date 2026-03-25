# Learnings inter-projets

Ce dossier accumule les apprentissages de tous les projets exécutés par l'orchestrateur.

## Structure

Chaque fichier est nommé `YYYY-MM-DD-<projet>.md` et contient les insights
extraits de `orchestrator-improvements.md` à la fin du projet.

## Utilisation

- Au bootstrap d'un nouveau projet, l'IA lit ce dossier
- Les patterns récurrents sont intégrés dans les prompts de phase
- Les skills les plus réutilisées sont promues dans `skills-templates/`

## Format d'un fichier learning

```markdown
# Learnings — <nom-du-projet>
Date : YYYY-MM-DD

## Règles découvertes
- ...

## Skills créées
- ...

## Pièges à éviter
- ...

## Recommandations pour l'orchestrateur
- ...
```
