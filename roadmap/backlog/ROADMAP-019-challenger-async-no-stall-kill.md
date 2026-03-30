---
id: ROADMAP-019
title: Challenger async — pas de stall kill (stalle 18-26min sans timeout)
priority: P2
type: bugfix
effort: S
tags: [challenger, async, stall, reliability]
created: 2026-03-29
updated: 2026-03-29
depends: []
epic: reliability
---

## Contexte

Observé sur geo_vox : le challenger async a stallé 2 fois consécutives (18min28s et 26min28s avec `0 bytes reçus`) avant de déclencher "Run interrompu (crash ou signal)". Le `STALL_KILL_THRESHOLD` est censé tuer après 5min d'inactivité, mais il ne s'est pas déclenché.

Cause probable : `run_challenger_async()` lance la phase challenger dans une subshell isolée. Cette subshell exécute `run_claude()` mais le monitoring du stall (FIFO heartbeat ou polling du byte count) ne fonctionne peut-être pas correctement en contexte background/subshell.

Les crashes répétés au lancement du challenger async allongent significativement la durée du run (2 × 20min = 40min perdues sur geo_vox).

## Spécification

1. Vérifier que `run_claude()` en subshell async reçoit bien les variables de monitoring (notamment `STALL_KILL_THRESHOLD`)
2. Vérifier que le monitoring heartbeat/bytes fonctionne en contexte background (pas de terminal attaché)
3. Ajouter un timeout explicite sur `run_challenger_async()` indépendant du stall kill (ex: `MAX_TURNS_CHALLENGER * 60s + marge`)
4. Logger explicitement quand le stall kill se déclenche dans la subshell async

## Critères de validation

- [ ] Challenger async stallé → tué après max 5min (STALL_KILL_THRESHOLD)
- [ ] Le timeout de la subshell async est bounded (même si le stall kill échoue)
- [ ] Log explicite "stall kill async challenger" dans orchestrator.log

## Notes

Reproduit 2/2 fois sur geo_vox avant que le 3e challenger réussisse (1min15s). Semble lié à un modèle fort (CLAUDE_MODEL_STRONG=claude-opus-4-6) qui pense longtemps sans émettre de tokens.
