VALIDATION ACCEPTANCE — Epic terminé ({{EPIC_NUMBER}} — {{FEATURE_COUNT}} features)

L'epic est terminé. Vérifie que le produit fait ce que le BRIEF demande.

1. Lis .orc/BRIEF.md — les user stories / objectifs du produit
2. Lis .orc/ROADMAP.md — les features cochées de cet epic
3. Pour chaque feature cochée de l'epic, vérifie :
   - Le code correspondant existe-t-il ?
   - Un test couvre-t-il le scénario utilisateur ?
   - Le scénario fonctionne-t-il de bout en bout ?

4. Si possible, lance l'application et teste manuellement :
   - Utilise la COMMANDE DEV SERVER fournie ci-dessous pour démarrer
   - Navigue les scénarios utilisateur clés
   - Vérifie que les données s'affichent / se sauvegardent

5. Écris un rapport dans .orc/logs/acceptance-{{EPIC_NUMBER}}.md :
   ```
   ## Acceptance — Epic {{EPIC_NUMBER}}

   ### Scénarios validés
   - [ ] [scénario 1 du brief] — [résultat]
   - [ ] [scénario 2] — [résultat]

   ### Problèmes trouvés
   - [problème] → [correction appliquée ou à planifier]

   ### Score : X/Y scénarios passés
   ```

6. Si des problèmes critiques sont trouvés, corrige-les directement.
   Ne crée PAS de nouvelles features — corrige le code existant.

7. Génère des smoke tests persistants si la stack le permet :
   - Crée les smoke tests dans le dossier de tests existant du projet
   - Chaque test vérifie un scénario utilisateur validé dans le rapport
   - Ces tests s'ajoutent aux tests existants et persistent entre les features
   - Format : un test par scénario d'acceptance validé

RÈGLES :
- Max 5 corrections. Les problèmes non critiques vont en backlog.
- Le critère c'est "l'utilisateur peut faire X", pas "le code est propre".
- Les smoke tests doivent être simples et stables (pas de tests flaky).
