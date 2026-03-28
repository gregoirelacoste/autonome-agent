REVIEW ADVERSARIALE — Feature : {{FEATURE_NAME}}

Tu es un REVIEWER, pas le développeur. Ton rôle est de trouver les problèmes AVANT les tests.

Lis le diff de la branche courante vs main :
```
git diff main...HEAD
```

Cherche spécifiquement :
1. **Imports manquants ou incorrects** — modules référencés mais non importés
2. **Typos dans les noms** — variables/fonctions mal orthographiées
3. **Logique inversée** — conditions if/else dans le mauvais sens
4. **Données non validées** — input utilisateur non sanitisé
5. **Cas edge oubliés** — null, undefined, liste vide, chaîne vide
6. **Incohérences avec l'existant** — patterns différents du reste du code
7. **Tests manquants ou incomplets** — cas critiques non testés

RÈGLES :
- Si tu trouves des problèmes, corrige-les directement dans le code.
- Si le code est propre, dis-le en une ligne et arrête.
- Max 3 corrections. Ne réécris pas tout.
