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

Après chaque feature, Claude améliore ses propres outils :

1. **CLAUDE.md** — ajoute des règles si piège découvert, supprime les obsolètes
2. **Skills** — crée un nouveau skill si pattern répété manuellement,
   met à jour un skill existant s'il était inadapté
3. **ROADMAP.md** — coche la feature, ajoute des dépendances découvertes
4. **Logs** — écrit `logs/retrospective-N.md`

> C'est cette phase qui fait que la feature 20 est mieux implémentée
> que la feature 1 : l'agent a appris de SES propres erreurs sur CE projet.

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
| `CLAUDE.md` | Ses instructions | Après chaque feature (Reflect) |
| `.claude/skills/*.md` | Ses workflows | Quand un pattern se répète |
| `.claude/memory/` | Sa mémoire | Leçons inter-sessions |
| `ROADMAP.md` | Sa direction | Méta-rétros + veille |
| `.claude/settings.json` | Ses hooks/permissions | Si besoin d'automatiser |

Le cycle vertueux :
```
Feature 1 : erreurs basiques → Reflect ajoute 3 règles au CLAUDE.md
Feature 3 : même type d'erreur E2E → crée un skill fix-e2e.md
Feature 5 : méta-rétro → CLAUDE.md nettoyé, skills affinées
Feature 10 : dette technique détectée → refactoring ajouté à la roadmap
Feature 15 : plateau → les améliorations deviennent marginales
```

---

## Configuration — Intervention humaine

Tout est configurable en haut de l'orchestrateur :

```bash
# === GARDE-FOUS ===
MAX_FIX_ATTEMPTS=5              # Tentatives de correction par feature
MAX_FEATURES=50                 # Nombre total de features avant arrêt
MAX_TURNS_PER_INVOCATION=50     # Limite de turns par appel Claude

# === RYTHME ===
RESEARCH_FREQUENCY=5            # Veille tendances toutes les N features
EPIC_SIZE=3                     # Nombre de features par epic

# === INTERVENTION HUMAINE ===
MAX_FEATURES_BEFORE_PAUSE=10    # Pause humaine toutes les N features
REQUIRE_HUMAN_APPROVAL=false    # true = attend validation avant merge
AUTO_EVOLVE_ROADMAP=true        # Claude peut ajouter des features seul

# === RECHERCHE ===
MAX_TURNS_RESEARCH_INITIAL=80   # Budget recherche initiale
MAX_TURNS_RESEARCH_EPIC=40      # Budget veille ciblée par epic
MAX_TURNS_RESEARCH_TREND=50     # Budget veille tendances
```

**Modes d'utilisation :**

| Mode | Config | Comportement |
|---|---|---|
| **Pilote auto** | `REQUIRE_HUMAN_APPROVAL=false` | Totalement autonome |
| **Copilote** | `REQUIRE_HUMAN_APPROVAL=true` | Claude code, humain valide les merges |
| **Supervisé** | `MAX_FEATURES_BEFORE_PAUSE=3` | Pause fréquente pour check humain |
| **Recherche seule** | Lancer uniquement phases 1-2 | Veille + roadmap sans code |

---

## Structure complète des fichiers

```
project/
├── BRIEF.md                    # Vision produit (IMMUABLE — jamais modifié par Claude)
├── CLAUDE.md                   # Instructions (auto-évolutif)
├── ROADMAP.md                  # Backlog en epics (auto-évolutif)
├── DONE.md                     # Créé quand le projet est terminé
│
├── .claude/
│   ├── skills/                 # Workflows auto-générés
│   │   ├── implement-feature.md
│   │   ├── fix-tests.md
│   │   ├── research.md
│   │   ├── review-own-code.md
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
├── logs/                       # Historique des rétrospectives
│   ├── retrospective-N.md
│   └── meta-retrospective-N.md
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
| Boucle infinie de fix | `MAX_FIX_ATTEMPTS` puis abandon de la feature |
| Roadmap infinie | `MAX_FEATURES` + DONE.md |
| CLAUDE.md trop long | Nettoyage forcé à chaque méta-rétro |
| Recherche sans fin | Max turns par phase de recherche |
| Infos obsolètes | Fichiers datés, élagage > 3 mois |
| Dérive vs vision | BRIEF.md immuable, vérifié aux méta-rétros |
| Coût tokens | `--max-turns` par invocation |
| Régression code | Tests E2E complets relancés à chaque feature |
| Auto-modification destructive | Git versionne tout, rollback possible |
| Hallucination de sources | Règle : toujours citer l'URL exacte |
| Absence de l'humain | `MAX_FEATURES_BEFORE_PAUSE` force un checkpoint |

---

## Lancement

```bash
# 1. Préparer
mkdir -p project
# Écrire BRIEF.md avec la vision du projet
cd project && git init && cd ..

# 2. Lancer
chmod +x orchestrator.sh
nohup ./orchestrator.sh > orchestrator.log 2>&1 &

# 3. Surveiller
tail -f orchestrator.log
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
- **Pas de feedback utilisateur réel** : peut lire les forums mais ne peut pas
  faire de user testing ni observer de vrais utilisateurs.
- **Coût** : chaque feature complète (veille + impl + tests + reflect)
  consomme environ 50-100K tokens. Un projet de 30 features ~= 2-3M tokens.

---

## Prochaine étape

Écrire `orchestrator.sh` — le script bash qui orchestre tout le flow.
Puis écrire un `BRIEF.md` pour un projet concret et lancer.
