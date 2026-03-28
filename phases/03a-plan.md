PLANIFICATION DE LA FEATURE : {{FEATURE_NAME}}

Avant de coder, produis un plan concis. Le contexte projet (INDEX.md + auto-map.md) est injecté ci-dessus.
Lis aussi la spec de cette feature dans .orc/ROADMAP.md.

Puis écris un plan dans .orc/logs/plan-{{N}}.md avec ce format exact :

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

RÈGLES :
- Max 20 lignes de plan. Sois concis et actionnable.
- Ne crée PAS de code. Uniquement le plan.
- Si un module existant couvre déjà le besoin, note "réutiliser X" au lieu de créer.
