---
id: ROADMAP-010
title: GitHub Phase 3 — CI distant + Releases
priority: P2
type: feature
effort: M
tags: [github, ci, releases, devops]
created: 2026-03-25
updated: 2026-03-25
depends: [ROADMAP-008]
epic: github-native
---

## Contexte

Phase 3 de l'intégration GitHub. Les tests locaux font toujours foi.
Le CI distant est une validation bonus. Les releases sont un miroir.

## Spécification

### CI distant (non-bloquant)
- `gh_wait_ci()` : attend les checks GitHub Actions sur la branche courante
- Appelé après la quality gate, avant le merge
- Si CI fail → log warning + commentaire sur tracking issue, mais merge quand même
- Les tests locaux (BUILD_COMMAND + TEST_COMMAND) restent la source de vérité
- `gh_post_quality_status()` : poste le résultat de la quality gate comme commit status

### Releases automatiques
- `gh_create_release()` : crée une GitHub Release avec changelog
- Appelé après chaque meta-rétrospective (tag `v0.N.0`)
- Appelé en fin de projet (tag `v1.0.0`)
- Changelog auto-généré depuis les commits git

### Config
- `GITHUB_CI=false` (off par défaut)
- `GITHUB_RELEASES=false` (off par défaut)

## Critères de validation

- [ ] Tests locaux toujours exécutés en premier
- [ ] CI distant non-bloquant (warn only)
- [ ] Quality gate postée comme commit status
- [ ] Release créée après meta-retro et fin de projet
- [ ] Changelog auto-généré depuis git log
- [ ] Tout off par défaut, aucun crash si gh absent

## Notes

- Le CI distant suppose un `.github/workflows/` déjà configuré (pas généré par ORC)
- La release finale est v1.0.0 — les intermédiaires sont v0.N.0
