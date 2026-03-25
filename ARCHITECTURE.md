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
            │   Implement ──▶ Test ──▶ Fix (loop) ─┐   │
            │                                      │   │
            │       ┌──────────────────────────────┘   │
            │       ▼                                   │
            │   Reflect & Evolve                        │
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
                    ROADMAP vide ?
                    ├── non → nouvelles features proposées → boucle
                    └── oui → DONE.md → fin
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
1. Croise `BRIEF.md` (vision immuable) avec `research/INDEX.md` (données marché)
2. Structure `ROADMAP.md` en epics de 3-5 features liées
3. Chaque feature référence un insight de la recherche
4. Ordonne par : impact utilisateur × faisabilité
5. Quick wins en premier

**Format ROADMAP.md :**
```markdown
## Epic 1 : [nom]
Justification : [référence research/...]
- [ ] Feature 1.1 — description | critères d'acceptance
- [ ] Feature 1.2 — ...
```

---

## Phase 3 — BOUCLE FEATURE (coeur du système)

Pour chaque feature de la roadmap :

### 3a. Veille ciblée (avant chaque epic)

Recherche focalisée sur le domaine de l'epic :
- Comment les concurrents gèrent cette fonctionnalité
- Best practices UX spécifiques
- APIs / données publiques exploitables

Met à jour `research/` et ajuste les specs dans `ROADMAP.md`.

### 3b. Implémentation

1. Crée une branche `feature/<nom>`
2. Lit le code existant et `research/INDEX.md`
3. Implémente la feature
4. Écrit les tests E2E Playwright
5. Build + tests locaux
6. Auto-review du code
7. Commit atomique

### 3c. Test & Fix Loop

```
attempt = 0
while (build échoue OU tests échouent) AND attempt < MAX_FIX:
    Claude analyse l'erreur
    Claude corrige le code
    Relance build + tests
    attempt++

Si attempt == MAX_FIX:
    Feature marquée en échec, on passe à la suite
```

### 3d. Reflect & Evolve (auto-amélioration)

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

Claude analyse le projet terminé et :
1. Propose de nouvelles features basées sur la veille récente
2. Identifie des optimisations ou refactorings
3. Ou déclare le projet terminé → crée `DONE.md` avec bilan final

---

## Auto-amélioration — ce que Claude modifie sur lui-même

| Fichier | Rôle | Modifié quand |
|---|---|---|
| `codebase/INDEX.md` | Carte sémantique du projet | Après chaque feature (Reflect) |
| `codebase/*.md` | Détail par domaine | Après chaque feature (Reflect) |
| `stack-conventions.md` | Conventions de stack | Après chaque feature (Reflect) |
| `CLAUDE.md` | Ses instructions | Après chaque feature (Reflect) |
| `.claude/skills/*.md` | Ses workflows | Quand un pattern se répète |
| `ROADMAP.md` | Sa direction | Méta-rétros + veille |

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

Tout est configurable dans `.orc/config.sh` :

```bash
# === GARDE-FOUS ===
MAX_FIX_ATTEMPTS=5              # Tentatives de correction par feature
MAX_FEATURES=50                 # Nombre total de features avant arrêt
MAX_TURNS_PER_INVOCATION=50     # Limite de turns par appel Claude

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
MAX_TURNS_RESEARCH_INITIAL=80   # Budget recherche initiale
MAX_TURNS_RESEARCH_EPIC=40      # Budget veille ciblée par epic
MAX_TURNS_RESEARCH_TREND=50     # Budget veille tendances

# === TECHNIQUE ===
QUALITY_COMMAND=""               # Quality gate post-tests (ex: lighthouse, bundle-size)
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
| **implement** | INDEX.md + auto-map.md + fichiers de détail pertinents + stack-conventions.md |
| **fix** | auto-map.md + security.md + réflexions passées |
| **strategy** | INDEX.md + architecture.md + research/INDEX.md |
| **reflect** | auto-map.md (vérité) + INDEX.md + fichiers de détail à mettre à jour |
| **meta-retro** | INDEX.md + auto-map.md + audit complet de cohérence |

L'IA charge ~200 tokens de contexte pertinent au lieu de ~2000 tokens de tout.

---

## Structure complète des fichiers

```
project/
├── BRIEF.md                    # Vision produit (IMMUABLE — jamais modifié par Claude)
├── CLAUDE.md                   # Instructions (auto-évolutif)
├── ROADMAP.md                  # Backlog en epics (auto-évolutif)
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
| Boucle infinie de fix | `MAX_FIX_ATTEMPTS` + détection de boucle (hash erreur) |
| Roadmap infinie | `MAX_FEATURES` + `MAX_EVOLVE_CYCLES` + DONE.md |
| IA ajoute trop de features | `MAX_AI_ROADMAP_ADDS` force une pause humaine |
| CLAUDE.md trop long | Nettoyage forcé à chaque méta-rétro |
| Recherche sans fin | Max turns par phase de recherche |
| Recherche non fiable | Cross-validation + score de confiance |
| Infos obsolètes | Fichiers datés, élagage > 3 mois |
| Dérive vs vision | BRIEF.md immuable, vérifié aux méta-rétros + evolve |
| Coût tokens | `--max-turns` par invocation + `MAX_BUDGET_USD` |
| Régression qualité | Tests E2E + `QUALITY_COMMAND` optionnel |
| Auto-modification destructive | Git versionne tout, rollback possible |
| Hallucination de sources | Règle : URL exacte + cross-validation 2 sources |
| Absence de l'humain | `PAUSE_EVERY_N_FEATURES` + signaux file-based + notifications |
| Perte de contexte inter-projets | `learnings/` accumule les apprentissages |

---

## Lancement

```bash
# Cloner le repo orchestrateur
git clone git@github.com:gregoirelacoste/orc.git mon-projet
cd mon-projet

# Option A : Brief assisté par Claude (recommandé)
./orchestrator.sh --brief
# ou avec une idée de départ :
./orchestrator.sh --brief "un comparateur d'assurances auto pour les jeunes conducteurs"

# Option B : Brief manuel
cp BRIEF.template.md BRIEF.md
vim BRIEF.md

# Ajuster la config si besoin
vim config.sh

# Lancer l'agent autonome
nohup ./orchestrator.sh > logs/orchestrator.log 2>&1 &

# Surveiller
tail -f logs/orchestrator.log
watch -n 30 'grep -c "\[x\]" project/ROADMAP.md'
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
