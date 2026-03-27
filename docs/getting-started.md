# Démarrage rapide

## Prérequis

| Outil | Requis | Installation |
|---|---|---|
| Claude Code CLI | Oui | [docs.anthropic.com](https://docs.anthropic.com/en/docs/claude-code) |
| Clé API Anthropic | Oui | `orc admin key set sk-ant-...` |
| Git | Oui | `apt install git` / `brew install git` |
| Node.js 22+ | Oui | `nvm install 22` |
| GitHub CLI (`gh`) | Non | `apt install gh` / `brew install gh` |
| `jq` | Non | Pour le tracking des coûts |

## Installation

```bash
# Cloner le template
git clone git@github.com:gregoirelacoste/orc.git
cd orc

# Rendre orc disponible partout
sudo ln -sf "$(pwd)/orc.sh" /usr/local/bin/orc

# Configurer la clé API
orc admin key set sk-ant-votre-cle
```

### Installation VPS (Ubuntu 22+ / Debian 12+)

```bash
ssh root@<vps-ip> 'bash -s' < deploy.sh
```

Le script installe Node.js, Claude CLI et orc en une commande.

## Premier projet en 3 minutes

### Option A — Wizard interactif (recommandé pour débuter)

```bash
orc agent new mon-projet
```

Claude te pose ~22 questions pour comprendre ton produit et rédige un `BRIEF.md` complet.

### Option B — Brief existant (recommandé si tu sais ce que tu veux)

```bash
orc agent new mon-projet --brief briefs/mon-brief.md
```

Claude lit ton brief, identifie les zones floues, te pose des questions ciblées pour l'enrichir, puis génère le `BRIEF.md` final.

> Astuce : regarde `briefs/pc-builder.md` pour un exemple de brief complet.

### Option C — Brief sans clarification

```bash
orc agent new mon-projet --brief briefs/mon-brief.md --no-clarify
```

Copie le brief tel quel, sans questions. Utile si ton brief est déjà exhaustif.

### Option D — Template vide

```bash
orc agent new mon-projet --skip-brief
```

Copie le template `BRIEF.template.md`. Tu le remplis manuellement avant de lancer.

## Configurer (optionnel)

```bash
vim ~/projects/mon-projet/.orc/config.sh
```

Les paramètres essentiels :

| Paramètre | Défaut | Description |
|---|---|---|
| `MAX_FEATURES` | 50 | Nombre de features avant arrêt |
| `REQUIRE_HUMAN_APPROVAL` | false | Valider chaque merge |
| `PAUSE_EVERY_N_FEATURES` | 0 | Pause toutes les N features |
| `BUILD_COMMAND` | `npm run build` | Commande de build |
| `TEST_COMMAND` | `npx playwright test` | Commande de test |

Voir [configuration.md](configuration.md) pour la liste complète.

## Lancer

```bash
orc agent start mon-projet
```

L'orchestrateur tourne en background. Le code est généré dans `~/projects/mon-projet/project/`.

## Suivre

```bash
orc s                     # Vue d'ensemble de tous les projets
orc s mon-projet          # Détail : features, coût, progression
orc l mon-projet          # Logs en temps réel
orc r                     # Roadmap d'orc
```

## Intervenir en cours de route

```bash
# Injecter des notes pour la prochaine feature
vim ~/projects/mon-projet/.orc/human-notes.md

# Pause après la feature en cours
touch ~/projects/mon-projet/.orc/pause-requested

# Arrêt propre
touch ~/projects/mon-projet/.orc/stop-after-feature

# Arrêt immédiat
orc agent stop mon-projet
```

Voir [human-controls.md](human-controls.md) pour le détail des interventions.

## Prochaines étapes

- [Modes d'initialisation](init-modes.md) — comprendre les différentes façons de créer un projet
- [Référence des commandes](commands-reference.md) — toutes les commandes disponibles
- [Configuration](configuration.md) — personnaliser le comportement
- [Intégration GitHub](github-integration.md) — activer PRs, tracking, CI
