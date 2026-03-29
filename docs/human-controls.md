# Contrôle humain

L'orchestrateur offre plusieurs mécanismes pour intervenir sans l'arrêter.

## Signaux fichier (toujours disponibles)

### Notes humaines

```bash
vim ~/projects/mon-projet/.orc/human-notes.md
```

Contenu lu et injecté dans le prompt **avant chaque feature**. Permet de :
- Corriger une direction ("ne pas utiliser cette lib")
- Ajouter des contraintes ("prioritiser le mobile")
- Donner du feedback ("la feature X est bancale, refactorer")

Le fichier est lu puis vidé après injection. Tu peux écrire dedans à tout moment.

### Pause

```bash
touch ~/projects/mon-projet/.orc/pause-requested
```

L'orchestrateur termine la feature en cours puis se met en pause. Pour reprendre :

```bash
rm ~/projects/mon-projet/.orc/pause-requested
orc agent start mon-projet
```

### Arrêt propre

```bash
touch ~/projects/mon-projet/.orc/stop-after-feature
```

Comme pause, mais l'orchestrateur s'arrête complètement après la feature. Reprend au restart.

### Skip la feature en cours

```bash
touch ~/projects/mon-projet/.orc/skip-feature
```

Abandonne la feature en cours (déplace le ticket en `done`) et passe à la suivante. Utile quand une feature est bloquée sans vouloir stopper tout le run.

### Arrêt immédiat

```bash
orc agent stop mon-projet
```

Tue le process Claude en cours, sauvegarde l'état, libère le lock.

## Feedback structuré

```bash
vim ~/projects/mon-projet/.orc/logs/human-feedback-N.md
```

Feedback numéroté et structuré, prioritaire sur les observations de l'IA. Créé automatiquement lors des pauses en mode supervisé.

## Signaux GitHub (optionnels)

Si `GITHUB_SIGNALS=true` dans la config :

| Label sur la tracking issue | Effet |
|---|---|
| `orc:pause` | Pause après la feature en cours |
| `orc:stop` | Arrêt après la feature en cours |
| `orc:continue` | Reprendre |

Voir [github-integration.md](github-integration.md).

## Surveillance autonome (`orc watch`)

Lance un opérateur IA qui surveille le run en boucle (toutes les 3 minutes par défaut), diagnostique les crashes, corrige les bugs dans l'orchestrateur, et relance automatiquement.

```bash
orc watch mon-app                    # boucle auto 3min
orc watch mon-app --interval 5m     # intervalle personnalisé
orc watch mon-app --interactive     # mode chat (intervention manuelle)
orc watch stop mon-app              # arrêter la surveillance
```

En mode boucle, chaque check est léger (~3K tokens). L'opérateur n'intervient que si un problème est détecté. Les améliorations non-urgentes sont notées en roadmap.

## Checkpoint d'alignement

Quand `ALIGNMENT_CHECK=true` (défaut), l'orchestrateur s'arrête après chaque cycle evolve pour valider la direction avec l'humain.

1. Le run termine ses features → evolve ajoute de nouvelles features → **le run s'arrête**
2. Statut : `alignement requis` (visible dans `orc status`)
3. Au prochain `orc agent start`, un **wizard interactif** pose 5 questions :
   - Direction toujours bonne ?
   - Features à retirer/réordonner ?
   - Besoin nouveau ?
   - Critère de "suffisant" ?
   - Feedback libre ?
4. Les réponses sont injectées dans les features du prochain cycle

Désactiver : `ALIGNMENT_CHECK=false` dans `.orc/config.sh`.

## Ajout de tickets (`orc roadmap ticket`)

L'humain peut ajouter des tickets au kanban d'un projet à tout moment, même pendant un run :

```bash
orc roadmap ticket mon-projet                        # Dialogue + challenge IA
orc roadmap ticket mon-projet --quick "export CSV"   # Mode rapide
orc r t mon-projet                                   # Raccourci
```

Le pipeline IA challenge le ticket (pertinence, faisabilité, doublons), recherche sur le web si pertinent, et rédige un ticket structuré. L'humain valide avant l'ajout au kanban.

**Hot injection** : les tickets P0 ajoutés pendant un run sont signalés via `human-notes.md` et pris en priorité au prochain cycle.

## Brainstorm (`orc roadmap brainstorm`)

Pour planifier une nouvelle itération (surtout après un projet "terminé") :

```bash
orc roadmap brainstorm mon-projet   # Pipeline complet 5 phases
orc r brain mon-projet              # Raccourci
```

L'IA dialogue avec l'humain sur sa vision, audite le MVP, recherche la concurrence, propose 15-20 tickets, puis l'humain sélectionne ceux à garder. Les tickets validés sont écrits dans le kanban.

## Modes d'autonomie

| Mode | Intervention | Config |
|---|---|---|
| **Pilote auto** | Aucune sauf urgence | `PAUSE=0, APPROVAL=false` |
| **Copilote** | Validation de chaque merge | `APPROVAL=true` |
| **Supervisé** | Review toutes les 3 features | `PAUSE=3` |

Configurable dans `.orc/config.sh`. Voir [configuration.md](configuration.md).
