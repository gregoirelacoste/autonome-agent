MÉTA-RÉTROSPECTIVE — {{FEATURE_COUNT}} features complétées.

Lis tous les fichiers .orc/logs/retrospective-*.md et analyse les tendances.
Lis AUSSI tous les fichiers .orc/logs/human-feedback-*.md — le feedback humain
est PRIORITAIRE et doit influencer tes décisions de repriorisation.

### 1. Rétro technique & santé du codebase
- Quels types d'erreurs reviennent le plus ?
- L'architecture tient-elle ou montre des signes de dette ?
- Le CLAUDE.md est-il devenu trop long ou contradictoire ? Nettoie-le.
- Quelles skills sont les plus/moins utilisées ?
- **.orc/codebase/INDEX.md** est-il à jour ? Y a-t-il des modules non documentés ?
- Les fichiers de détail (modules.md, utilities.md, etc.) reflètent-ils le code réel ?
- L'index est-il resté compact (< 40 lignes) ou faut-il l'élaguer ?
- Y a-t-il du code dupliqué qui aurait dû être factorisé ? (grep les patterns similaires)
- Les conventions de stack-conventions.md sont-elles respectées dans tout le code ?

### 2. Veille tendances (WebSearch)
- Nouveaux concurrents ou features chez les concurrents existants ?
- Discussions récentes sur les forums (nouveaux pain points ?)
- Nouvelles APIs ou technologies pertinentes ?
- Changements réglementaires ?
Mets à jour .orc/research/ avec les découvertes.

### 3. Positionnement produit
- Où en est-on vs les concurrents ? (mettre à jour SYNTHESIS.md avec colonne "nous")
- Quels différenciateurs a-t-on construits ?
- Quels gaps restent critiques ?

### 4. Repriorisation
- La .orc/ROADMAP.md est-elle toujours cohérente avec le .orc/BRIEF.md ?
- Faut-il ajouter des tâches de refactoring ?
- Faut-il reprioriser des features restantes ?
- Y a-t-il une feature existante à améliorer plutôt qu'une nouvelle à ajouter ?

### 5. Nettoyage & consolidation
- CLAUDE.md : supprimer les règles obsolètes, réorganiser
- Skills : supprimer ou fusionner les skills inutiles
- stack-conventions.md : vérifier la cohérence, supprimer les conventions qui ne s'appliquent plus
- .orc/codebase/ : vérifier que l'index et les fichiers de détail reflètent le code réel, supprimer les entrées obsolètes, s'assurer que l'index reste compact
- .orc/research/INDEX.md : élaguer (max 50 lignes)
- Supprimer les fichiers .orc/research/ datés de plus de 3 mois sans validation
- Identifier le code dupliqué → ajouter un item de refactoring si nécessaire

### Output
Écris un bilan dans .orc/logs/meta-retrospective-{{FEATURE_COUNT}}.md

Ne modifie PAS le code applicatif dans cette phase.
