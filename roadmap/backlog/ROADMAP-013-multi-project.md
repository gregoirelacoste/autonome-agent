---
id: ROADMAP-013
title: Multi-projet (frontend + backend en parallèle)
priority: P3
type: feature
effort: XL
tags: [architecture, multi-repo]
created: 2026-03-28
updated: 2026-03-28
depends: []
epic: multi-project
---

## Contexte

Un vrai outil métier c'est rarement un seul repo. SaaS = frontend + API + DB + workers. ORC ne pilote qu'un seul workspace. Tout est dans un monolithe, ce qui limite les projets complexes.

## Spécification

Un "super-orchestrateur" qui :
- Lance 2+ instances ORC en parallèle (une par composant)
- Synchronise les interfaces (types partagés, contrats API)
- Vérifie que le tout fonctionne ensemble (tests d'intégration cross-repo)
- Brief unifié → roadmap décomposée par composant

## Critères de validation

- [ ] Peut piloter 2 repos en parallèle (frontend + backend)
- [ ] Types/contrats API partagés entre les repos
- [ ] Tests d'intégration cross-composants
- [ ] Un seul brief, une seule roadmap, plusieurs workspaces

## Notes

Pas prioritaire tant que le monolithe suffit pour les MVPs. À évaluer quand des projets réels nécessitent cette séparation. Le mode `adopt` permet déjà d'orchestrer un repo existant.
