PHASE RÉTROSPECTIVE — Feature terminée : {{FEATURE_NAME}}
Tests passés : {{TESTS_PASSED}} | Tentatives de fix : {{FIX_ATTEMPTS}}

Si un fichier logs/human-feedback-*.md existe pour une feature récente,
lis-le attentivement. Le feedback humain est PRIORITAIRE sur tes propres observations.

Analyse cette itération et améliore ton workflow :

1. **CLAUDE.md** — Ajoute des règles si tu as rencontré des pièges
   récurrents. Supprime des règles qui ne servent plus.
   Section dédiée : "## Règles apprises (auto-générées)"

2. **Skills** — Si tu as répété un pattern manuellement plus de 2 fois,
   crée un skill dans .claude/skills/.
   Si un skill existant était inadapté, mets-le à jour.

3. **ROADMAP.md** — Coche la feature terminée.
   Si l'implémentation t'a révélé de nouvelles dépendances,
   features nécessaires, bugs ou améliorations :
   - Crée un item dans `roadmap/backlog/` en suivant le format
     défini dans le skill `roadmap-item.md`
   - Chaque item = un fichier ROADMAP-NNN-slug.md avec frontmatter YAML
   - Assigne une priorité (P0-P3), un type, un effort estimé, des tags
   - Référence la feature courante dans la section Contexte

4. **Architecture** — Si tu as dû contourner l'architecture,
   note-le. Si ça s'accumule, ajoute une tâche de refactoring.

5. Écris un résumé dans logs/retrospective-{{N}}.md :
   - Ce qui a bien marché
   - Ce qui a posé problème
   - Ce qui a été ajouté/modifié dans les instructions
   - Temps estimé vs réel (nombre de turns)

Ne modifie PAS le code applicatif dans cette phase.
Uniquement la config, les skills, la roadmap et les logs.
