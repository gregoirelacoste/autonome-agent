PLANIFICATION DE LA FEATURE : {{FEATURE_NAME}}

Le contexte projet (INDEX.md + auto-map.md) est injecté ci-dessus.

**PRIORITÉ ABSOLUE : écris d'abord le fichier plan, puis lis si tu as besoin de détails.**

Étape 1 — Lis la spec de cette feature dans .orc/ROADMAP.md (1 lecture max).
Étape 2 — Écris immédiatement le plan dans .orc/logs/plan-{{N}}.md avec ce format :

## Plan : {{FEATURE_NAME}}

### Fichiers à modifier
- `path/to/file.ts` — [ce qui change]

### Fichiers à créer
- `path/to/new.ts` — [rôle]

### Interfaces / signatures clés
```
[pseudo-code des interfaces ou signatures principales]
```

### Tests à écrire
- [test 1 — ce qu'il vérifie]

### Risques identifiés
- [risque potentiel et mitigation]

Étape 3 — Seulement si nécessaire après avoir écrit le plan : lis 1-2 fichiers existants pour affiner.

RÈGLES :
- Max 20 lignes de plan. Sois concis et actionnable.
- Ne crée PAS de code. Uniquement le plan.
- Si un module existant couvre déjà le besoin, note "réutiliser X" au lieu de créer.
- Le plan doit exister dans le fichier avant la fin — c'est l'unique livrable de cette phase.
