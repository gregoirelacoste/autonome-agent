# ORC — Fonctions clés de orchestrator.sh

## Exécution Claude

### run_claude(prompt, max_turns, log_file, phase_name, feature_name, [system_prompt])
Point central — lance Claude CLI en background, monitore le heartbeat, détecte les stalls, enforce le timeout par phase, track les tokens. Injecte le contexte adaptatif (INDEX.md + auto-map.md pré-lus) selon la phase. Support multi-agent via `--append-system-prompt` optionnel. Apprentissage adaptatif des turns via `adaptive_max_turns()`.

### render_phase(phase_file, KEY=VALUE...)
Substitue {{VAR}} dans les prompts. Attention : `${content//pattern/replacement}` casse si replacement contient `/` ou `\`. Pour les outputs build/test, utiliser write_fix_prompt().

### write_fix_prompt(attempt, max_fix, build_exit, build_output, test_exit, test_output)
Construit le prompt de fix via fichier temporaire pour éviter les problèmes de caractères spéciaux.

### resolve_model(phase_name)
Choisit le modèle selon la phase. Hiérarchie à 3 tiers : `CLAUDE_MODEL_STRONG` pour les phases fortes (challenger), `CLAUDE_MODEL_LIGHT` pour les phases non-code (plan, reflect, research, etc.), `CLAUDE_MODEL` pour les phases critiques (implement, fix, critic). Fallback sur le tier inférieur si vide.

### get_model_pricing(model_name)
Résout le coût input/output par token selon le modèle. Table MODEL_PRICING avec préfixes triés par longueur décroissante. Fallback tarif Sonnet + warning si modèle inconnu.

### adaptive_max_turns(phase_name, default_max)
Calcule le max_turns optimal basé sur l'historique réel (p75 + 30% marge). Requiert 5+ échantillons valides. Ne dépasse jamais le défaut. Exclut les turns tronqués par max_turns pour éviter le feedback loop.

## Challenger (enrichissement pré-implémentation)

### peek_feature(n)
Retourne la Nième feature non-cochée de la ROADMAP sans la consommer. `peek_feature 2` retourne la feature suivante. Utilisé pour le lookahead du challenger.

### run_challenger_async(feature_name, feature_count)
Lance le challenger dans une subshell isolée (globales CLAUDE_PID, TMP_JSON indépendantes). Écrit le delta de coût dans `.orc/logs/.challenger-cost-N`. Guard fichier : skip si `challenger-N.md` existe déjà. Appelé avec `&` pour exécution en arrière-plan.

### collect_challenger_cost(feature_count)
Récupère le delta de coût du challenger async et l'intègre au `TOTAL_COST_USD` du parent. Nettoie le fichier temporaire.

## Connaissance projet

### generate_repo_map(project_dir)
Génère codebase/auto-map.md par grep des exports/classes. Multi-stack : TS/JS, Python, Java, Go, Astro. Tronqué à 200 lignes max.

### read_human_notes()
Lit .orc/human-notes.md et retourne le contenu formaté pour injection dans les prompts.

### smart_truncate(text, max_chars)
Troncation intelligente : garde le début (~1/6) et la fin (~5/6) pour ne pas perdre le message d'erreur initial.

## Contrôle & monitoring

### human_pause(reason)
Pause interactive avec options : c(ontinue), r(oadmap), l(ogs), t(okens), d(iff), s(ummary), f(eedback), n(otes), q(uit). Skippée en mode nohup.

### check_signals()
Vérifie les fichiers de signal : .orc/pause-requested, .orc/stop-after-feature, .orc/skip-feature, .orc/continue.

### notify(message)
Exécute NOTIFY_COMMAND si configuré.

### error_hash(output)
Extrait les lignes contenant error/fail/exception, supprime les numéros de ligne, trie et hashe. Compare la structure de l'erreur, pas sa position. Fallback sur head -20 si aucune ligne d'erreur.

## État & persistence

### save_state() / restore_state()
Sauvegarde/restaure tout l'état dans .orc/state.json : compteurs, tracking enrichi, features_timeline, workflow_phase, run_status.

### workflow_transition(target_phase)
Transitions de la state machine avec validation. Phases : init → bootstrap → research → strategy → features ⇄ evolve → post-project → done. Transitions d'urgence : *→crashed/stopped/budget_exceeded. Self-transitions pour la reprise.

### update_phase_tracking(phase, feature) / timeline_add() / timeline_update_last()
Tracking enrichi : feature en cours, phase, timestamps, historique avec status/timing/fix_attempts.

### init_tokens() / track_tokens(phase, feature, json, model, actual_turns) / print_cost_summary()
Tracking des tokens et coûts dans .orc/tokens.json. Modèle et turns trackés par phase et par invocation.

### migrate_config()
Migration auto au démarrage. Compare .orc/config.sh avec config.default.sh, ajoute les paramètres manquants. Traitement spécial pour PHASE_TIMEOUTS (declare -A).

### mark_feature_done_bash(feature_name)
Legacy : coche la feature dans ROADMAP.md via sed. Fallback quand le kanban n'est pas utilisé.

### migrate_to_kanban()
Migration auto au démarrage. Convertit le ROADMAP.md plat (lignes `- [ ]`) en fichiers tickets dans `.orc/roadmap/{todo,done}/`. Archive l'ancien fichier en `.legacy`.

## Kanban (système de tickets)

### init_kanban()
Crée la structure `.orc/roadmap/{backlog,todo,in-progress,done}/`.

### next_ticket()
Lit le prochain ticket dans `todo/`, trié par priorité P0→P3 puis par ID. Retourne le chemin du fichier.

### peek_ticket(n)
Retourne le titre du Nième ticket todo (pour le challenger lookahead).

### move_ticket(file, status)
Déplace un ticket entre statuts (ex: todo→in-progress, in-progress→done).

### ticket_title(file) / ticket_context(file)
Lit le titre (frontmatter) et le contenu markdown (après frontmatter) d'un ticket.

### has_todo_tickets() / count_todo_tickets()
Vérifie s'il reste des tickets à implémenter / compte les tickets todo.

### regenerate_roadmap_view()
Génère ROADMAP.md depuis le kanban (vue compat dashboard/status, format checkbox).

## Helpers

### next_feature()
Legacy : lit la prochaine feature non cochée de ROADMAP.md. Fallback quand le kanban n'est pas utilisé.

### branch_name(feature_name)
Sanitize le nom de feature pour créer un nom de branche git.

### run_in_project(command)
Exécute une commande dans PROJECT_DIR via subshell (pas de cd global).

### log(level, message)
Log avec couleurs + append dans orchestrator.log. Niveaux : INFO, WARN, ERROR, PHASE, COST.

### cleanup()
Trap EXIT/INT/TERM : kill Claude, save state, workflow_transition("crashed") si encore running, rm lock, rm temp files.

### run_functional_check(feature_name)
Exécute FUNCTIONAL_CHECK_COMMAND après chaque merge. Cycle de fix dédié si échec.

### update_changelog()
Met à jour le changelog du projet en fin de run. Génère un résumé des features implémentées, des métriques (coût, durée, taux de réussite) et du score de maturité.
