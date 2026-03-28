PHASE STRATÉGIE

Tu as fait ta recherche initiale. Transforme-la en plan d'action.

1. Lis .orc/research/INDEX.md et tous les SYNTHESIS.md
2. Relis .orc/BRIEF.md (la vision immuable)

### Étape 1 : Scoring du brief

Évalue le brief sur ces critères et écris le résultat dans .orc/logs/brief-scoring.md :

| Critère | Score (1-5) | Commentaire |
|---------|-------------|-------------|
| Clarté du problème utilisateur | | |
| Scope MVP défini | | |
| Stack / contraintes techniques claires | | |
| Critères de succès mesurables | | |
| Utilisateurs cibles identifiés | | |

Si le score total est < 15/25, écris les questions manquantes dans .orc/logs/brief-scoring.md
et ajoute des hypothèses raisonnables pour combler les manques. Note-les dans CLAUDE.md.

### Étape 2 : Roadmap MVP-first

Produis une .orc/ROADMAP.md structurée en 2 phases :

```
## MVP — Fonctionnel minimum (5-8 features max)
Objectif : un utilisateur peut [action principale du brief] de bout en bout.
- [ ] Feature 1 — description | critères d'acceptance
- [ ] Feature 2 — description | critères d'acceptance
...

## Améliorations — Post-MVP (optionnel, si temps/budget)
- [ ] Feature N — description | critères d'acceptance
```

Règles :
- **Le MVP DOIT être fonctionnel seul** — pas de dépendance vers les features post-MVP
- Chaque feature MVP DOIT contribuer au parcours utilisateur principal
- Les quick wins (haute valeur, faible effort) en premier dans le MVP
- Les features de fondation technique avant les features avancées
- Critères d'acceptance = comment vérifier que c'est fait (testable)
- Chaque feature référence un insight de .orc/research/ si pertinent
- **Maximum 15 features totales** (MVP + améliorations) — ne pas over-scoper

Mets à jour CLAUDE.md avec les patterns techniques
découverts pendant la recherche (APIs à utiliser, conventions du domaine, etc.)
