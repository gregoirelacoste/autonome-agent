---
name: roadmap-item
description: Créer ou mettre à jour un item de roadmap structuré
user_invocable: true
---

## Gestion des items de roadmap

Quand tu découvres un besoin, une idée, un bug, ou une amélioration pendant
ton travail (implémentation, rétrospective, debug), crée un item de roadmap.

### Où écrire

**Pour les projets générés** (quand tu travailles dans un workspace projet) :
```
.orc/roadmap/
├── backlog/        # Idées non priorisées (défaut pour les découvertes)
├── todo/           # Prêtes à implémenter (triées par priorité P0→P3)
├── in-progress/    # En cours (géré par l'orchestrateur)
└── done/           # Terminées
```

**Pour le template orc** (quand tu travailles sur orc lui-même) :
```
roadmap/
├── backlog/        # Idées non priorisées
├── planned/        # Priorisées, prêtes à implémenter
├── in-progress/    # En cours
└── done/           # Terminées
```

**Par défaut, les découvertes vont dans `backlog/`.**
Ne place dans `todo/` ou `planned/` que si c'est un prérequis bloquant identifié.

### Format obligatoire

**Projet** : `NNN-slug-court.md` dans `.orc/roadmap/<status>/`
**Template orc** : `ROADMAP-NNN-slug-court.md` dans `roadmap/<status>/`

```markdown
---
id: ROADMAP-NNN
title: "Titre court et descriptif"
priority: P0|P1|P2|P3
type: feature|bugfix|refactor|infra|dx|security|docs|research
effort: XS|S|M|L|XL
tags: [tag1, tag2]
created: YYYY-MM-DD
updated: YYYY-MM-DD
depends: [ROADMAP-XXX]
epic: nom-de-l-epic
---

## Contexte
Pourquoi cet item existe. Quel problème il résout.
Référence la feature ou le bug qui l'a révélé.

## Spécification
Ce qui doit être fait concrètement.

## Critères de validation
- [ ] Critère mesurable 1
- [ ] Critère mesurable 2

## Notes
Réflexions, liens, alternatives considérées.
```

### Règles

1. **Un fichier = un item.** Pas de listes.
2. **ID incrémental** : regarde le dernier ID dans `roadmap/` et incrémente.
3. **Priorité** :
   - P0 = bloque le système, à faire immédiatement
   - P1 = prochaine itération
   - P2 = planifié mais pas urgent
   - P3 = nice-to-have
4. **Effort** : estimation honnête (XS < 1h, S 1-4h, M 4h-2j, L 2-5j, XL > 5j)
5. **Dépendances** : liste les IDs des items qui doivent être faits avant.
6. **Epic** : regroupe les items liés (ex: `adopt-mode`, `cli-monitoring`)
7. **Jamais supprimer** : un item fait → `mv` vers `done/`, jamais `rm`.
8. **Changer de statut** = déplacer le fichier dans le bon dossier.

### Quand créer un item

- Pendant l'**implémentation** : tu découvres un edge case, une dette technique
- Pendant la **rétrospective** : tu identifies une amélioration systémique
- Pendant le **debug** : tu trouves un bug non lié à la feature courante
- Pendant l'**evolve** : tu imagines de nouvelles features

### Ne PAS créer d'item pour

- Un fix trivial dans la feature courante (fais-le directement)
- Une tâche déjà couverte par un item existant (mets à jour les notes)
