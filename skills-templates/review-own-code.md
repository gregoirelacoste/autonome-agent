---
name: review-own-code
description: Auto-review du code avant commit
user_invocable: true
---

## Checklist d'auto-review

Avant chaque commit, vérifier :

### Correctness
- [ ] La feature correspond aux critères d'acceptance de la ROADMAP
- [ ] Pas de TODO ou code commenté laissé en place
- [ ] Les edge cases sont gérés

### Qualité
- [ ] Pas de code dupliqué avec l'existant
- [ ] Nommage clair et cohérent avec le reste du projet
- [ ] Pas de fichier trop long (>300 lignes → découper)

### Sécurité
- [ ] Pas d'injection possible (SQL, XSS, command)
- [ ] Pas de secrets en dur
- [ ] Validation des entrées utilisateur

### Performance
- [ ] Pas de requêtes N+1
- [ ] Pas de re-renders inutiles (React)
- [ ] Pas de données chargées inutilement

### Tests
- [ ] Tests E2E couvrent le happy path
- [ ] Tests couvrent au moins un cas d'erreur
