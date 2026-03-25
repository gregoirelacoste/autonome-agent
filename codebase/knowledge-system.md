# ORC — Système de connaissance projet

Architecture de la mémoire inspirée de MemGPT, Voyager, Reflexion, CoALA, et Aider.

## Niveaux de mémoire (CoALA)

| Type | Implémentation ORC | Quand |
|---|---|---|
| Working memory | Prompt de phase + context hints | Chaque invocation |
| Episodic memory | logs/retrospective-*.md, fix-reflections-*.md | Après chaque feature/fix |
| Semantic memory | codebase/INDEX.md + fichiers détail, research/ | Lu avant implement, enrichi à reflect |
| Procedural memory | phases/*.md, skills/, CLAUDE.md | Bootstrap + auto-enrichi |

## Index sémantique (codebase/)

```
codebase/
├── INDEX.md        ← carte sémantique (max 40 lignes), lu TOUJOURS
├── auto-map.md     ← carte auto-générée (grep exports), vérité du code
├── modules.md      ← détail par module
├── utilities.md    ← helpers réutilisables
├── integrations.md ← APIs/services tiers
├── data-models.md  ← schémas, types, interfaces
├── architecture.md ← décisions techniques + justification
└── security.md     ← patterns de sécurité validés
```

## Auto-map (pattern Aider repo map)
- Fonction : generate_repo_map() dans orchestrator.sh
- Multi-stack : TS/JS, Python, Java, Go, Astro
- Regénéré avant chaque feature
- Tronqué à 200 lignes max
- L'IA ne le modifie jamais — c'est la vérité du code

## Réflexions structurées (pattern Reflexion)
- Après chaque échec de fix → logs/fix-reflections-N.md
- Format : "Ce que j'ai tenté / Pourquoi ça a échoué / Ce que je dois essayer"
- Injecté dans les tentatives suivantes

## Contexte adaptatif (pattern GITM + ACE)
- run_claude() injecte un context_hint différent selon $phase_name
- implement ≠ fix ≠ strategy ≠ reflect ≠ meta-retro
- L'IA ne charge que les fichiers pertinents pour la phase

## Mémoire inter-projets (learnings/)
- orchestrator-improvements.md → copié dans learnings/ en fin de projet
- Learnings lus au bootstrap du projet suivant
- Cycle vertueux cross-projets

## Stack conventions (skill auto-enrichie)
- .claude/skills/stack-conventions.md
- Initialisé au bootstrap selon la stack du BRIEF
- Enrichi à chaque reflect
- Conventions, anti-patterns, utilities, sécurité, performance
