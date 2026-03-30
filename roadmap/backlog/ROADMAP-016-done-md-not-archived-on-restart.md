---
id: ROADMAP-016
title: DONE.md non archivé au restart post-done — status affiche "terminé" à tort
priority: P3
type: bugfix
effort: XS
tags: [status, ux, watch]
created: 2026-03-29
updated: 2026-03-29
depends: []
epic: "operator-ux"
---

## Contexte

Observé sur geo_vox : après qu'un cycle evolve marque le projet "done" (DONE.md créé), un auto-brainstorm ajoute de nouveaux tickets et le run repart. DONE.md n'est pas archivé/supprimé au restart. Conséquence : `get_run_status()` dans orc-agent.sh retourne "terminé" (check `[ -f DONE.md ]` en priorité sur `is_running()`) alors que l'orchestrateur tourne activement.

Problème connexe : `workflow_phase: "crashed"` dans state.json reste après un crash précédent et n'est pas réinitialisé au restart (`run_status` lui est bien remis à "running").

## Spécification

1. Au démarrage de `orchestrator.sh`, si un cycle reprend après DONE (nouvelles features dans todo/), archiver DONE.md → `.orc/DONE-archive-N.md` ou le supprimer.
2. Ou : dans `get_run_status()`, vérifier `is_running()` AVANT `[ -f DONE.md ]` pour que le statut live prenne la priorité.
3. Au restart, réinitialiser `workflow_phase` à la valeur cohérente avec l'état réel (ex: "features") si `run_status` passe à "running".

## Critères de validation

- [ ] `orc status <projet>` affiche "en cours" quand l'orchestrateur tourne, même si DONE.md existe
- [ ] `workflow_phase` dans state.json reflète l'état actuel du workflow au restart

## Notes

Fix minimal recommandé : inverser l'ordre des checks dans `get_run_status()` — `is_running()` avant `[ -f DONE.md ]`.
