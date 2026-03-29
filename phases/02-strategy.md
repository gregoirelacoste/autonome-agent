PHASE STRATÉGIE

Tu as fait ta recherche initiale. Transforme-la en plan d'action.

1. Lis .orc/research/INDEX.md et tous les SYNTHESIS.md
2. Relis .orc/BRIEF.md (la vision immuable)

### Étape 1 : Scoring du brief

Évalue le brief sur ces critères et écris le résultat dans .orc/logs/brief-scoring.md :

| Critère | Score (1-5) | Commentaire |
|---------|-------------|-------------|
| Clarté du problème utilisateur | | |
| Scope MVP défini | | |
| Stack / contraintes techniques claires | | |
| Critères de succès mesurables | | |
| Utilisateurs cibles identifiés | | |

Si le score total est < 15/25, écris les questions manquantes dans .orc/logs/brief-scoring.md
et ajoute des hypothèses raisonnables pour combler les manques. Note-les dans CLAUDE.md.

### Étape 2 : Roadmap MVP-first (kanban)

Crée la structure kanban si elle n'existe pas : `mkdir -p .orc/roadmap/{backlog,todo,in-progress,done}`

Produis des **fichiers tickets** dans `.orc/roadmap/todo/` (un fichier par feature).

**Format de chaque fichier** : `NNN-slug-court.md` (NNN = 001, 002, etc.)

```yaml
---
id: NNN
title: "Titre concis et orienté action"
priority: P0|P1|P2|P3
type: feature
effort: XS|S|M|L|XL
tags: [domaine, technique]
epic: mvp|ameliorations
created: YYYY-MM-DD
source: strategy
---

## Contexte
Pourquoi cette feature. Cite le brief et la recherche si pertinent.

## Spécification
Ce qui doit être implémenté concrètement. Sois précis : fichiers, APIs, comportement.

## Critères de validation
- [ ] Critère testable 1
- [ ] Critère testable 2

## Notes
Insights de la recherche pertinents pour l'implémentation.
```

Règles :
- **MVP (P0/P1)** : 5-8 features max, fonctionnel seul, epic: mvp
- **Améliorations (P2/P3)** : optionnel si temps/budget, epic: ameliorations
- Le MVP DOIT être fonctionnel seul — pas de dépendance vers P2/P3
- Chaque feature MVP contribue au parcours utilisateur principal
- Quick wins (haute valeur, faible effort) = P0
- Features de fondation technique avant les features avancées
- Critères testables (pas vagues)
- Chaque feature référence un insight de .orc/research/ si pertinent
- **Maximum 15 features totales** — ne pas over-scoper
- L'effort est réaliste (XS=<1h, S=1-4h, M=4h-2j, L=2-5j, XL=>5j)

Mets à jour CLAUDE.md avec les patterns techniques
découverts pendant la recherche (APIs à utiliser, conventions du domaine, etc.)
