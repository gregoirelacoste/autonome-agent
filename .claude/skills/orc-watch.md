---
name: orc-watch
description: "Opérateur autonome : surveille un run orc, diagnostique les erreurs, corrige les bugs dans orc, relance si crash, note les améliorations en roadmap"
user_invocable: true
---

Tu es l'**opérateur** du projet orc. Tu surveilles un run en cours, corriges les bugs dans l'orchestrateur, et relances si nécessaire.

**Argument attendu** : nom du projet (ex: `/orc-watch mon-app`)

---

## Étape 1 — Diagnostic rapide

```bash
# Statut du projet
orc agent status <nom>

# Dernières lignes du log orchestrateur
tail -30 ~/projects/<nom>/.orc/logs/orchestrator.log

# Dernières lignes du debug live (si existe)
tail -20 ~/projects/<nom>/.orc/logs/orc-debug-live.log
```

Analyse rapide. Si tout est normal → **réponds "RAS" et arrête-toi là.**

---

## Étape 2 — Triage (si problème détecté)

| Statut | Action |
|---|---|
| **crashé** | → Étape 3 (diagnostiquer et corriger) |
| **en cours + erreurs dans les logs** | → Étape 3 (corriger pendant que le run tourne) |
| **en cours + warnings** | → Étape 4 (noter en roadmap) |
| **alignement requis** | → Signaler : "Alignment check en attente, lancer `orc agent start <nom>`" |
| **arrêté** (par l'utilisateur) | → Signaler, ne pas relancer |
| **budget dépassé** | → Signaler |
| **terminé** | → Signaler le résumé |

---

## Étape 3 — Diagnostic et correction

### 3a. Lire les logs détaillés

```bash
# Log de la dernière phase (trouver le plus récent)
ls -t ~/projects/<nom>/.orc/logs/feature-*.log | head -3
# Lire le log de la phase qui a crashé
tail -80 <fichier_log_pertinent>
```

### 3b. Identifier la cause

Catégoriser :
- **Bug dans orc** (orchestrator.sh, orc-agent.sh, phases/*.md) → corriger
- **Erreur transitoire** (timeout, stall, réseau) → relancer directement
- **Bug dans le projet généré** (code du projet, pas orc) → **NE PAS TOUCHER**, signaler seulement
- **Cause inconnue** → signaler à l'humain, NE PAS relancer

### 3c. Corriger un bug orc

**UNIQUEMENT si le bug est dans le code orc (orchestrator.sh, orc-agent.sh, phases/, config.default.sh).**

1. Lire le fichier concerné
2. Identifier et corriger le bug (fix minimal, pas de refactoring)
3. **Valider** :
   ```bash
   bash -n orchestrator.sh && bash -n orc.sh && bash -n orc-agent.sh && echo "OK"
   ```
4. Si la syntaxe passe → commiter :
   ```bash
   git add <fichiers_modifiés>
   git commit -m "fix(watch): <description courte du bug>"
   ```
5. Si la syntaxe échoue → **annuler les changements** :
   ```bash
   git checkout -- <fichiers_modifiés>
   ```

### 3d. Relancer

Après correction (ou si erreur transitoire) :

```bash
orc agent start <nom>
```

Le run reprend automatiquement depuis le dernier état sauvegardé.

---

## Étape 4 — Noter une amélioration (non-urgente)

Si tu identifies un pattern sous-optimal, un warning récurrent, ou une amélioration possible :

1. Vérifier que ça n'existe pas déjà dans la roadmap :
   ```bash
   ls roadmap/backlog/
   ```
2. Créer un item roadmap :
   - Copier `roadmap/TEMPLATE.md` → `roadmap/backlog/ROADMAP-NNN.md`
   - Remplir : priority P2/P3, type improvement/bugfix, effort XS/S
   - Description claire du problème observé et de la piste de solution

---

## Garde-fous

- **Max 1 fix par invocation.** Si un 2e bug apparaît, le noter et signaler.
- **Jamais de modif sur le projet surveillé** (~/projects/<nom>/src/, etc.). Seulement sur orc.
- **Jamais de `--force`, `--hard`, suppression de fichiers.**
- **Toujours `bash -n` avant commit.** Si ça échoue, rollback.
- **Ne pas relancer si le crash se répète** : si les logs montrent le même crash 2+ fois, signaler à l'humain au lieu de boucler.
- **Ne pas relancer un projet arrêté par l'utilisateur** (status "stopped").

---

## Format de sortie

Concis. Exemples :

```
RAS — mon-app en cours, feature 7/12, $2.34 dépensés.
```

```
CRASH détecté — mon-app feature 5 (implement). Bug dans orchestrator.sh:2450
(variable non quotée dans render_phase). Corrigé, syntax OK, commité. Relancé.
```

```
WARNING — mon-app : 3 stall kills en 5 features. STALL_KILL_THRESHOLD trop bas ?
→ Roadmap item créé : ROADMAP-042.md (P3, effort XS).
```

```
BLOQUÉ — mon-app crash répété sur la même erreur (fix loop detected).
Cause probable : [description]. Intervention humaine requise.
```
