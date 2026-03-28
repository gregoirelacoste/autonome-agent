---
name: implement-feature
description: Workflow complet d'implémentation d'une feature
user_invocable: true
---

## Workflow d'implémentation

1. **Comprendre** — Lis la spec dans .orc/ROADMAP.md + les insights .orc/research/ pertinents
2. **Explorer** — Lis le code existant lié à cette feature
3. **Brancher** — `git checkout -b feature/<nom-court>`
4. **Coder** — Implémente en respectant CLAUDE.md
5. **Tester** — Écris les tests E2E Playwright
6. **Build** — `npm run build` doit passer
7. **Review** — Relis ton code : duplication, sécurité, cohérence, performance
8. **Commit** — Message descriptif, atomique
