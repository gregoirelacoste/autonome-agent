# ORC — Auto-generated Repo Map
> Généré automatiquement — NE PAS modifier à la main.
> Dernière mise à jour : 2026-03-25 07:47:42

## Shell Scripts

### agent.sh
- die() { printf "${RED}Erreur : %s${NC}\n" "$1" >&2; exit 1; }
- project_dir() {
- require_project() {
- is_running() {
- cmd_new() {
- cmd_start() {
- cmd_stop() {
- cmd_restart() {
- cmd_status() {
- cmd_status_detail() {
- cmd_logs() {
- parse_frontmatter() {
- parse_tags() {
- parse_depends() {
- extract_section() {
- priority_color() {
- status_symbol() {
- sort_items() {
- effort_sort_key() {
- cmd_roadmap() {

### config.default.sh

### deploy.sh

### init.sh

### orc-admin.sh
- admin_config() {
- admin_model() {
- admin_budget() {
- admin_key() {
- admin_version() {
- admin_help() {
- admin_dispatch() {

### orc-agent.sh
- project_dir() {
- require_project() {
- is_running() {
- cmd_new() {
- cmd_start() {
- cmd_stop() {
- cmd_restart() {
- cmd_status() {
- cmd_status_detail() {
- cmd_logs() {
- cmd_update() {
- parse_frontmatter() {
- parse_tags() {
- parse_depends() {
- extract_section() {
- priority_color() {
- status_symbol() {
- sort_items() {
- effort_sort_key() {
- cmd_roadmap() {

### orc.sh
- die() { printf "${RED}Erreur : %s${NC}\n" "$1" >&2; exit 1; }
- orc_help() {

### orchestrator.sh
- cleanup() {
- log() {
- save_state() {
- restore_state() {
- init_tokens() {
- track_tokens() {
- print_cost_summary() {
- run_claude() {
- render_phase() {
- write_fix_prompt() {
- next_feature() {
- branch_name() {
- run_in_project() {
- notify() {
- check_signals() {
- read_human_notes() {
- error_hash() {
- run_quality_gate() {
- generate_repo_map() {
- human_pause() {

## Phases (phases/*.md)

- 00-bootstrap.md — placeholders: aucun
- 01-research.md — placeholders: aucun
- 02-strategy.md — placeholders: aucun
- 03-implement.md — placeholders: {{FEATURE_BRANCH}},{{FEATURE_NAME}},
- 04-test-fix.md — placeholders: {{ATTEMPT}},{{BUILD_EXIT}},{{BUILD_OUTPUT}},{{MAX_FIX}},{{TEST_EXIT}},{{TEST_OUTPUT}},
- 05-reflect.md — placeholders: {{FEATURE_NAME}},{{FIX_ATTEMPTS}},{{N}},{{TESTS_PASSED}},
- 06-meta-retro.md — placeholders: {{FEATURE_COUNT}},
- 07-evolve.md — placeholders: aucun

## Skills Templates (skills-templates/*.md)

- fix-tests.md
- implement-feature.md
- research.md
- review-own-code.md
- roadmap-item.md
- stack-conventions.md
- write-brief.md
