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

Abandonne la feature en cours (la coche dans la ROADMAP) et passe à la suivante. Utile quand une feature est bloquée sans vouloir stopper tout le run.

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

## Modes d'autonomie

| Mode | Intervention | Config |
|---|---|---|
| **Pilote auto** | Aucune sauf urgence | `PAUSE=0, APPROVAL=false` |
| **Copilote** | Validation de chaque merge | `APPROVAL=true` |
| **Supervisé** | Review toutes les 3 features | `PAUSE=3` |

Configurable dans `.orc/config.sh`. Voir [configuration.md](configuration.md).
