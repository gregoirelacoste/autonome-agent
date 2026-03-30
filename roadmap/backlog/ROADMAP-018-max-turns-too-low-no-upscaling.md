---
id: ROADMAP-018
title: adaptive_max_turns ne remonte pas quand les phases atteignent le plafond
priority: P2
type: improvement
effort: S
tags: [turns, adaptive, reliability]
created: 2026-03-29
updated: 2026-03-29
depends: []
epic: "reliability"
---

## Contexte

Sur geo_vox feature 40, 3 phases consécutives ont atteint leur max_turns :
- product-review : 5/5 (résultat potentiellement incomplet)
- reflect : 15/15 (résultat potentiellement incomplet)
- acceptance : 20/20 (résultat potentiellement incomplet)

`adaptive_max_turns()` ne peut qu'abaisser les plafonds (p75 + 30% des runs passés). Si une phase utilise systématiquement 100% de ses turns, le mécanisme adaptatif ne détecte pas qu'elle en aurait besoin de plus — il n'augmente jamais.

## Spécification

Deux axes :

1. **Détection du saturation** : si une phase atteint son max_turns 2+ fois de suite (dans `tokens.json.by_phase.X.turns_history[]`), logger un WARN plus visible et ne pas réduire le plafond adaptatif.

2. **Upscaling auto** : si la phase a atteint max_turns lors du dernier run, augmenter légèrement le plafond adaptatif (+20%, plafonné à `MAX_TURNS_*` du config). Symétrique à la réduction actuelle.

## Critères de validation

- [ ] Quand reflect atteint 15/15 deux runs de suite → pas de réduction du plafond adaptatif
- [ ] Quand reflect atteint 15/15 deux runs de suite → prochain max_turns = min(15 * 1.2, MAX_TURNS_REFLECT)
- [ ] `bash -n orchestrator.sh` passe

## Notes

Pattern observé sur geo_vox (feature 40, Epic 14). Les 3 phases concernées (product-review, reflect, acceptance) sont des phases de relecture/validation qui deviennent naturellement plus longues sur des projets complexes avec beaucoup de code accumulé.
