# Modes d'initialisation de projet

orc propose plusieurs façons de créer un projet, selon que tu as déjà un brief ou non.

## Vue d'ensemble

| Mode | Commande | Quand l'utiliser |
|---|---|---|
| **Wizard interactif** | `orc agent new <nom>` | Tu pars de zéro, Claude t'aide à formuler |
| **Brief + clarification** | `orc agent new <nom> --brief x.md` | Tu as un draft, Claude l'enrichit |
| **Brief direct** | `orc agent new <nom> --brief x.md --no-clarify` | Ton brief est exhaustif |
| **Template vide** | `orc agent new <nom> --skip-brief` | Tu veux rédiger manuellement |

## Mode 1 — Wizard interactif (défaut)

```bash
orc agent new mon-projet
```

Claude joue le rôle de directeur produit et te pose ~22 questions structurées :

1. **Vision & Problème** (4 questions) — quel problème, pour qui, pourquoi maintenant, anti-scope
2. **Utilisateurs** (4 questions) — persona, device, parcours type
3. **Marché** (3 questions) — concurrents, différenciateur, modèle économique
4. **Fonctionnalités** (3 questions) — MVP, V2, hors scope
5. **Technique** (4 questions) — stack, BDD, APIs, type d'app
6. **Design & UX** (3 questions) — ambiance, langue, accessibilité
7. **Contraintes** (3 questions) — budget, légal, deadline

Les questions sont posées par petit groupe thématique. Claude rédige ensuite le `BRIEF.md` structuré.

**Idéal pour** : nouveaux projets, exploration d'idées, quand tu veux être guidé.

## Mode 2 — Brief existant avec clarification

```bash
orc agent new mon-projet --brief briefs/mon-brief.md
```

Tu fournis un brief en markdown (format libre). Claude :

1. **Lit le brief** et identifie les zones floues, manques, incohérences
2. **Pose des questions ciblées** par thème (pas toutes d'un coup)
   - Explique pourquoi chaque question est importante
   - Propose des suggestions par défaut quand c'est possible
3. **Enrichit le brief** avec tes réponses et le réécrit au format structuré

Le brief original est enrichi, pas remplacé. Les informations existantes sont conservées.

**Idéal pour** : tu as déjà une idée claire mais le brief a des trous. Ou tu as un brief d'un collègue/client à compléter.

### Format du brief source

Pas de format imposé. Un simple markdown avec les infos que tu as suffit :

```markdown
# Mon Projet

Application de gestion de recettes de cuisine.
Stack : Next.js + Supabase.
Features : recherche par ingrédients, partage de recettes, planning repas.
Mobile-first.
```

Claude se charge de détecter ce qui manque et de poser les bonnes questions.

### Résolution du chemin

Le fichier brief est cherché dans cet ordre :
1. Chemin absolu ou relatif depuis le répertoire courant
2. Relatif au dossier orc (`orc/briefs/mon-brief.md`)

```bash
# Ces trois commandes sont équivalentes
orc agent new mon-projet --brief /chemin/absolu/brief.md
orc agent new mon-projet --brief briefs/mon-brief.md
orc agent new mon-projet --brief ../mes-briefs/idee.md
```

## Mode 3 — Brief direct sans clarification

```bash
orc agent new mon-projet --brief briefs/mon-brief.md --no-clarify
```

Copie le brief tel quel dans le workspace. Aucune question, aucune modification.

**Idéal pour** : briefs déjà exhaustifs (générés par le wizard, ou très détaillés).

## Mode 4 — Template vide

```bash
orc agent new mon-projet --skip-brief
```

Copie `BRIEF.template.md` dans le workspace. Tu le remplis à la main avant de lancer l'orchestrateur.

**Idéal pour** : tu préfères rédiger le brief dans ton éditeur.

## Avec init.sh (legacy)

Le wizard original `init.sh` supporte aussi ces modes :

```bash
./init.sh mon-projet                              # Wizard interactif (5 étapes)
./init.sh mon-projet --brief briefs/mon-brief.md  # Brief + clarification
./init.sh mon-projet --brief x.md --no-clarify    # Brief direct
./init.sh mon-projet --skip-brief                 # Template vide
```

La différence avec `orc agent new` : `init.sh` inclut un wizard de configuration (mode d'autonomie, recherche, max features) et peut créer un repo GitHub.

## Ce qui est créé

Quel que soit le mode, le workspace créé est identique :

```
~/projects/mon-projet/
├── BRIEF.md                 ← Brief produit (source de vérité)
├── orchestrator.sh          ← Boucle principale
├── phases/                  ← Prompts par phase
├── skills-templates/        ← Skills copiées dans le projet
├── .orc/
│   ├── config.sh            ← Configuration du projet
│   ├── logs/                ← Logs orchestrateur
│   └── ...
└── project/                 ← Code produit (git indépendant)
```

## Écrire un bon brief

Un bon brief pour orc est **exhaustif et sans ambiguïté**. L'agent autonome ne peut pas te poser de questions une fois lancé — chaque zone floue = une décision arbitraire de l'IA.

Checklist :
- [ ] Chaque feature MVP a des critères d'acceptance
- [ ] Les cas limites sont documentés
- [ ] L'anti-scope est explicite (ce que l'IA ne doit PAS faire)
- [ ] La stack est définie ou explicitement laissée au choix de l'IA
- [ ] Les concurrents sont listés avec URLs

Voir `briefs/pc-builder.md` pour un exemple complet.
