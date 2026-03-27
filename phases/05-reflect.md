PHASE RÉTROSPECTIVE — Feature terminée : {{FEATURE_NAME}}
Tests passés : {{TESTS_PASSED}} | Tentatives de fix : {{FIX_ATTEMPTS}}

Si un fichier .orc/logs/human-feedback-*.md existe pour une feature récente,
lis-le attentivement. Le feedback humain est PRIORITAIRE sur tes propres observations.

Analyse cette itération et améliore tes connaissances du projet :

### 1. .orc/codebase/ — Index & fichiers de détail (OBLIGATOIRE)

Mets à jour les fichiers de détail dans `.orc/codebase/` avec ce que tu as créé/modifié :
- **.orc/codebase/modules.md** — nouvelles fonctions, classes, composants exportés
- **.orc/codebase/utilities.md** — tout ce qui est réutilisable (ne pas dupliquer ensuite !)
- **.orc/codebase/integrations.md** — nouvelles APIs/services intégrés
- **.orc/codebase/data-models.md** — nouveaux modèles, types, interfaces partagées
- **.orc/codebase/architecture.md** — si tu as fait un choix technique, note POURQUOI
- **.orc/codebase/security.md** — patterns de sécurité appliqués, vérifications faites

Format pour chaque entrée dans les fichiers de détail :
`- nom() dans chemin/fichier.ext — description courte de ce que ça fait`

Vérifie **.orc/codebase/auto-map.md** (généré automatiquement par l'orchestrateur) :
- Compare-le avec tes fichiers de détail — y a-t-il des exports non documentés ?
- Si oui, ajoute-les dans le fichier de détail approprié

Puis mets à jour **.orc/codebase/INDEX.md** :
- Ajoute/modifie le résumé d'une phrase par section impactée
- L'index doit rester COMPACT (max 40 lignes)
- L'index est une carte : il dit CE QUI EXISTE et OÙ TROUVER LE DÉTAIL
- Ne mets PAS le détail dans l'index — seulement le nom + renvoi au fichier

### 2. stack-conventions.md — Conventions de stack

Mets à jour `.claude/skills/stack-conventions.md` avec :
- Nouveaux patterns découverts spécifiques à la stack
- Nouveaux anti-patterns identifiés (si tu as fait une erreur, note-la)
- Nouvelles utilities créées (pour ne pas les dupliquer)
- Optimisations de performance appliquées
- Patterns de sécurité validés pour ce projet

### 3. CLAUDE.md — Règles apprises

Ajoute des règles si tu as rencontré des pièges récurrents.
Supprime des règles qui ne servent plus.
Section dédiée : "## Règles apprises (auto-générées)"

### 4. Skills

Si tu as répété un pattern manuellement plus de 2 fois,
crée un skill dans .claude/skills/.
Si un skill existant était inadapté, mets-le à jour.

### 5. .orc/ROADMAP.md

Coche la feature terminée.
Si l'implémentation t'a révélé de nouvelles dépendances,
features nécessaires, bugs ou améliorations :
- Crée un item dans `roadmap/backlog/` en suivant le format
  défini dans le skill `roadmap-item.md`
- Chaque item = un fichier ROADMAP-NNN-slug.md avec frontmatter YAML
- Assigne une priorité (P0-P3), un type, un effort estimé, des tags
- Référence la feature courante dans la section Contexte

### 6. Architecture & Sécurité

- Si tu as dû contourner l'architecture, note-le dans .orc/codebase/architecture.md
- Si ça s'accumule, ajoute une tâche de refactoring à la roadmap
- Note les vérifications de sécurité effectuées (auth, validation, injection, secrets)

### 7. Rétrospective

Écris un résumé dans logs/retrospective-{{N}}.md :
- Ce qui a bien marché
- Ce qui a posé problème
- Code réutilisé vs créé (mesure de l'anti-duplication)
- Ce qui a été ajouté/modifié dans les instructions
- Temps estimé vs réel (nombre de turns)

Ne modifie PAS le code applicatif dans cette phase.
Uniquement codebase/, les skills, CLAUDE.md, la roadmap et les logs.
