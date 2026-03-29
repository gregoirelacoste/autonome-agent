# Documentation ORC — Index

> Ce fichier est lu par le skill `maintain-docs` pour savoir quels documents existent
> et lesquels mettre à jour. Toujours maintenir cet index à jour.

## Guides utilisateur

| Document | Couvre | Dernière MàJ |
|---|---|---|
| [getting-started.md](getting-started.md) | Installation, premier projet, lancement | v0.6.0 |
| [init-modes.md](init-modes.md) | Les 3 modes d'init : wizard, --brief, --skip-brief | v0.7.0 |
| [commands-reference.md](commands-reference.md) | Toutes les commandes CLI avec exemples | v0.7.0 |
| [configuration.md](configuration.md) | Paramètres config.sh, modes d'autonomie | v0.7.0 |
| [github-integration.md](github-integration.md) | Options GitHub : PR, tracking, signals, CI, releases | v0.7.0 |
| [human-controls.md](human-controls.md) | Pause, stop, notes, feedback, signaux, ticket, brainstorm | v0.7.0 |
| [faq.md](faq.md) | Questions fréquentes et troubleshooting | v0.7.0 |

## Documents techniques (dans codebase/)

| Document | Couvre |
|---|---|
| [../codebase/INDEX.md](../codebase/INDEX.md) | Carte sémantique du code orc |
| [../codebase/scripts.md](../codebase/scripts.md) | Vue d'ensemble des scripts |
| [../codebase/functions.md](../codebase/functions.md) | Fonctions clés orchestrator.sh |
| [../codebase/phases.md](../codebase/phases.md) | Phases d'orchestration |
| [../codebase/config-params.md](../codebase/config-params.md) | Paramètres de configuration |

## Documents racine

| Document | Couvre |
|---|---|
| [../README.md](../README.md) | Vue d'ensemble, quick start, commandes principales |
| [../ARCHITECTURE.md](../ARCHITECTURE.md) | Architecture technique complète |
| [../CLAUDE.md](../CLAUDE.md) | Guidelines développeur pour Claude Code |

## Règles de maintenance

1. **Chaque changement CLI** → mettre à jour `commands-reference.md` + help dans `orc.sh`
2. **Nouveau flag/option** → mettre à jour `commands-reference.md` + doc spécifique + README si majeur
3. **Nouveau mode d'init** → mettre à jour `init-modes.md`
4. **Changement config** → mettre à jour `configuration.md` + `codebase/config-params.md`
5. **Changement GitHub** → mettre à jour `github-integration.md`
6. **Toujours** → vérifier que le README reste cohérent (c'est la porte d'entrée)
