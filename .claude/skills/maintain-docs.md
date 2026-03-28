---
name: maintain-docs
description: Met à jour la documentation utilisateur, le README, le help CLI et les tutoriels après chaque changement
user_invocable: true
---

Tu es responsable de la **documentation vivante** du projet orc.
Après chaque changement de code, tu dois mettre à jour la documentation impactée.

---

## Quand utiliser ce skill

- Après avoir ajouté/modifié une commande CLI
- Après avoir ajouté/modifié un flag ou une option
- Après avoir ajouté/modifié un mode ou un workflow
- Après avoir modifié la configuration (config.default.sh)
- Après avoir ajouté/modifié une phase, un skill, un template
- Lors d'un bump de version
- Quand tu constates qu'une doc est obsolète ou incomplète

## Process en 4 étapes

### Étape 1 — Lire l'index des docs

Lis `docs/INDEX.md` pour connaître les documents existants et les règles de maintenance.
Ne lis que l'INDEX — pas tous les fichiers. L'index te dit quel fichier couvre quel sujet.

### Étape 2 — Identifier les docs impactées

Pour chaque changement, identifie **précisément** quels documents sont impactés :

| Type de changement | Documents à mettre à jour |
|---|---|
| Nouvelle commande CLI | `docs/commands-reference.md` + `orc.sh` (help) + `README.md` |
| Nouveau flag/option | `docs/commands-reference.md` + doc spécifique + `README.md` si majeur |
| Nouveau mode d'init | `docs/init-modes.md` + `docs/getting-started.md` |
| Changement config | `docs/configuration.md` + `codebase/config-params.md` |
| Changement GitHub | `docs/github-integration.md` |
| Changement contrôle humain | `docs/human-controls.md` |
| Bug fréquent résolu | `docs/faq.md` (section troubleshooting) |
| Nouvelle phase/skill | `codebase/phases.md` ou `codebase/skills.md` + `CLAUDE.md` |

### Étape 3 — Mettre à jour

Pour **chaque** document impacté :

1. Lis le fichier concerné
2. Modifie la section pertinente (pas de réécriture complète)
3. Vérifie que les exemples de code sont corrects et à jour
4. Met à jour la version dans `docs/INDEX.md` si c'est un changement significatif

**Points d'attention :**
- Le `README.md` est la porte d'entrée — il doit rester concis et à jour
- Le help CLI (`orc_help()` dans `orc.sh`) doit refléter les commandes disponibles
- Les exemples de commandes doivent être testables
- Les tableaux de paramètres doivent correspondre à `config.default.sh`

### Étape 4 — Vérifier la cohérence

Vérifie que :
- [ ] Le README mentionne les nouvelles fonctionnalités majeures
- [ ] Le help CLI (`orc help`) liste les nouvelles commandes
- [ ] Les docs de détail sont cohérentes entre elles
- [ ] Les chemins de fichiers dans les docs existent
- [ ] La version dans `docs/INDEX.md` est à jour
- [ ] `CLAUDE.md` reflète les nouveaux patterns/conventions

## Structure des docs

```
docs/                          ← Documentation utilisateur
├── INDEX.md                   ← Carte des docs (LIS EN PREMIER)
├── getting-started.md         ← Tuto premier projet
├── init-modes.md              ← Modes d'init (wizard, --brief, etc.)
├── commands-reference.md      ← Référence CLI complète
├── configuration.md           ← Guide de configuration
├── github-integration.md      ← Options GitHub
├── human-controls.md          ← Pause, stop, notes, feedback
└── faq.md                     ← FAQ et troubleshooting
```

## Intégration dans le workflow de dev orc

Ce skill doit être invoqué **systématiquement** après une implémentation.
Pattern recommandé :

1. Implémenter le changement
2. Vérifier la syntaxe (`bash -n`)
3. **Invoquer ce skill** pour mettre à jour la doc
4. Commit le tout ensemble (code + docs)

## Conventions

- Langue : français (comme le reste du projet)
- Format : Markdown, tableaux pour les paramètres, blocs de code pour les commandes
- Pas d'emojis dans les docs
- Exemples concrets avec commandes copiables
- Chaque page doit être lisible indépendamment (pas de prérequis implicite)
