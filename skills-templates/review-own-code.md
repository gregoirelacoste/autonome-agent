---
name: review-own-code
description: Auto-review du code avant commit
user_invocable: true
---

## Checklist d'auto-review

Avant chaque commit, vérifier :

### Anti-duplication (consulter codebase/INDEX.md)
- [ ] Pas de nouvelle utility qui duplique une existante (vérifier codebase/utilities.md)
- [ ] Pas de nouveau composant qui duplique un existant (vérifier codebase/modules.md)
- [ ] Les patterns utilisés sont cohérents avec stack-conventions.md
- [ ] Si une nouvelle utility réutilisable a été créée → la noter pour la phase reflect

### Correctness
- [ ] La feature correspond aux critères d'acceptance de la ROADMAP
- [ ] Pas de TODO ou code commenté laissé en place
- [ ] Les edge cases sont gérés

### Qualité
- [ ] Nommage clair et cohérent avec le reste du projet
- [ ] Pas de fichier trop long (>300 lignes → découper)
- [ ] Pas d'over-engineering (pas d'abstraction pour un seul usage)
- [ ] Les conventions de stack-conventions.md sont respectées

### Sécurité
- [ ] Pas d'injection possible (SQL, XSS, command)
- [ ] Pas de secrets en dur (API keys, passwords, tokens)
- [ ] Validation des entrées utilisateur
- [ ] Auth/authz vérifié sur les endpoints sensibles
- [ ] Pas de données sensibles dans les logs

### Performance
- [ ] Pas de requêtes N+1
- [ ] Pas de re-renders inutiles (frameworks réactifs)
- [ ] Pas de données chargées inutilement
- [ ] Pagination pour les listes potentiellement longues

### Tests
- [ ] Tests couvrent le happy path
- [ ] Tests couvrent au moins un cas d'erreur
- [ ] Tests cohérents avec les patterns de test existants
