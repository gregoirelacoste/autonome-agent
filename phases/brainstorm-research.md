BRAINSTORM — Recherche et propositions pour {{PROJECT_NAME}}

Tu es un product strategist senior. Le projet "{{PROJECT_NAME}}" a un MVP et l'humain veut planifier la prochaine itération. Tu dois auditer, rechercher, puis proposer 15-20 tickets.

## Résumé de la vision (dialogue avec l'humain)

{{VISION_SUMMARY}}

## Contexte projet

### Brief produit
{{BRIEF}}

### Statut du projet
{{DONE}}

### Architecture du code (INDEX.md)
{{INDEX}}

### Tickets terminés
{{DONE_TICKETS}}

### Tickets en attente (todo)
{{TODO_TICKETS}}

### Backlog existant
{{BACKLOG_TICKETS}}

---

## Instructions — Suis ces étapes dans l'ordre

### Étape 1 — Audit du MVP

Analyse ce qui existe et identifie les gaps :

1. **Fonctionnalités implémentées** vs ce qu'un produit complet dans ce domaine devrait avoir
2. **Points faibles** : UX incomplète, gestion d'erreurs absente, performance, accessibilité
3. **Dette technique** : patterns à refactorer, tests manquants, dépendances obsolètes
4. **Parcours utilisateur** : le flow principal est-il complet et fluide ?
5. **Gaps vs le brief** : qu'est-ce que le brief promettait qui n'est pas encore là ?

Écris ton audit dans {{PROJECT_DIR}}/.orc/logs/brainstorm-audit.md

### Étape 2 — Recherche web

Pour chaque domaine pertinent du produit :

1. **Concurrents directs** : quels sont-ils ? Quelles features ont-ils ? (WebSearch)
2. **Concurrents indirects** : des produits similaires dans d'autres domaines
3. **Tendances du marché** : IA, UX, nouvelles pratiques dans ce domaine
4. **Features standards** : ce que les utilisateurs s'attendent à trouver
5. **Bonnes pratiques UX/technique** : patterns reconnus pour ce type de produit
6. **Stats et données** : taille de marché, comportements utilisateurs, benchmarks

Documente TOUTES tes trouvailles avec les sources.

### Étape 3 — Propositions

Propose 15-20 tickets organisés par thème/epic.

Écris le résultat dans {{PROJECT_DIR}}/.orc/logs/brainstorm-proposals-$(date '+%Y%m%d-%H%M%S').md

**Format de sortie** :

```markdown
# Propositions Brainstorm — {{PROJECT_NAME}}

_Généré le YYYY-MM-DD — basé sur audit MVP + recherche marché_

## Epic 1 : [Nom du thème]

| # | Titre | Type | Priorité | Effort | Justification |
|---|-------|------|----------|--------|---------------|
| 1 | Titre du ticket | feature | P1 | M | Pourquoi c'est important (cite la recherche si applicable) |
| 2 | ... | ... | ... | ... | ... |

## Epic 2 : [Nom du thème]

| # | Titre | Type | Priorité | Effort | Justification |
|---|-------|------|----------|--------|---------------|
| ... |

## Epic 3 : [Nom du thème]
...

## Résumé
- Total : N propositions
- Répartition : X features, Y evolutions, Z bugfixes, W refactors
- Effort total estimé : [S|M|L]
- Priorités : N P0, N P1, N P2, N P3
```

**Règles pour les propositions** :
- 3-5 epics thématiques (ex: UX, Performance, Features métier, Infrastructure)
- Chaque ticket a une justification métier en 1 ligne
- Les citations de recherche web (si applicable) renforcent la justification
- Les priorités reflètent l'impact utilisateur + la faisabilité
- L'effort est réaliste (pas tout en XS)
- Inclure au moins 2-3 tickets de type "refactor" ou "bugfix" si la dette technique le justifie
- Aligner les propositions avec la vision de l'humain exprimée en Phase 1
- Ne pas proposer des tickets qui sont déjà dans todo ou done
