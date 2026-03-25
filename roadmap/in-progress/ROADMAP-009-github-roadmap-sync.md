---
id: ROADMAP-009
title: GitHub Phase 2 — Roadmap sync + feedback
priority: P1
type: feature
effort: M
tags: [github, roadmap, feedback]
created: 2026-03-25
updated: 2026-03-25
depends: [ROADMAP-008]
epic: github-native
---

## Contexte

Phase 2 de l'intégration GitHub. Le local reste source de vérité,
GitHub reçoit un miroir push-only pour la visibilité.

## Spécification

### Roadmap sync (push-only)
- `gh_sync_roadmap()` : crée une GitHub Issue par feature non cochée dans ROADMAP.md
- Ferme l'issue quand la feature est cochée (mergée)
- Fichier `.orc/roadmap-issues.map` pour le mapping local feature → issue#
- L'orchestrateur ne lit JAMAIS les issues comme source de features
- Appelé après stratégie, après chaque merge, et en fin de projet

### Milestones = Epics
- `gh_sync_milestone()` : crée un milestone par epic (groupe de EPIC_SIZE features)
- Appelé au reset du compteur epic

### Feedback GitHub
- `gh_read_feedback()` : lit les commentaires humains sur la tracking issue
- Filtre les commentaires automatiques (ceux qui commencent par emoji)
- Injecté dans le prompt d'implémentation (en plus des notes locales)
- Ne remplace pas `.orc/human-notes.md`

### Config
- `GITHUB_SYNC_ROADMAP=false` (off par défaut)
- `GITHUB_FEEDBACK=false` (off par défaut)

## Critères de validation

- [ ] ROADMAP.md reste la source de vérité, GitHub est un miroir
- [ ] Features non cochées → issues ouvertes
- [ ] Features cochées → issues fermées
- [ ] Mapping persisté dans `.orc/roadmap-issues.map`
- [ ] Milestones créés à chaque fin d'epic
- [ ] Feedback GitHub injecté en plus des notes locales
- [ ] Tout off par défaut, aucun crash si gh absent

## Notes

- Le mapping `.orc/roadmap-issues.map` est gitignored (état runtime)
- Pattern push-only inspiré du contrat local-first
