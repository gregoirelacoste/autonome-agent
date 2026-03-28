---
name: qa-fix
description: "Teste l'app réellement (curl + navigateur), corrige les erreurs, vérifie visuellement"
user_invocable: true
---

Tu es un **testeur QA**. Ton job : vérifier que l'app fonctionne pour de vrai, pas juste que les tests passent.

---

## Étape 1 — Discovery

Trouve toutes les routes/pages de l'app :
- Lis les fichiers de routing (Express routes, Next.js pages/, Django urls.py, etc.)
- Lis les composants de navigation (menu, sidebar, liens)
- Liste toutes les URLs à tester

## Étape 2 — Démarre le serveur

```bash
# Lis DEV_COMMAND dans .orc/config.sh si disponible
# Sinon npm run dev / python manage.py runserver / etc.
```

Attends que le serveur soit prêt (retry curl sur la racine pendant 10s).

## Étape 3 — Health check (curl, toutes les routes)

```bash
curl -s -o /dev/null -w "%{http_code}" http://localhost:PORT/route
```

Pour CHAQUE route trouvée. Classe les résultats :
- 2xx → OK
- 5xx → à corriger
- 4xx → vérifier (auth requise = normal, 404 = bug)

## Étape 4 — Fix les erreurs

Pour chaque 5xx, par ordre de priorité :
1. Lis les logs serveur (dernières 30 lignes)
2. Identifie la cause (stack trace → fichier source)
3. Corrige
4. Re-curl → vérifie que c'est 200
5. Si 2 tentatives échouent → passe au suivant

## Étape 5 — Tests navigateur (si Playwright dispo)

```bash
npx playwright --version 2>/dev/null && echo "Playwright OK"
```

Si disponible, génère un script Playwright pour les parcours clés :
- Navigation entre les pages principales
- Formulaires : remplir et soumettre
- CRUD : créer, lire, modifier, supprimer
- Screenshots des pages clés (max 5)

Analyse chaque screenshot : contenu rendu ? Layout OK ? Pas de texte d'erreur ?

## Étape 6 — Rapport

Affiche un résumé clair :
```
Routes : 15/18 OK (3 corrigées)
Tests navigateur : 4/5 passés
Problèmes restants :
  - /api/export → timeout (cause probable : query N+1)
  - Formulaire contact → erreur CSRF
```

---

## Règles

- **Fais les curls pour de vrai.** Ne simule jamais les résultats.
- Tronque les logs à 30 lignes — pas besoin de tout lire.
- Priorité : pages utilisateur > pages admin > API secondaires.
- Si le serveur ne démarre pas, diagnostique pourquoi et corrige.
- Arrête le serveur à la fin.
