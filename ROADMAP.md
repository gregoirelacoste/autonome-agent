# Roadmap — Autonome Agent

## Historique (fait)

### v0.1.0 — Prototype
- [x] Architecture conceptuelle complète (ARCHITECTURE.md)
- [x] Orchestrateur bash avec boucle feature (implement → test → fix → reflect)
- [x] 8 prompts de phases (bootstrap → evolve)
- [x] 4 skills templates (implement, fix-tests, research, review-own-code)
- [x] Config externalisée (config.sh)

### v0.2.0 — Brief & Skills
- [x] Skill write-brief : Claude product director (22 questions structurées)
- [x] Mode --brief dans l'orchestrateur

### v0.3.0 — Séparation template/workspace
- [x] init.sh : wizard interactif en 5 étapes
- [x] Workspace créé dans un dossier séparé (pas dans le template)
- [x] config.default.sh (template) vs config.sh (projet)
- [x] README.md complet
- [x] Mode --brief déplacé dans init.sh

### v0.4.0 — Observabilité
- [x] Token tracking (logs/tokens.json) avec breakdown par phase et feature
- [x] Estimation de coût en temps réel
- [x] MAX_BUDGET_USD : hard stop si budget dépassé
- [x] Phase self-improve : suggestions d'amélioration post-projet

### v0.5.0 — Production-ready
- [x] Signal handling (trap EXIT/INT/TERM, kill Claude proprement)
- [x] Lockfile anti-exécution concurrente
- [x] State persistence (state.json, reprise après crash)
- [x] Watchdog stall detection (warning après 2min sans données)
- [x] CLAUDE_TIMEOUT : kill après N secondes
- [x] run_in_project() : subshells au lieu de cd/cd-
- [x] human_pause skip en mode nohup
- [x] git checkout main entre les features
- [x] write_fix_prompt() pour les outputs build/test (contourne render_phase)
- [x] printf au lieu de echo -e
- [x] Validation entiers pour le tracking tokens
- [x] Tags de version (v0.1.0 → v0.5.0)

---

## Backlog (à faire)

### v0.6.0 — Déploiement VPS + CLI agent
> Objectif : gérer l'orchestrateur depuis n'importe où (SSH mobile/desktop)

- [ ] `deploy.sh` — script d'installation one-shot sur VPS Ubuntu/Debian
  - Installe Node.js 22, jq, git, Claude Code CLI
  - Clone le repo template dans `/opt/orc/`
  - Configure `ANTHROPIC_API_KEY` dans `.env`
  - Crée `~/projects/` et symlink `agent` global
- [ ] `agent.sh` — CLI de gestion multi-projets
  - `agent new <nom>` — crée un workspace (interactif ou `--brief`)
  - `agent start <nom>` — lance l'orchestrateur en background (nohup + .pid)
  - `agent stop <nom>` — arrêt propre (SIGTERM → 30s → SIGKILL)
  - `agent restart <nom>` — stop + start
  - `agent status` — tableau de tous les projets (running/stopped/done, features, coût)
  - `agent status <nom>` — détail d'un projet
  - `agent logs <nom>` — tail -f en temps réel
  - `agent logs <nom> --full` — log complet (less)
  - `agent update` — git pull du template
- [ ] `briefs/` — dossier pour stocker des briefs réutilisables dans le template
  - `briefs/pc-builder.md` — le brief PC Builder comme exemple
- [ ] Mettre à jour `.gitignore` (permettre briefs/, ignorer .env)
- [ ] Mettre à jour `README.md` — section VPS + agent CLI
- [ ] Cible : VPS IONOS Cloud S (upgrade vers 2GB+ RAM) — Berlin, 217.160.34.6

### v0.7.0 — Robustesse & DX
- [ ] Synchroniser ARCHITECTURE.md avec l'état réel (noms de variables, flow, phases)
- [ ] Mode `--dry-run` : simuler le flow sans lancer Claude (debug)
- [ ] Gérer le cas "toutes features cochées mais pas DONE.md" (boucle infinie strategy/evolve)
- [ ] Tests automatisés : script de test avec mock Claude
- [ ] shellcheck clean

### v0.8.0 — Intelligence des prompts
- [ ] Améliorer render_phase (`envsubst` ou template engine)
- [ ] Prompt dynamique : injecter l'état courant dans chaque prompt
- [ ] Context carry : résumé de la feature précédente dans le prompt de la suivante
- [ ] Phase quality gate optionnelle (lint, type-check) entre implement et test

### v0.9.0 — Infra avancée
- [ ] Intégration GitHub Actions (workflow_dispatch, state sur branches)
- [ ] Notifications (Telegram/Slack) quand feature terminée ou erreur
- [ ] Commande `agent upgrade <nom>` : mettre à jour un workspace avec le dernier template
- [ ] Versioning du workspace : tag quelle version du template a été utilisée

### Idées (non priorisé)
- [ ] Dashboard web pour visualiser tokens, roadmap, logs
- [ ] Support d'autres LLM CLI (pas que Claude)
- [ ] Mode "pair" : deux instances Claude qui review le code l'une de l'autre
- [ ] Mode "brief interactif distant" : Claude rédige le brief via SSH (déjà supporté par init.sh)
- [ ] Cron optionnel : relancer automatiquement l'orchestrateur après un arrêt/crash
