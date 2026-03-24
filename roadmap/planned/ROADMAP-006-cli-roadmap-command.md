---
id: ROADMAP-006
title: "CLI agent roadmap — Suivi multi-niveaux pour l'humain"
priority: P1
type: feature
effort: M
tags: [cli, monitoring, dx]
created: 2026-03-24
updated: 2026-03-24
depends: []
epic: cli-monitoring
---

## Contexte

Sur un VPS Ubuntu sans UI, l'humain a besoin d'un suivi CLI fin de la roadmap
avec plusieurs niveaux de détail : du résumé compact à la vue exhaustive.

## Spécification

Commande `agent roadmap` avec 3 niveaux de verbosité :

### Niveau 1 : Compact (défaut)
```
ROADMAP — orc         P0: 1 | P1: 4 | P2: 3 | P3: 2
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 IN-PROGRESS (2)
  ● ROADMAP-001 [P1/L] adopt.sh — Script d'adoption       adoption,cli
  ● ROADMAP-006 [P1/M] CLI agent roadmap                  cli,monitoring

 PLANNED (3)
  ○ ROADMAP-005 [P0/L] Garde-fous adoption                safety,security
  ○ ROADMAP-002 [P1/M] Auto-détection de stack            adoption
  ○ ROADMAP-003 [P1/M] Orchestrateur — mode adoption      adoption
```

### Niveau 2 : Détaillé (`--detail`)
Ajoute : contexte (premiers ~3 lignes), dépendances, epic, date

### Niveau 3 : Exhaustif (`--full`)
Ajoute : spécification complète, critères de validation, notes

### Filtres
- `--priority P0` / `--tag adoption` / `--epic adopt-mode` / `--type feature`
- `--status planned|in-progress|done|backlog`
- Combinables : `--priority P1 --tag adoption`

## Critères de validation

- [ ] 3 niveaux de verbosité fonctionnels
- [ ] Filtrage par priorité, tag, epic, type, statut
- [ ] Tri par priorité puis par effort
- [ ] Couleurs ANSI (P0=rouge, P1=jaune, P2=bleu, P3=dim)
- [ ] Fonctionne sans `jq` (parsing YAML frontmatter en bash/awk)
- [ ] Intégré dans `agent.sh` comme sous-commande

## Notes

Le parsing du frontmatter YAML en bash pur est le point technique délicat.
Utiliser `awk`/`sed` pour extraire les champs entre les `---`.
