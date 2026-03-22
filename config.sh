#!/bin/bash
# ============================================================
# Configuration de l'agent autonome
# Modifier ces valeurs selon votre projet
# ============================================================

# === PROJET ===
PROJECT_DIR="./project"                  # Dossier du projet généré
PROJECT_NAME=""                          # Nom du projet (auto-détecté depuis BRIEF.md si vide)

# === GARDE-FOUS ===
MAX_FIX_ATTEMPTS=5                       # Tentatives de correction par feature
MAX_FEATURES=50                          # Nombre total de features avant arrêt
MAX_TURNS_PER_INVOCATION=50              # Limite de turns par appel Claude

# === RYTHME ===
EPIC_SIZE=3                              # Nombre de features par epic avant veille ciblée
META_RETRO_FREQUENCY=5                   # Méta-rétrospective toutes les N features

# === INTERVENTION HUMAINE ===
PAUSE_EVERY_N_FEATURES=0                 # Pause humaine toutes les N features (0 = jamais)
REQUIRE_HUMAN_APPROVAL=false             # true = attend validation avant chaque merge
AUTO_EVOLVE_ROADMAP=true                 # Claude peut ajouter des features à la roadmap

# === RECHERCHE ===
ENABLE_RESEARCH=true                     # Activer la veille marché
MAX_TURNS_RESEARCH_INITIAL=80            # Budget recherche initiale
MAX_TURNS_RESEARCH_EPIC=40               # Budget veille ciblée par epic
MAX_TURNS_RESEARCH_TREND=50              # Budget veille tendances (méta-rétro)

# === TECHNIQUE ===
BUILD_COMMAND="npm run build"            # Commande de build
TEST_COMMAND="npx playwright test"       # Commande de test
DEV_COMMAND="npm run dev"                # Commande serveur dev
LINT_COMMAND="npm run lint"              # Commande lint (vide = désactivé)

# === LOGS ===
LOG_DIR="./logs"                         # Dossier des logs orchestrateur
VERBOSE=true                             # Logs détaillés dans la console
