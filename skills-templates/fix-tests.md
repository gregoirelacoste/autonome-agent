---
name: fix-tests
description: Diagnostique et corrige les tests qui échouent
user_invocable: true
---

## Workflow de correction

1. **Lire** — Lis le rapport d'erreur complet (pas juste la première ligne)
2. **Catégoriser** :
   - Erreur de build (TypeScript, import, config) → corriger le code
   - Test qui timeout → ajouter un waitFor / vérifier les selectors
   - Assertion échouée → le code ou le test est incorrect, déterminer lequel
   - Erreur d'environnement → vérifier la config
3. **Corriger** — Corriger la cause racine, pas le symptôme
4. **Ne JAMAIS** désactiver ou skip un test
5. **Relancer** — Le test corrigé seul d'abord, puis la suite complète
6. **Commit** — `fix(tests): <description>`
7. **Apprendre** — Si c'est un piège récurrent, ajouter une règle dans CLAUDE.md
