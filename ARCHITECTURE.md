# Agent Autonome Claude — Architecture complète

> Un agent Claude Code 100% autonome qui construit un produit de A à Z :
> veille marché, roadmap, développement, tests, corrections,
> auto-amélioration — avec intervention humaine configurable.

---

## Le principe en une phrase

On donne un brief à Claude. Il fait sa veille, établit une roadmap,
développe feature par feature (dev → test → debug → correction),
et toutes les N features il prend du recul (veille → repriorisation → validation)
avant de repartir — le tout en boucle autonome.

---

## Schéma global

```
./orchestrator.sh --brief     (optionnel, mode interactif)
    │
    ▼
BRIEF.md (immuable)
    │
    ▼
BOOTSTRAP ──▶ RECHERCHE INITIALE ──▶ STRATÉGIE & ROADMAP
                                           │
                    ┌──────────────────────┘
                    │
                    ▼
            ┌───────────────────────────────────────────┐
            │            BOUCLE FEATURE (×N)            │
            │                                           │
            │   Veille ciblée (avant chaque epic)       │
            │       │                                   │
            │       ▼                                   │
            │   Challenger ──▶ Plan ──▶ Implement ──▶ Lint ──▶ Critic ──▶ Test ──▶ Fix (loop) ─┐ │
            │                                      │   │
            │       ┌──────────────────────────────┘   │
            │       ▼                                   │
            │   Product Review (autocritique métier)    │
            │       │                                   │
            │       ▼                                   │
            │   Reflect                                 │
            │       │                                   │
            │       ├── (fin d'epic) → Acceptance       │
            │       ├── (>30% échecs) → Tech-Debt       │
            │       ▼                                   │
            │   Evolve (score maturité /30)             │
            │   - met à jour CLAUDE.md                  │
            │   - crée/améliore des skills              │
            │   - coche la feature, note les leçons     │
            │                                           │
            └───────────────┬───────────────────────────┘
                            │
                  toutes les N features
                            │
                            ▼
            ┌───────────────────────────────────────────┐
            │         MÉTA-RÉTROSPECTIVE                │
            │                                           │
            │   1. Vision globale du projet             │
            │   2. Veille tendances & concurrents       │
            │   3. Repriorisation de la roadmap         │
            │   4. Validation vs objectif & brief       │
            │   5. Nettoyage (CLAUDE.md, skills, docs)  │
            │                                           │
            └───────────────┬───────────────────────────┘
                            │
                            ▼
                  Nouvelle itération de N features
                            │
                            ...
                            │
                            ▼
                    Score maturité /30 ?
                    ├── >= 24 → DONE.md → deploy (si DEPLOY_COMMAND) → fin
                    ├── >= 18 → 3 features ciblées → boucle
                    └── < 18  → corrections prioritaires → boucle
```

---

## Phase -1 — RÉDACTION DU BRIEF (optionnel)

**Quand :** `./orchestrator.sh --brief` ou `./orchestrator.sh --brief "mon idée"`

**Ce que Claude fait :**

Claude agit en **directeur produit senior**. En mode interactif (pas autonome),
il pose ~22 questions structurées à l'utilisateur pour couvrir :
- Vision, problème, anti-scope
- Persona, parcours utilisateur, device
- Concurrents (vérifiés par WebSearch), différenciateurs, modèle économique
- Features MVP avec critères d'acceptance et cas limites
- Stack technique, APIs, données
- Design, UX, langue, accessibilité
- Contraintes (budget, légal, performance)
- Critères de succès mesurables

Puis rédige un `BRIEF.md` exhaustif et sans ambiguïté.

**Pourquoi c'est critique :** le BRIEF est la seule ancre immuable du système.
Chaque ambiguïté dans le brief = une décision arbitraire de l'IA plus tard.

**Skill :** `skills-templates/write-brief.md`

---

## Phase 0 — BOOTSTRAP

**Quand :** Une seule fois, au lancement.

**Ce que Claude fait :**
1. Lit `BRIEF.md` pour comprendre la vision produit
2. Initialise la structure technique (dossiers, config, dépendances)
3. Crée ses propres skills dans `.claude/skills/`
4. Rédige le `CLAUDE.md` du projet avec les règles initiales
5. Commit initial

---

## Phase 1 — RECHERCHE INITIALE

**Quand :** Après le bootstrap, avant tout code.

**Ce que Claude fait :**
1. **Benchmark concurrentiel** — WebSearch + WebFetch des concurrents directs
2. **Attentes utilisateurs** — forums, Reddit, ProductHunt, avis
3. **Tendances tech & UX** — APIs disponibles, patterns actuels
4. **Veille réglementaire** — contraintes légales applicables

