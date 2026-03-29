PHASE ÉVOLUTION — Toutes les features de la ROADMAP sont terminées.

1. Relis .orc/BRIEF.md (la vision originale)
2. Analyse le projet dans son état actuel (code, tests, .orc/research/)
3. Lis .orc/research/INDEX.md et les SYNTHESIS.md
4. Lis les rapports d'acceptance : .orc/logs/acceptance-*.md

### Étape 1 : Score de maturité produit

Évalue le produit et écris le score dans .orc/logs/maturity-score.md :

| Critère | Score (1-5) | Justification |
|---------|-------------|---------------|
| **Parcours utilisateur principal** fonctionne | | Le user peut-il faire l'action principale du brief ? |
| **Données** se créent/lisent/modifient/suppriment | | CRUD fonctionne-t-il ? |
| **Erreurs** gérées proprement | | Pas de crash visible, messages clairs |
| **UI/UX** cohérente et utilisable | | Pas de pages cassées, navigation logique |
| **Tests** couvrent les scénarios clés | | Les tests valident le comportement, pas juste la compilation |
| **Documentation** utilisateur minimale | | README + setup instructions suffisantes |

**Score total : X/30**

### Étape 2 : Décision

**Si score >= 24/30 (produit mature)** → Option B (DONE)
**Si score >= 18/30 (fonctionnel mais améliorable)** → Option A avec max 3 features ciblées
**Si score < 18/30 (lacunes critiques)** → Option A avec les corrections prioritaires

### Option A : Améliorations ciblées
Identifie les features qui augmenteraient le plus le score de maturité.

Crée des tickets dans `.orc/roadmap/todo/` (un fichier par feature). Pour chaque ticket :

Format fichier : `NNN-slug.md` (NNN = prochain numéro séquentiel après les tickets existants)

```yaml
---
id: NNN
title: "Titre concis"
priority: P1
type: feature|bugfix|evolution
effort: S|M|L
tags: []
epic: evolve-cycle-N
created: YYYY-MM-DD
source: evolve
---

## Contexte
Quel critère de maturité cette feature améliore.
Quelle section du brief elle sert.

## Spécification
Ce qui doit être implémenté.

## Critères de validation
- [ ] Critère testable
```

Limiter les ajouts à **5 tickets maximum** par cycle d'évolution.

### Option B : Projet complet
Crée DONE.md avec :
- Score de maturité final (tableau ci-dessus)
- Résumé du projet livré
- Features implémentées (liste)
- Métriques : features, tests, fichiers, coût total
- Ce qui reste à faire par un humain (feedback utilisateur, config prod, etc.)
