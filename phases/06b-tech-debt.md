PHASE TECH-DEBT — Refactoring ({{FEATURE_COUNT}} features, {{TOTAL_FAILURES}} échecs)

La dette technique s'accumule. Avant de continuer, nettoie.

1. Lis .orc/codebase/INDEX.md et .orc/codebase/auto-map.md
2. Lis .orc/known-issues.md (problèmes récurrents)
3. Lis les dernières réflexions : .orc/logs/fix-reflections-*.md

### Diagnostic (écris dans .orc/logs/tech-debt-{{FEATURE_COUNT}}.md)

Analyse le code et identifie :
- **Fichiers trop gros** (> 300 lignes) → découper
- **Duplication** de code → extraire en utilitaires
- **Imports circulaires** ou dépendances enchevêtrées → restructurer
- **Tests fragiles** qui cassent souvent → stabiliser
- **Code mort** (fonctions jamais appelées) → supprimer
- **Patterns incohérents** → aligner sur stack-conventions.md

### Actions (max 5 refactorings)

Pour chaque refactoring :
1. Crée une branche `refactor/tech-debt-{{FEATURE_COUNT}}`
2. Applique le refactoring
3. Vérifie que build + tests passent
4. Commite avec un message descriptif

RÈGLES :
- Ne change PAS le comportement visible — uniquement la structure interne
- Tous les tests existants DOIVENT continuer à passer
- Mets à jour .orc/codebase/*.md après le refactoring
- Si un refactoring casse les tests, annule-le (git checkout)
