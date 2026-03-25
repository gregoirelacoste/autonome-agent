---
name: stack-conventions
description: Conventions bash et patterns de l'orchestrateur ORC
user_invocable: true
---

## Stack : Bash 5+ (orchestrateur)

## Conventions de code
- `set -euo pipefail` en haut de chaque script
- `printf` au lieu de `echo -e` pour la portabilité des couleurs
- Chemins absolus via `realpath` au démarrage (PROJECT_DIR, LOG_DIR)
- Pas de `cd` nu — utiliser `run_in_project()` (subshell)
- Variables globales en MAJUSCULES, locales en minuscules avec `local`
- Fonctions nommées en snake_case

## Patterns adoptés
- Lockfile PID-based (.orc/.lock) pour empêcher l'exécution concurrente
- Signal handling via `trap cleanup EXIT INT TERM`
- State persistence JSON (.orc/state.json) pour reprise après crash
- Dégradation gracieuse si jq absent (pas de crash)
- Phases comme fichiers .md séparés, pas inline dans le bash
- Placeholders {{VAR}} dans les phases, substitués par render_phase()

## Anti-patterns identifiés
- NE PAS utiliser render_phase() pour les outputs build/test (caractères spéciaux) → utiliser write_fix_prompt()
- NE PAS hardcoder de valeurs → tout dans config.default.sh
- NE PAS utiliser `eval` avec des entrées non sanitisées
- NE PAS modifier le template ORC depuis un projet — le workspace est une copie

## Utilities existantes (NE PAS dupliquer)
- `log()` — logging avec couleurs + fichier
- `run_in_project()` — exécution dans PROJECT_DIR
- `run_claude()` — invocation Claude avec monitoring complet
- `render_phase()` — substitution de placeholders
- `save_state()` / `restore_state()` — persistence des compteurs
- `notify()` — notifications configurables
- `check_signals()` — signaux file-based
- `generate_repo_map()` — carte auto-générée du code
- `error_hash()` — hash d'erreur pour détection de boucle

## Sécurité
- Sanitize les noms de feature pour les branches git (branch_name())
- Pas de secrets dans les logs ou les prompts
- Lockfile avec vérification de PID vivant

## Performance
- stream-json au lieu de json pour le output Claude (watchdog temps réel)
- Truncation des outputs build/test à 3000 chars dans les prompts
- auto-map.md tronqué à 200 lignes
