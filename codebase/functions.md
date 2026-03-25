# ORC — Fonctions clés de orchestrator.sh

## Exécution Claude

### run_claude(prompt, max_turns, log_file, phase_name, feature_name)
Point central — lance Claude CLI en background, monitore le heartbeat, détecte les stalls, enforce le timeout, track les tokens. Injecte le contexte adaptatif selon la phase. Toute modification ici impacte tout le système.

### render_phase(phase_file, KEY=VALUE...)
Substitue {{VAR}} dans les prompts. Attention : `${content//pattern/replacement}` casse si replacement contient `/` ou `\`. Pour les outputs build/test, utiliser write_fix_prompt().

### write_fix_prompt(attempt, max_fix, build_exit, build_output, test_exit, test_output)
Construit le prompt de fix via fichier temporaire pour éviter les problèmes de caractères spéciaux.

## Connaissance projet

### generate_repo_map(project_dir)
Génère codebase/auto-map.md par grep des exports/classes. Multi-stack : TS/JS, Python, Java, Go, Astro. Tronqué à 200 lignes max.

### read_human_notes()
Lit .orc/human-notes.md et retourne le contenu formaté pour injection dans les prompts.

## Contrôle & monitoring

### human_pause(reason)
Pause interactive avec options : c(ontinue), r(oadmap), l(ogs), t(okens), d(iff), s(ummary), f(eedback), n(otes), q(uit). Skippée en mode nohup.

### check_signals()
Vérifie les fichiers de signal : .orc/pause-requested, .orc/stop-after-feature, .orc/continue.

### notify(message)
Exécute NOTIFY_COMMAND si configuré.

### error_hash(output)
Hash MD5 des 20 premières lignes d'une erreur pour détecter les boucles de fix.

## État & persistence

### save_state()
Sauvegarde feature_count, epic_feature_count, total_failures, evolve_cycles, ai_roadmap_adds dans .orc/state.json.

### restore_state()
Restaure les compteurs depuis .orc/state.json pour reprise après crash.

### init_tokens() / track_tokens(phase, feature, json) / print_cost_summary()
Tracking des tokens et coûts dans .orc/tokens.json.

## Helpers

### next_feature()
Lit la prochaine feature non cochée de ROADMAP.md.

### branch_name(feature_name)
Sanitize le nom de feature pour créer un nom de branche git.

### run_in_project(command)
Exécute une commande dans PROJECT_DIR via subshell (pas de cd global).

### log(level, message)
Log avec couleurs + append dans orchestrator.log. Niveaux : INFO, WARN, ERROR, PHASE, COST.

### cleanup()
Trap EXIT/INT/TERM : kill Claude, save state, rm lock, rm temp files.
