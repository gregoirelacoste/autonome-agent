---
id: ROADMAP-015
title: Prompt prefix caching inter-features
priority: P3
type: optimization
effort: M
tags: [tokens, performance, cost]
created: 2026-03-28
updated: 2026-03-28
depends: []
epic: ""
---

## Contexte

Chaque invocation `claude -p` recharge le contexte complet (CLAUDE.md, INDEX.md, conventions). Sur 90 invocations par run, c'est ~90x les mêmes fichiers de base relus. L'API Anthropic facture les tokens cachés à 10% du prix, mais en mode non-interactif chaque appel est isolé.

## Spécification

- Construire un "préfixe stable" (CLAUDE.md + INDEX.md + conventions)
- L'injecter via `--append-system-prompt` pour bénéficier du cache API
- Ne changer le préfixe que quand les fichiers sources changent (hash-based)
- Mesurer l'économie réelle sur un run de 15 features

## Critères de validation

- [ ] Préfixe stable injecté via --append-system-prompt
- [ ] Cache hit mesuré (tokens facturés vs non-cachés)
- [ ] Économie > 5% du budget total pour justifier la complexité
- [ ] Pas de régression sur la qualité des réponses

## Notes

Gain estimé : ~$3-5 par run de 15 features (~10%). Claude Code gère déjà une partie du caching côté API. Le ratio effort/gain est faible comparé aux optimisations déjà en place (modèle léger = 35-45%, critic conditionnel = 5-10%).
