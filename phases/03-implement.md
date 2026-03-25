FEATURE À IMPLÉMENTER : {{FEATURE_NAME}}

### Avant de coder — consultation de l'index (OBLIGATOIRE)

1. **codebase/INDEX.md** — la carte sémantique du projet (TOUJOURS lire en premier).
   Identifie les sections pertinentes pour cette feature, puis lis SEULEMENT
   les fichiers de détail nécessaires :
   - `codebase/modules.md` si tu as besoin de connaître les exports existants
   - `codebase/utilities.md` si tu pourrais réutiliser un helper
   - `codebase/integrations.md` si la feature touche une API/service
   - `codebase/data-models.md` si tu manipules des données
   - `codebase/architecture.md` si tu dois comprendre un choix technique
   - `codebase/security.md` si la feature a un aspect sécurité
   **NE LIS PAS tous les fichiers — uniquement ceux pertinents pour cette feature.**
2. **codebase/auto-map.md** — la carte auto-générée des exports et classes du code.
   C'est la VÉRITÉ du code (généré par l'orchestrateur, pas par l'IA).
   Utilise-le pour localiser rapidement les modules et fonctions existants.
3. **.claude/skills/stack-conventions.md** — les conventions de la stack.
   Respecte-les. Si un anti-pattern est listé, ne le fais PAS.
4. Le code existant lié à cette feature
5. research/INDEX.md pour le contexte marché
6. La spec de cette feature dans ROADMAP.md
7. Les insights concurrents dans research/competitors/SYNTHESIS.md

### Anti-duplication — checklist AVANT de créer du code

Avant de créer une nouvelle fonction, un nouveau composant ou un nouveau helper :
- [ ] Vérifie dans codebase/INDEX.md puis le fichier de détail qu'il n'existe pas déjà
- [ ] Vérifie dans stack-conventions.md que le pattern est cohérent
- [ ] Si une utility similaire existe → l'enrichir plutôt qu'en créer une nouvelle
- [ ] Si un composant proche existe → le rendre paramétrique plutôt que dupliquer
- [ ] Si tu crées quelque chose de nouveau et réutilisable → note-le pour la phase reflect

### Workflow

1. Crée une branche : feature/{{FEATURE_BRANCH}}
2. Implémente la feature en respectant CLAUDE.md et stack-conventions.md
3. Écris les tests correspondants
4. Lance le build — corrige si erreur
5. Lance les tests — corrige si erreur
6. Auto-review (utilise le skill review-own-code) :
   - Code dupliqué avec l'existant (vérifier dans CODEBASE.md)
   - Failles de sécurité (injection, XSS, secrets, auth)
   - Patterns incohérents avec stack-conventions.md
   - Performance (requêtes N+1, re-renders, chargements inutiles)
   - Over-engineering (ne crée pas d'abstraction pour un seul usage)
7. Commite de façon atomique avec un message descriptif

Si un concurrent fait mieux que notre spec sur cette feature,
adapte l'implémentation et note le changement dans ROADMAP.md.
