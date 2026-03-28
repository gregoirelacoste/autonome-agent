#!/bin/bash
# ============================================================
# Test d'intégration ORC — validation du pipeline sans exécution
# Usage : bash tests/validate-orchestrator.sh
# ============================================================

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ERRORS=0
WARNINGS=0
CHECKS=0

pass() { CHECKS=$((CHECKS + 1)); printf "  ✓ %s\n" "$1"; }
fail() { CHECKS=$((CHECKS + 1)); ERRORS=$((ERRORS + 1)); printf "  ✗ %s\n" "$1"; }
warn() { CHECKS=$((CHECKS + 1)); WARNINGS=$((WARNINGS + 1)); printf "  ⚠ %s\n" "$1"; }

echo "═══════════════════════════════════════"
echo "  ORC — Validation d'intégrité"
echo "═══════════════════════════════════════"
echo ""

# --- Syntaxe bash ---
echo "▸ Syntaxe bash"
for f in orchestrator.sh orc.sh orc-agent.sh orc-admin.sh config.default.sh; do
  if [ -f "$SCRIPT_DIR/$f" ]; then
    if bash -n "$SCRIPT_DIR/$f" 2>/dev/null; then
      pass "$f"
    else
      fail "$f — erreur de syntaxe"
    fi
  else
    warn "$f — fichier manquant"
  fi
done

# --- Fichiers de phase ---
echo ""
echo "▸ Phases"
for phase in 00-bootstrap 01-research 02-strategy 03-implement 03a-plan 03b-critic \
             04-test-fix 04b-acceptance 05-reflect 06-meta-retro 06b-tech-debt \
             07-evolve 08-user-docs; do
  if [ -f "$SCRIPT_DIR/phases/${phase}.md" ]; then
    pass "phases/${phase}.md"
  else
    fail "phases/${phase}.md — manquant"
  fi
done

# --- Placeholders dans les phases ---
echo ""
echo "▸ Placeholders"
for phase_file in "$SCRIPT_DIR/phases/"*.md; do
  local_name=$(basename "$phase_file")
  # Vérifier que tous les {{VAR}} sont dans la liste connue
  placeholders=$(grep -oP '\{\{\w+\}\}' "$phase_file" 2>/dev/null | sort -u || true)
  if [ -n "$placeholders" ]; then
    for ph in $placeholders; do
      var="${ph//\{/}"; var="${var//\}/}"
      case "$var" in
        FEATURE_NAME|FEATURE_BRANCH|N|FEATURE_COUNT|TESTS_PASSED|FIX_ATTEMPTS|\
        EPIC_NUMBER|TOTAL_FAILURES|DEV_COMMAND|\
        ATTEMPT|MAX_FIX|BUILD_EXIT|BUILD_OUTPUT|TEST_EXIT|TEST_OUTPUT)
          ;;
        *)
          warn "$local_name : placeholder inconnu {{$var}}"
          ;;
      esac
    done
  fi
  pass "$local_name — placeholders OK"
done

# --- Config default cohérence ---
echo ""
echo "▸ Config"
# Vérifier que les paramètres clés existent
for param in PROJECT_DIR MAX_FIX_ATTEMPTS MAX_FEATURES CLAUDE_MODEL CLAUDE_MODEL_LIGHT \
             MAX_BUDGET_USD CLAUDE_TIMEOUT STALL_KILL_THRESHOLD; do
  if grep -q "^${param}=" "$SCRIPT_DIR/config.default.sh" 2>/dev/null; then
    pass "$param défini"
  else
    fail "$param manquant dans config.default.sh"
  fi
done

# Vérifier PHASE_TIMEOUTS
if grep -q "declare -A PHASE_TIMEOUTS" "$SCRIPT_DIR/config.default.sh" 2>/dev/null; then
  pass "PHASE_TIMEOUTS déclaré"
else
  fail "PHASE_TIMEOUTS manquant"
fi

# --- Skills templates ---
echo ""
echo "▸ Skills"
for skill in fix-tests implement-feature research review-own-code stack-conventions; do
  if [ -f "$SCRIPT_DIR/skills-templates/${skill}.md" ]; then
    pass "skills-templates/${skill}.md"
  else
    warn "skills-templates/${skill}.md — manquant"
  fi
done

# --- Fonctions clés dans orchestrator.sh ---
echo ""
echo "▸ Fonctions"
for func in run_claude render_phase track_tokens save_state restore_state \
            migrate_config adaptive_max_turns smart_truncate error_hash \
            workflow_transition resolve_model get_model_pricing \
            mark_feature_done_bash update_changelog generate_repo_map; do
  if grep -q "^${func}()" "$SCRIPT_DIR/orchestrator.sh" 2>/dev/null; then
    pass "$func()"
  else
    fail "$func() — manquant dans orchestrator.sh"
  fi
done

# --- LIGHT_PHASES cohérence ---
echo ""
echo "▸ LIGHT_PHASES"
light_phases=$(grep '^LIGHT_PHASES=' "$SCRIPT_DIR/orchestrator.sh" | head -1 | sed 's/LIGHT_PHASES="//' | sed 's/"//')
for phase in plan acceptance reflection reflect self-improve meta-retro quality \
             strategy research-initial research-epic evolve user-docs; do
  if echo " $light_phases " | grep -q " $phase "; then
    pass "$phase dans LIGHT_PHASES"
  else
    warn "$phase absent de LIGHT_PHASES"
  fi
done

# Vérifier que critic et tech-debt ne sont PAS dans LIGHT_PHASES
for phase in critic tech-debt; do
  if echo " $light_phases " | grep -q " $phase "; then
    fail "$phase dans LIGHT_PHASES (devrait être sur modèle principal)"
  else
    pass "$phase sur modèle principal (correct)"
  fi
done

# --- Bilan ---
echo ""
echo "═══════════════════════════════════════"
printf "  Résultat : %s checks, " "$CHECKS"
if [ "$ERRORS" -gt 0 ]; then
  printf "✗ %s erreurs" "$ERRORS"
else
  printf "✓ 0 erreurs"
fi
if [ "$WARNINGS" -gt 0 ]; then
  printf ", ⚠ %s warnings" "$WARNINGS"
fi
echo ""
echo "═══════════════════════════════════════"

exit "$ERRORS"
