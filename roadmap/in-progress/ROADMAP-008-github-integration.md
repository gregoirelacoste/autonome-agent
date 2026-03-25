---
id: ROADMAP-008
title: GitHub Integration — PR-based merge + tracking issue
priority: P1
type: feature
effort: L
tags: [github, devops, visibility]
created: 2026-03-25
updated: 2026-03-25
depends: []
epic: github-native
---

## Contexte

ORC fonctionne en local-only : merge direct, logs locaux, signaux par fichiers.
Les orchestrateurs IA modernes (Devin, Sweep, OpenHands, Copilot Coding Agent)
convergent tous vers un pattern PR-centric avec GitHub Issues comme backbone.

ORC doit offrir la même visibilité et le même contrôle asynchrone, tout en gardant
le mode local comme fallback (dégradation gracieuse si `gh` absent).

## Spécification

### Phase 1 (cet item)

1. **Config `GIT_STRATEGY`** : `local` (défaut, rétrocompat) | `pr` (GitHub PRs)
2. **PR-based merge** : quand `GIT_STRATEGY=pr`, chaque feature crée une PR via `gh`,
   attend review si `REQUIRE_HUMAN_APPROVAL=true`, puis merge via GitHub.
3. **Tracking issue** : une issue GitHub "ORC Run" créée au bootstrap, commentée
   à chaque début/fin de feature, fermée en fin de run.
4. **GitHub signals** : labels `orc:pause`, `orc:stop`, `orc:continue` sur la
   tracking issue, lus par `check_signals()`.
5. **Abandoned issues** : quand une feature est abandonnée (3x même erreur),
   une issue bug est auto-créée avec les fix-reflections.
6. **Dégradation gracieuse** : si `gh` non disponible, tout fonctionne en local.

### Phases futures (items séparés)

- Sync bidirectionnelle roadmap ↔ GitHub Issues
- GitHub Projects v2 dashboard avec champs custom
- GitHub Actions comme CI
- GitHub Releases automatiques

## Critères de validation

- [ ] `GIT_STRATEGY=local` : comportement identique à avant (rétrocompat)
- [ ] `GIT_STRATEGY=pr` : feature branch → push → PR → merge via GitHub
- [ ] Tracking issue créée au bootstrap, commentée, fermée à la fin
- [ ] Signaux GitHub (labels) lus et convertis en fichiers signaux locaux
- [ ] Feature abandonnée → issue bug créée automatiquement
- [ ] `gh` absent → aucun crash, fallback local transparent
- [ ] `bash -n orchestrator.sh` passe

## Notes

- Inspiré des patterns Sweep (issue-driven), Devin (PR-centric), OpenHands (label-driven)
- Compatible avec ROADMAP-004 (git strategy detection) — cette feature est le socle