**Stockage :**
```
research/
├── INDEX.md                    # Synthèse courante (max 50 lignes)
├── competitors/
│   ├── YYYY-MM-DD-<nom>.md     # Fiche par concurrent
│   └── SYNTHESIS.md            # Tableau comparatif
├── trends/
│   └── SYNTHESIS.md
├── user-needs/
│   └── SYNTHESIS.md
└── regulations/
    └── SYNTHESIS.md
```

**Règles :**
- Toujours dater les fichiers de recherche
- Toujours citer l'URL source
- Chaque insight se termine par "Impact produit : ..."

---

## Phase 2 — STRATÉGIE

**Quand :** Après la recherche initiale, puis à chaque méta-rétro.

**Ce que Claude fait :**
1. **Score le brief** sur 5 critères (clarté, scope, stack, succès, users) — note /25. Si < 15/25, ajoute des hypothèses pour combler les manques
2. Croise `BRIEF.md` (vision immuable) avec `research/INDEX.md` (données marché)
3. Crée des **tickets kanban** dans `.orc/roadmap/todo/` : **MVP** (P0/P1, 5-8 features) + **Améliorations** (P2/P3, optionnel, max 15 features totales)
4. Chaque ticket référence un insight de la recherche
5. Ordonne par priorité × faisabilité
6. Quick wins (P0) en premier, MVP fonctionnel seul

**Format ticket kanban** (un fichier `.orc/roadmap/todo/NNN-slug.md` par feature) :
```yaml
---
id: 1
title: "Titre orienté action"
priority: P1
type: feature
effort: M
tags: [domaine, technique]
epic: mvp
created: 2026-03-29
source: strategy
---

## Contexte
Pourquoi cette feature. Cite le brief et la recherche.

## Spécification
Ce qui doit être implémenté concrètement.

## Critères de validation
- [ ] Critère testable
```

**Structure kanban projet :**
```
.orc/roadmap/
├── backlog/        # Idées non priorisées
├── todo/           # Prêt à implémenter, trié par priorité P0→P3
├── in-progress/    # En cours (max 1, géré par l'orchestrateur)
└── done/           # Terminé
```

`ROADMAP.md` est **auto-généré** depuis le kanban (vue compatible dashboard/status).
Migration automatique des projets existants au premier démarrage.

---

## Phase 3 — BOUCLE FEATURE (coeur du système)

Pour chaque feature de la roadmap :

### 3a. Veille ciblée (avant chaque epic)

Recherche focalisée sur le domaine de l'epic :
- Comment les concurrents gèrent cette fonctionnalité
- Best practices UX spécifiques
- APIs / données publiques exploitables

Met à jour `research/` et ajuste les specs dans `ROADMAP.md`.

### 3b. Challenger (enrichissement pré-implémentation)

`phases/03c-challenger.md` — 3 turns max, modèle **fort** (`CLAUDE_MODEL_STRONG`, défaut Opus).

Claude joue le rôle de **product thinker senior** pour enrichir la feature AVANT qu'elle soit planifiée. Analyse sous 6 angles : complétude, edge cases, UX, cohérence, sécurité, performance.

**Contexte complet pré-injecté** (INDEX.md, auto-map.md, BRIEF, ROADMAP, research) → zéro lecture fichier, ~3100 tokens/feature.

Output : `.orc/logs/challenger-N.md` avec :
- **Enrichissements immédiats** (3-7 actions concrètes) → injectés dans plan + implement
- **Idées futures** (0-3 ideas) → backlog pour plus tard

**Lookahead parallèle** : le challenger de feature N+1 tourne en arrière-plan (subshell isolée) pendant les phases lint/critic/test/reflect de feature N. Quand on arrive à N+1, le challenger est déjà prêt → 0 temps d'attente ajouté.

Config : `ENABLE_CHALLENGER=true`, `CLAUDE_MODEL_STRONG`, `MAX_TURNS_CHALLENGER=3`.

### 3c. Micro-phase Plan

5 turns max, modèle léger (`CLAUDE_MODEL_LIGHT`). Produit `.orc/logs/plan-N.md` :
- Fichiers à modifier, interfaces, tests, risques
- Si un challenger a été exécuté, ses enrichissements sont injectés dans le prompt du plan
- Le plan est injecté dans le prompt d'implémentation
- Détecte les erreurs de conception AVANT de coder, réduit les cycles de fix

### 3d. Implémentation

