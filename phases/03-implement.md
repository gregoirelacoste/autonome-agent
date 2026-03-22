FEATURE À IMPLÉMENTER : {{FEATURE_NAME}}

Avant de coder, lis :
1. Le code existant lié à cette feature
2. research/INDEX.md pour le contexte marché
3. La spec de cette feature dans ROADMAP.md
4. Les insights concurrents pertinents dans research/competitors/SYNTHESIS.md

Workflow :
1. Crée une branche : feature/{{FEATURE_BRANCH}}
2. Implémente la feature en respectant CLAUDE.md
3. Écris les tests E2E Playwright correspondants
4. Lance le build — corrige si erreur
5. Lance les tests — corrige si erreur
6. Auto-review : relis ton propre code, cherche :
   - Code dupliqué avec l'existant
   - Failles de sécurité évidentes
   - Patterns incohérents avec le reste du projet
   - Performance (requêtes N+1, re-renders inutiles, etc.)
7. Commite de façon atomique avec un message descriptif

Si un concurrent fait mieux que notre spec sur cette feature,
adapte l'implémentation et note le changement dans ROADMAP.md.
