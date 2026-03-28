---
id: ROADMAP-014
title: Feedback loop utilisateur (analytics → features)
priority: P3
type: feature
effort: L
tags: [analytics, product, adoption]
created: 2026-03-28
updated: 2026-03-28
depends: []
epic: adopt-mode
---

## Contexte

ORC construit ce que le brief demande, pas ce que les utilisateurs utilisent réellement. Après déploiement, aucune donnée d'usage ne remonte pour influencer les prochaines features. Le score de maturité est basé sur le code, pas sur l'usage réel.

## Spécification

- Intégrer un tracking analytics léger au bootstrap (Posthog, Plausible, ou endpoint maison)
- Lire les données d'usage avant chaque cycle evolve
- Prioriser les features suivantes basées sur : pages visitées, taux d'abandon, erreurs JS, clics
- Injecter un résumé analytics dans le prompt de la phase strategy/evolve

## Critères de validation

- [ ] Analytics intégré au bootstrap (configurable, off par défaut)
- [ ] Données d'usage lues avant la phase evolve
- [ ] Priorisation des features influencée par l'usage réel
- [ ] Fonctionne sans analytics (dégradation gracieuse)

## Notes

Nécessite que le produit soit déployé et utilisé. Pertinent pour un v2 d'ORC quand les projets générés sont en production. Le brief scoring + acceptance + score de maturité couvrent le besoin pour l'instant.