1. Crée une branche `feature/<nom>`
2. Lit le plan + le code existant (via INDEX.md + auto-map.md injectés)
3. Implémente la feature
4. Écrit les tests
5. Build
6. Commit atomique

### 3e. Lint

Si `LINT_COMMAND` est défini, exécuté entre implement et la review adversariale.
En cas d'échec, correction automatique par Claude (10 turns max) avant de continuer.

### 3f. Review adversariale (Critic) — Multi-agent

`phases/03b-critic.md` — 10 turns max, modèle **principal** (pas léger).
Utilise `--append-system-prompt` avec un persona adversarial ("reviewer senior sceptique")
distinct du coder pour éliminer le biais de confirmation.
- Review le diff vs main
- Corrige max 3 bugs AVANT le cycle de test coûteux
- Persona séparé = multi-agent (le critic ne partage pas le contexte du coder)

### 3g. Product Review (autocritique métier)

`phases/04d-product-review.md` — 5 turns max, modèle **fort** (`CLAUDE_MODEL_STRONG`, défaut Opus).

Exécutée APRÈS les tests, AVANT reflect. Miroir du challenger : vérifie que l'implémentation **livre réellement de la valeur à l'utilisateur**.

Évalue sous 6 angles :
- **Adéquation** au brief — décalage entre spec et exécution ?
- **Complétude** utilisateur — parcours de bout en bout ?
- **Expérience** ressentie — l'utilisateur serait-il satisfait ?
- **Valeur** livrée — "techniquement correct" vs "vraiment utile" ?
- **Quick wins** — polish cosmétique à faible effort (max 3)
- **Cohérence** produit — intégration avec les features précédentes

Le challenger output est injecté pour comparer ce qui était **attendu** vs ce qui a été **réalisé**.

Output : `.orc/logs/product-review-N.md`. Config : `ENABLE_PRODUCT_REVIEW=true`, `MAX_TURNS_PRODUCT_REVIEW=5`.

### 3h. Test & Fix Loop

```
attempt = 0
while (build échoue OU tests échouent) AND attempt < MAX_FIX:
    Claude analyse l'erreur (error_hash pour détecter les boucles)
    Claude écrit une réflexion structurée (fix-reflections-N.md)
    known-issues.md injecté (mémoire inter-features)
    Claude corrige le code
    Relance build + tests
    attempt++

    Même erreur 2x → prompt "change d'approche"
    Même erreur 3x → abandon anticipé

Si attempt == MAX_FIX:
    Feature marquée en échec, on passe à la suite
```

### 3i. Acceptance (fin d'epic)

`phases/04b-acceptance.md` — exécutée après chaque epic (toutes les `EPIC_SIZE` features).
Valide les user stories du BRIEF de bout en bout :
1. Lit le BRIEF et les features cochées de l'epic
2. Lance l'app (`DEV_COMMAND`) et teste les scénarios utilisateur
3. Écrit un rapport `acceptance-N.md` avec score X/Y scénarios passés
4. Corrige max 5 problèmes critiques directement (pas de nouvelles features)
5. Les problèmes non critiques vont en backlog

### 3j. Reflect & Evolve (auto-amélioration)

Après chaque feature, Claude enrichit sa connaissance du projet :

