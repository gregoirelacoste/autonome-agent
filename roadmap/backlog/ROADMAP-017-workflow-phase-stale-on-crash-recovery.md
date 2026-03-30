---
id: ROADMAP-017
priority: P2
type: bugfix
effort: S
tags: [state, crash-recovery, status]
epic: reliability
depends: []
---

# workflow_phase reste "crashed" après reprise réussie

## Problème observé

Après un crash + reprise automatique, `workflow_phase` dans `state.json` reste à `"crashed"` même quand le run continue normalement. Le run progresse (tests passent, features s'enchaînent) mais l'état interne est incohérent.

Conséquences :
- `orc agent status` peut afficher "terminé" à tort (lit `workflow_phase` pour déterminer le statut affiché)
- La valeur résiduelle peut perturber la reprise après un 2e crash (la state machine lit `workflow_phase` pour savoir où reprendre)

## Piste de solution

Dans `orchestrator.sh`, au démarrage du run (après `migrate_config()` et lecture de `state.json`), si `workflow_phase == "crashed"` mais le run reprend normalement, restaurer `workflow_phase` à la valeur cohérente (`"features"` si des features sont en cours, etc.).

Alternativement, dans `workflow_transition()`, traiter `"crashed"` comme un état de transit → toujours forcer une transition vers l'état correct au redémarrage.

## Contexte

Observé sur geo_vox le 2026-03-29 : `run_status: "running"`, `workflow_phase: "crashed"`, PID vivant, tests en cours. Le `orc agent status` affichait "terminé" à tort.
