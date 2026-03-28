---
name: test-orchestrator
description: Vérifie la syntaxe et la cohérence de l'orchestrateur avant commit
user_invocable: true
---

## Checklist de validation

### 1. Syntaxe bash
```bash
bash -n orchestrator.sh && echo "✓ orchestrator.sh"
bash -n init.sh && echo "✓ init.sh"
bash -n config.default.sh && echo "✓ config.default.sh"
```

### 2. Shellcheck (si disponible)
```bash
shellcheck -x orchestrator.sh init.sh 2>&1 || true
```

### 3. Cohérence config
Vérifier que toutes les variables utilisées dans orchestrator.sh
sont définies dans config.default.sh :
- Grep les `${}` et `$VAR` dans orchestrator.sh
- Vérifier qu'ils existent dans config.default.sh ou sont définis localement

### 4. Cohérence phases
Vérifier que chaque fichier dans phases/ référencé par orchestrator.sh existe :
- `render_phase "00-bootstrap.md"` → phases/00-bootstrap.md doit exister
- Les placeholders {{VAR}} dans chaque phase doivent correspondre aux arguments passés

### 5. Cohérence documentation
Vérifier que ARCHITECTURE.md et README.md sont à jour avec :
- Les noms de variables dans config.default.sh
- Les phases listées
- Le flow décrit vs le flow réel dans orchestrator.sh

### 6. Dry-run mental
Parcourir le flow complet mentalement :
1. Premier lancement (rien n'existe)
2. Reprise après crash (state.json existant)
3. Toutes les features cochées (phase evolve)
4. Mode nohup (pas de terminal)
