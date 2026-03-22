PHASE RÉTROSPECTIVE — Feature terminée : {{FEATURE_NAME}}
Tests passés : {{TESTS_PASSED}} | Tentatives de fix : {{FIX_ATTEMPTS}}

Analyse cette itération et améliore ton workflow :

1. **CLAUDE.md** — Ajoute des règles si tu as rencontré des pièges
   récurrents. Supprime des règles qui ne servent plus.
   Section dédiée : "## Règles apprises (auto-générées)"

2. **Skills** — Si tu as répété un pattern manuellement plus de 2 fois,
   crée un skill dans .claude/skills/.
   Si un skill existant était inadapté, mets-le à jour.

3. **ROADMAP.md** — Coche la feature terminée.
   Si l'implémentation t'a révélé de nouvelles dépendances
   ou features nécessaires, ajoute-les à la roadmap.

4. **Architecture** — Si tu as dû contourner l'architecture,
   note-le. Si ça s'accumule, ajoute une tâche de refactoring.

5. Écris un résumé dans logs/retrospective-{{N}}.md :
   - Ce qui a bien marché
   - Ce qui a posé problème
   - Ce qui a été ajouté/modifié dans les instructions
   - Temps estimé vs réel (nombre de turns)

Ne modifie PAS le code applicatif dans cette phase.
Uniquement la config, les skills, la roadmap et les logs.