1. **codebase/** — met à jour les fichiers de détail pertinents (modules.md, utilities.md, etc.) puis l'INDEX.md. L'index reste compact (max 40 lignes) — c'est la carte sémantique du projet consultée avant chaque feature.
2. **stack-conventions.md** — enrichit les conventions spécifiques à la stack : nouveaux patterns, anti-patterns, optimisations, patterns de sécurité validés.
3. **CLAUDE.md** — ajoute des règles si piège découvert, supprime les obsolètes
4. **Skills** — crée un nouveau skill si pattern répété manuellement,
   met à jour un skill existant s'il était inadapté
5. **ROADMAP.md** — coche la feature, ajoute des dépendances découvertes
6. **Logs** — écrit `logs/retrospective-N.md` avec mesure de réutilisation vs création

> L'IA ne s'améliore pas seulement sur le process : elle construit une
> expertise du projet. À la feature 20, elle connaît chaque module, chaque
> convention, chaque utility — et ne duplique plus rien.

---

## Phase 4 — MÉTA-RÉTROSPECTIVE (toutes les N features)

**Quand :** Toutes les 5-10 features (configurable).

**Ce que Claude fait :**

1. **Vision globale** — le projet est-il sur la bonne trajectoire ?
2. **Veille tendances** — WebSearch : quoi de neuf sur le marché ?
3. **Positionnement** — où en est-on vs les concurrents ?
4. **Repriorisation** — ajuste la ROADMAP si nécessaire
5. **Validation** — la roadmap est-elle toujours cohérente avec le BRIEF ?
6. **Nettoyage** — CLAUDE.md devenu trop long ? Skills inutiles ? INDEX.md à élaguer ?

Écrit `logs/meta-retrospective-N.md` avec le bilan.

---

## Phase 5 — ÉVOLUTION (quand la roadmap est vide)

Claude évalue le projet avec un **score de maturité /30** sur 6 critères :
parcours utilisateur complet, CRUD fonctionnel, gestion d'erreurs, UX cohérente,
couverture de tests, documentation.

1. **Score >= 24/30** → projet terminé → crée `DONE.md` → déploiement auto si `DEPLOY_COMMAND` configuré
2. **Score >= 18/30** → crée 3 tickets ciblés dans `.orc/roadmap/todo/` → relance la boucle
3. **Score < 18/30** → corrections prioritaires dans `.orc/roadmap/todo/`

Le cycle evolve utilise une boucle `while` interne (pas `exec "$0"`) pour
relancer la boucle feature sans redémarrer le process. Le compteur `evolve_cycle`
est incrémenté et limité par `MAX_EVOLVE_CYCLES`.

### Continuation post-DONE

Un projet "terminé" (DONE.md) peut reprendre si de nouveaux tickets sont ajoutés
via `orc roadmap ticket` ou `orc roadmap brainstorm`. Le mécanisme :
1. L'humain crée des tickets → DONE.md est archivé dans `.orc/logs/`
2. `workflow_phase` est reset à `features`
3. `orc agent start` reprend la boucle avec les nouveaux tickets

---

## Auto-amélioration — ce que Claude modifie sur lui-même

| Fichier | Rôle | Modifié quand |
|---|---|---|
| `codebase/INDEX.md` | Carte sémantique du projet | Après chaque feature (Reflect) |
| `codebase/*.md` | Détail par domaine | Après chaque feature (Reflect) |
| `stack-conventions.md` | Conventions de stack | Après chaque feature (Reflect) |
| `CLAUDE.md` | Ses instructions | Après chaque feature (Reflect) |
| `.claude/skills/*.md` | Ses workflows | Quand un pattern se répète |
| `.orc/roadmap/` | Kanban tickets (source) | Strategy, evolve, ticket, brainstorm |
| `ROADMAP.md` | Vue auto-générée (compat) | Régénéré après chaque changement |

Le cycle vertueux (process + projet + économie de contexte) :
```
Feature 1 : erreurs basiques → Reflect ajoute 3 règles au CLAUDE.md
Feature 2 : crée formatDate() → Reflect l'ajoute à codebase/utilities.md + index
Feature 3 : même type d'erreur E2E → crée un skill fix-e2e.md
Feature 4 : besoin de formater une date → lit INDEX.md → lit utilities.md → réutilise !
Feature 5 : méta-rétro → nettoyage index + stack-conventions enrichi
Feature 8 : pattern sécurité répété → ajouté à codebase/security.md
Feature 10 : dette technique détectée → refactoring ajouté à la roadmap
Feature 15 : l'IA connaît chaque module via l'index → zéro duplication
Feature 20 : index compact + détail à la demande → contexte minimal, expertise maximale
```

---

## Configuration — Intervention humaine

Tout est configurable dans `.orc/config.sh` (migration auto des nouveaux paramètres via `migrate_config()`) :

```bash
# === GARDE-FOUS ===
MAX_FIX_ATTEMPTS=3              # Tentatives de correction par feature
MAX_FEATURES=50                 # Nombre total de features avant arrêt
MAX_TURNS_PER_INVOCATION=50     # Limite de turns par appel Claude

# === BUDGET ===
MAX_BUDGET_USD="200.00"         # Budget max en USD (prédictif + post-hoc)
                                # Prédictif : refuse de lancer si budget insuffisant
                                # Post-hoc : vérifie après chaque invocation

# === MODÈLES (adaptatifs) ===
CLAUDE_MODEL=""                 # Modèle principal (implement, fix, critic). Vide = défaut CLI
CLAUDE_MODEL_LIGHT="claude-haiku-4-5"  # Modèle léger (plan, reflect, research)
CLAUDE_MODEL_STRONG="claude-opus-4-6"  # Modèle fort (challenger)
                                # resolve_model() : STRONG > CLAUDE_MODEL > LIGHT
                                # MODEL_PRICING[] contient les tarifs par préfixe de modèle

# === RYTHME ===
META_RETRO_FREQUENCY=5          # Méta-rétrospective toutes les N features
EPIC_SIZE=3                     # Nombre de features par epic

# === INTERVENTION HUMAINE ===
PAUSE_EVERY_N_FEATURES=0        # Pause humaine toutes les N features (0 = jamais)
REQUIRE_HUMAN_APPROVAL=false    # true = attend validation avant merge
AUTO_EVOLVE_ROADMAP=true        # Claude peut ajouter des features seul
MAX_EVOLVE_CYCLES=2             # Nombre max de cycles evolve (0 = illimité)
MAX_AI_ROADMAP_ADDS=5           # Max features ajoutées par l'IA avant pause

# === NOTIFICATIONS ===
NOTIFY_COMMAND=""               # Commande de notification (ex: notify-send, slack webhook)

# === RECHERCHE ===
MAX_TURNS_RESEARCH_INITIAL=50   # Budget recherche initiale
MAX_TURNS_RESEARCH_EPIC=20      # Budget veille ciblée par epic
MAX_TURNS_RESEARCH_TREND=30     # Budget veille tendances

# === TECHNIQUE ===
LINT_COMMAND="npm run lint"     # Lint entre implement et critic (vide = désactivé)
QUALITY_COMMAND=""              # Quality gate post-tests (ex: lighthouse, bundle-size)
DEPLOY_COMMAND=""               # Déploiement auto en fin de projet (ex: scripts/deploy.sh, vercel deploy --prod)
FUNCTIONAL_CHECK_COMMAND=""     # Vérification fonctionnelle post-merge

# === TIMEOUTS ===
CLAUDE_TIMEOUT=900              # Timeout global par invocation (secondes)
STALL_KILL_THRESHOLD=60         # Checks sans données avant kill auto (×5s = 5min)
declare -A PHASE_TIMEOUTS=(     # Timeouts par phase (surcharge CLAUDE_TIMEOUT)
    [plan]=120 [implement]=900 [fix]=600 [critic]=300
    [reflect]=180 [research]=600 [strategy]=600 [meta-retro]=600
)
```

**Modes d'utilisation :**

| Mode | Config | Comportement |
|---|---|---|
| **Pilote auto** | `PAUSE_EVERY_N_FEATURES=0` | Totalement autonome |
| **Copilote** | `REQUIRE_HUMAN_APPROVAL=true` | Claude code, humain valide les merges |
| **Supervisé** | `PAUSE_EVERY_N_FEATURES=3` | Pause fréquente pour check humain |
| **Recherche seule** | Lancer uniquement phases 1-2 | Veille + roadmap sans code |

---

## Mécaniques de contrôle humain

### Human Notes (instructions mid-run)

L'humain peut écrire dans `.orc/human-notes.md` à tout moment. Le contenu est
injecté dans le prompt d'implémentation de la prochaine feature. Permet de
rediriger l'IA sans arrêter l'agent.

Accessible aussi via l'option `n` dans `human_pause()`.

### Feedback structuré

À chaque checkpoint (`human_pause`), l'humain peut laisser un feedback (`f`)
sur la dernière feature. Stocké dans `logs/human-feedback-N.md`, lu par :
- La phase reflect (prioritaire sur les observations de l'IA)
- La méta-rétrospective (influence les décisions de repriorisation)
- Le prompt d'implémentation de la feature suivante

### Diff & Summary à l'approbation

Options `d` (diff) et `s` (summary) dans `human_pause()` pour voir le code
changé et le résumé de la rétrospective avant d'approuver un merge.

### Signaux file-based (mode nohup)

Quand l'agent tourne en background, l'humain peut déposer des fichiers dans `.orc/` :
- `.orc/pause-requested` → pause au prochain checkpoint (attend `.orc/continue` pour reprendre)
- `.orc/stop-after-feature` → arrêt propre après la feature en cours
- `.orc/skip-feature` → saute la feature en cours, passe à la suivante

### Notifications

`NOTIFY_COMMAND` dans config.sh : commande shell appelée sur les événements critiques :
- Feature mergée, feature abandonnée, quality gate échouée
- Budget proche de la limite, pause humaine, projet terminé
- L'IA a ajouté trop de features à la roadmap

### Garde-fous sur l'évolution

- `MAX_EVOLVE_CYCLES=2` — limite les cycles d'auto-extension de la roadmap
- `MAX_AI_ROADMAP_ADDS=5` — force une pause humaine si l'IA ajoute trop de features
- Chaque feature ajoutée par l'IA doit citer la section du BRIEF qu'elle sert

---

## Mécaniques d'autonomie de l'IA

### Détection de boucle de fix

Le test-fix loop compare le hash des erreurs entre tentatives :
- Même erreur 2x → prompt "change d'approche radicalement"
- Même erreur 3x → abandon anticipé (évite le gaspillage de tokens)

### Quality Gate

`QUALITY_COMMAND` optionnel, exécuté après les tests et avant le merge.
Si échec → l'IA tente une correction. Si toujours en échec → merge quand même
(non-bloquant) avec notification. Exemples : lighthouse, bundle-size, coverage.

### Cross-validation de la recherche

Chaque insight de la phase research doit indiquer :
- `confidence: high | medium | low`
- Nombre de sources indépendantes qui le confirment
- Les insights `low confidence` ne peuvent pas servir seuls à prioriser des features

### Mémoire inter-projets (learnings/)

Le dossier `learnings/` dans le template accumule les apprentissages :
- À la fin du projet, `orchestrator-improvements.md` est copié dans `learnings/`
- Au bootstrap d'un nouveau projet, l'IA lit les learnings existants
- Les règles et pièges pertinents sont intégrés dans le CLAUDE.md initial

### Connaissance projet vivante (CODEBASE.md + stack-conventions.md)

**codebase/ — index sémantique + fichiers de détail + auto-map** (système DB-like)

```
codebase/
├── INDEX.md          ← carte sémantique (max 40 lignes), lu TOUJOURS
├── auto-map.md       ← carte auto-générée par l'orchestrateur (vérité du code)
├── modules.md        ← fonctions, classes, composants par dossier
├── utilities.md      ← helpers réutilisables avec signature et chemin
├── integrations.md   ← APIs, services tiers, config, erreurs
├── data-models.md    ← schémas DB, types TS, interfaces
├── architecture.md   ← décisions prises, justification, alternatives rejetées
└── security.md       ← patterns de sécurité validés, vérifications faites
```

**Deux sources de vérité complémentaires :**
- `auto-map.md` : **vérité du code** — généré par grep avant chaque feature. Multi-stack
  (TS/JS, Python, Java, Go, Astro). L'IA ne le modifie jamais.
- `INDEX.md` : **vérité sémantique** — maintenu par l'IA, enrichi d'annotations,
  justifications, liens entre modules. Max 40 lignes.

**Principe** : l'IA lit l'auto-map (ce qui existe) + l'index (pourquoi ça existe),
puis pioche le fichier de détail pertinent. Elle ne charge jamais tout.

**Gain estimé** : à la feature 30, un fichier monolithique ferait ~500 lignes
(~2000 tokens). Avec le système indexé, l'IA charge ~40 lignes d'index + ~100
lignes d'auto-map tronqué + ~50 lignes de détail = ~760 tokens au lieu de ~2000.

**stack-conventions.md** — skill auto-enrichie, spécifique à la stack du projet :
- Conventions de code adoptées (nommage, structure, patterns)
- Anti-patterns identifiés (erreurs à ne pas reproduire)
- Utilities créées et réutilisables
- Patterns de sécurité validés
- Optimisations de performance appliquées

Le cycle : implement consulte l'index + auto-map → lit le détail pertinent →
reflect enrichit le détail + vérifie vs auto-map → implement suivant consulte → ...

### Réflexions structurées (pattern Reflexion)

Inspiré du papier Reflexion (2023). Après chaque échec dans le test-fix loop,
l'IA écrit une réflexion structurée dans `logs/fix-reflections-N.md` :
- **Ce que j'ai tenté** — l'approche choisie
- **Pourquoi ça a échoué** — cause racine identifiée
- **Ce que je dois essayer** — nouvelle approche concrète

Ces réflexions sont injectées dans les tentatives de fix suivantes. L'IA ne
refait pas les mêmes erreurs parce qu'elle a **le raisonnement** de ses échecs
passés, pas juste le hash de l'erreur.

### Contexte adaptatif par phase

Inspiré de GITM et ACE. Chaque phase reçoit un **contexte différent** au lieu
du même blob global. `run_claude()` injecte un "context hint" selon la phase :

| Phase | Contexte injecté |
|---|---|
| **plan** | INDEX.md + auto-map.md (injectés directement) |
| **implement** | INDEX.md + auto-map.md (injectés) + fichiers de détail pertinents + stack-conventions.md |
| **fix** | auto-map.md (injecté) + security.md + réflexions passées + known-issues.md |
| **strategy** | INDEX.md (injecté) + architecture.md + research/INDEX.md |
| **reflect** | auto-map.md (injecté) + INDEX.md + fichiers de détail à mettre à jour |
| **meta-retro** | INDEX.md + auto-map.md (injectés) + audit complet de cohérence |

L'IA charge ~200 tokens de contexte pertinent au lieu de ~2000 tokens de tout.

### State machine (workflow_phase)

`WORKFLOW_PHASE` dans `state.json` pilote le workflow global. Transitions validées
par `workflow_transition()` :

```
init → bootstrap → research → strategy → features ⇄ evolve → post-project → done
                                                   ↘ crashed / stopped / budget_exceeded
```

Les guards fichier existants (CLAUDE.md, ROADMAP.md, etc.) restent comme filet de
sécurité. La reprise après crash utilise `WORKFLOW_PHASE` pour savoir exactement où
reprendre, sans re-scanner tous les fichiers.

### Multi-agent (critic)

Le système utilise deux "agents" distincts au sein du même orchestrateur :
- **Coder** — Claude avec le system prompt standard du projet (CLAUDE.md + skills)
- **Critic** — Claude avec `--append-system-prompt` injectant un persona adversarial
  ("reviewer senior sceptique"). Le critic ne partage pas le contexte du coder.

Ce découplage élimine le biais de confirmation : le critic review le diff sans
avoir participé à l'implémentation. Modèle principal (pas léger) pour la qualité.

### Budget prédictif + post-hoc

Deux mécanismes complémentaires pour `MAX_BUDGET_USD` (défaut 200$) :
- **Prédictif** — avant chaque invocation, `run_claude()` estime le coût probable
  (~4000 tokens input + ~2000 output) et refuse de lancer si le budget serait dépassé.
- **Post-hoc** — après chaque invocation, le coût réel est ajouté au total et vérifié.

### Pricing dynamique

`MODEL_PRICING` (associative array) contient les tarifs par préfixe de modèle.
`get_model_pricing()` résout le coût input/output pour le modèle effectif.
Préfixes triés par longueur décroissante pour match le plus spécifique.
Fallback sur tarif Sonnet + warning si modèle inconnu.

### Apprentissage adaptatif des turns

`adaptive_max_turns()` calcule le `max_turns` optimal par phase :
1. Lit l'historique des turns réels dans `tokens.json` (`by_phase.X.turns_history[]`)
2. Exclut les invocations tronquées par max_turns (feedback loop)
3. Calcule p75 + 30% marge
4. Requiert 5+ échantillons valides, ne dépasse jamais le défaut

Résultat : après quelques features, une phase qui utilise ~12 turns ne réserve
plus 50 turns, ce qui réduit les stalls et améliore le budget prédictif.

### Migration config auto

`migrate_config()` exécutée au démarrage de chaque run. Compare `.orc/config.sh`
avec `config.default.sh` et ajoute les paramètres manquants (avec commentaire
"# Added by migrate_config"). Traitement spécial pour `PHASE_TIMEOUTS`
(`declare -A`). Permet de mettre à jour orc sans recréer les projets.

### Mémoire inter-features (known-issues.md)

`.orc/known-issues.md` est alimenté automatiquement quand un fix réussit après
des échecs. Contient la réflexion qui a mené au fix (cause racine + solution).
Injecté dans le prompt de fix des features suivantes pour ne pas répéter les
mêmes erreurs. Complémentaire aux réflexions structurées (qui sont par-feature).

### Troncation intelligente (smart_truncate)

`smart_truncate(text, max_chars)` garde le début (~1/6) et la fin (~5/6) des logs.
Utilisé pour les outputs build/test qui peuvent être très longs. Préserve le
message d'erreur initial (souvent en haut) et le résumé final (en bas).

### Métriques enrichies

`tokens.json` contient désormais par invocation : modèle utilisé, turns réels,
phase, feature. Permet l'analyse post-run des coûts par modèle et l'apprentissage
adaptatif des turns.

---

## Structure complète des fichiers

```
~/projects/mon-projet/          # Repo git unique (structure aplatie)
├── BRIEF.md                    # Vision produit (IMMUABLE — jamais modifié par Claude)
├── CLAUDE.md                   # Instructions (auto-évolutif)
├── .orc/ROADMAP.md             # Backlog en epics (auto-évolutif)
├── DONE.md                     # Créé quand le projet est terminé
│
├── codebase/                    # Mémoire structurée du projet (index sémantique)
│   ├── INDEX.md                 # Carte sémantique (max 40 lignes, lu TOUJOURS)
│   ├── modules.md               # Fonctions, classes, composants
│   ├── utilities.md             # Helpers réutilisables
│   ├── integrations.md          # APIs, services tiers
│   ├── data-models.md           # Schémas, types, interfaces
│   ├── architecture.md          # Décisions techniques + justification
│   └── security.md              # Patterns de sécurité validés
│
├── .claude/
│   ├── skills/                 # Workflows auto-générés
│   │   ├── implement-feature.md
│   │   ├── fix-tests.md
│   │   ├── research.md
│   │   ├── review-own-code.md
│   │   ├── stack-conventions.md # Conventions spécifiques à la stack (auto-enrichi)
│   │   └── evolve-workflow.md
│   ├── settings.json
│   └── memory/
│       └── MEMORY.md
│
├── research/                   # Veille marché
│   ├── INDEX.md
│   ├── competitors/
│   ├── trends/
│   ├── user-needs/
│   └── regulations/
│
├── learnings/                  # Apprentissages inter-projets (copiés du template)
│
├── logs/                       # Historique des rétrospectives
│   ├── retrospective-N.md
│   ├── meta-retrospective-N.md
│   └── human-feedback-N.md     # Feedback humain par feature
│
├── e2e/                        # Tests Playwright
│   └── *.spec.ts
│
└── src/                        # Code applicatif
```

---

## Garde-fous

| Risque | Protection |
|---|---|
| Boucle infinie de fix | `MAX_FIX_ATTEMPTS` + détection de boucle (`error_hash`) + abandon à 3x même erreur |
| Roadmap infinie | `MAX_FEATURES` + `MAX_EVOLVE_CYCLES` + score maturité /30 (>= 24 → DONE) |
| IA ajoute trop de features | `MAX_AI_ROADMAP_ADDS` force une pause humaine |
| CLAUDE.md trop long | Nettoyage forcé à chaque méta-rétro |
| Recherche sans fin | Max turns par phase de recherche |
| Recherche non fiable | Cross-validation + score de confiance |
| Infos obsolètes | Fichiers datés, élagage > 3 mois |
| Dérive vs vision | BRIEF.md immuable, vérifié aux méta-rétros + evolve |
| Coût tokens | Budget prédictif + post-hoc (`MAX_BUDGET_USD`) + `adaptive_max_turns` |
| Claude bloqué (stall) | `STALL_KILL_THRESHOLD` kill auto après N checks sans données |
| Régression qualité | Tests E2E + `QUALITY_COMMAND` + `FUNCTIONAL_CHECK_COMMAND` + acceptance epic |
| Dette technique accumulée | Phase tech-debt auto quand >30% d'échecs (refactoring ciblé, max 5) |
| Brief incomplet/ambigu | Brief scoring /25 en phase strategy — hypothèses ajoutées si < 15 |
| Auto-modification destructive | Git versionne tout, rollback possible |
| Hallucination de sources | Règle : URL exacte + cross-validation 2 sources |
| Absence de l'humain | `PAUSE_EVERY_N_FEATURES` + signaux file-based + notifications |
| Perte de contexte inter-projets | `learnings/` accumule les apprentissages |
| Erreurs répétées inter-features | `known-issues.md` injecté dans les prompts de fix |
| Config obsolète après update | `migrate_config()` ajoute les paramètres manquants |
| State incohérent après crash | State machine (`workflow_phase`) + guards fichier |

---

## Lancement

```bash
# Cloner orc (une seule fois)
git clone git@github.com:gregoirelacoste/orc.git
cd orc

# Créer un projet (workspace séparé dans ~/projects/)
./orc.sh agent new mon-projet

# Ajuster la config si besoin
vim ~/projects/mon-projet/.orc/config.sh

# Lancer l'agent autonome
./orc.sh agent start mon-projet

# Surveiller
./orc.sh dash mon-projet          # Dashboard live
./orc.sh l mon-projet             # Logs temps réel
./orc.sh s mon-projet             # Status détaillé
```

---

## Limites connues

- **Context reset** : chaque invocation `claude -p` repart à zéro.
  Seuls les fichiers sur disque (CLAUDE.md, skills, code, research) persistent.
- **Pas de vraie créativité** : Claude optimise des patterns textuels.
  Les features qu'il propose seront des variations de ce qui existe, pas des innovations.
- **Plateau d'auto-amélioration** : après ~15 features, les leçons apprises
  deviennent marginales. Le modèle sous-jacent ne change pas.
- **Feedback humain indirect** : l'humain peut donner du feedback structuré
  via `human_pause` ou `.orc/human-notes.md`, mais pas de user testing réel.
- **Coût** : chaque feature complète (veille + impl + tests + reflect)
  consomme environ 50-100K tokens. Un projet de 30 features ~= 2-3M tokens.
