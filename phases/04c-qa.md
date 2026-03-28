PHASE QA — Test fonctionnel réel après l'Epic {{EPIC_NUMBER}}

L'epic {{EPIC_NUMBER}} ({{FEATURE_COUNT}} features) est terminé. Vérifie que l'app fonctionne RÉELLEMENT, pas juste que les tests passent.

---

### Étape 1 — Discovery des routes (bash, pas de lecture de fichier inutile)

Identifie toutes les routes/pages de l'app en analysant le code :
- Frameworks web : cherche les déclarations de routes (Express app.get/post, Next.js pages/, Django urls.py, Flask @app.route, etc.)
- Liens dans les templates/composants
- Liste les routes trouvées dans ton output

### Étape 2 — Health check (bash, curl)

Lance le serveur dev :
```bash
{{DEV_COMMAND}} &
sleep 5
```

Puis teste CHAQUE route avec curl :
```bash
curl -s -o /dev/null -w "%{http_code}" http://localhost:{{PORT}}/route
```

Classe les résultats :
- 2xx → OK
- 3xx → redirect (OK si intentionnel)
- 4xx → vérifier si c'est normal (auth requise ?) ou bug
- 5xx → BUG, à corriger

### Étape 3 — Fix des erreurs serveur

Pour chaque erreur 5xx, dans l'ordre de priorité (pages critiques d'abord) :
1. Lis les logs serveur (dernières 30 lignes après le curl)
2. Identifie la stack trace et le fichier source
3. Lis le fichier source
4. Corrige le bug
5. Re-teste avec curl → 200 ? → passe au suivant
6. Si échec après 2 tentatives → note dans le rapport, passe au suivant

**Max 5 fixes.** Les erreurs restantes vont dans le rapport.

### Étape 4 — Test navigateur (si Playwright disponible)

Vérifie si Playwright est installé :
```bash
npx playwright --version 2>/dev/null
```

**Si disponible** : génère et exécute un script de test pour les parcours utilisateur clés.

Scénarios à tester (basés sur les features de l'epic, lis .orc/ROADMAP.md) :
- Page d'accueil : se charge, contenu visible
- Navigation : liens principaux fonctionnent
- Formulaires : remplir + soumettre (si applicable)
- CRUD : créer/lire un élément (si applicable)
- Max 5 scénarios

Pour chaque scénario, capture un screenshot :
```javascript
await page.screenshot({ path: '.orc/logs/qa-screenshot-N.png' })
```

Analyse chaque screenshot : le contenu est-il rendu ? Layout cassé ? Texte d'erreur visible ?

**Si Playwright non disponible** : skip cette étape, note-le dans le rapport.

### Étape 5 — Rapport

Écris `.orc/logs/qa-report-{{EPIC_NUMBER}}.md` :

```markdown
## QA Report — Epic {{EPIC_NUMBER}}

### Routes testées
- [x] / — 200 OK
- [x] /api/items — 200 OK
- [ ] /admin — 500 (corrigé → 200)
- [ ] /api/export — 500 (non résolu : [raison])

### Tests navigateur
- [x] Page d'accueil : contenu rendu correctement
- [ ] Formulaire inscription : erreur JS dans la console
- Screenshots : .orc/logs/qa-screenshot-*.png

### Résumé
- Routes : X/Y OK (Z corrigées)
- Tests navigateur : A/B passés
- Problèmes non résolus : [liste]
```

N'oublie pas d'arrêter le serveur dev à la fin.

---

RÈGLES :
- Fais les curls en bash, ne simule pas les résultats.
- Tronque les logs serveur à 30 lignes — ne lis pas tout le fichier.
- Max 5 fixes, max 5 scénarios navigateur, max 5 screenshots.
- Si le serveur ne démarre pas, signale-le et arrête-toi.
- Le critère c'est "l'utilisateur peut utiliser l'app", pas "le code est propre".
