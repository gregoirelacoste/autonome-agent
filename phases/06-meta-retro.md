MÉTA-RÉTROSPECTIVE — {{FEATURE_COUNT}} features complétées.

Lis tous les fichiers logs/retrospective-*.md et analyse les tendances.

### 1. Rétro technique
- Quels types d'erreurs reviennent le plus ?
- L'architecture tient-elle ou montre des signes de dette ?
- Le CLAUDE.md est-il devenu trop long ou contradictoire ? Nettoie-le.
- Quelles skills sont les plus/moins utilisées ?

### 2. Veille tendances (WebSearch)
- Nouveaux concurrents ou features chez les concurrents existants ?
- Discussions récentes sur les forums (nouveaux pain points ?)
- Nouvelles APIs ou technologies pertinentes ?
- Changements réglementaires ?
Mets à jour research/ avec les découvertes.

### 3. Positionnement produit
- Où en est-on vs les concurrents ? (mettre à jour SYNTHESIS.md avec colonne "nous")
- Quels différenciateurs a-t-on construits ?
- Quels gaps restent critiques ?

### 4. Repriorisation
- La ROADMAP est-elle toujours cohérente avec le BRIEF ?
- Faut-il ajouter des tâches de refactoring ?
- Faut-il reprioriser des features restantes ?
- Y a-t-il une feature existante à améliorer plutôt qu'une nouvelle à ajouter ?

### 5. Nettoyage
- CLAUDE.md : supprimer les règles obsolètes, réorganiser
- Skills : supprimer ou fusionner les skills inutiles
- research/INDEX.md : élaguer (max 50 lignes)
- Supprimer les fichiers research datés de plus de 3 mois sans validation

### Output
Écris un bilan dans logs/meta-retrospective-{{FEATURE_COUNT}}.md

Ne modifie PAS le code applicatif dans cette phase.
