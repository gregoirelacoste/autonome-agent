---
name: stack-conventions
description: Conventions et patterns spécifiques à la stack technique du projet
user_invocable: true
---

## Stack Conventions — {{STACK}}

Ce fichier est auto-enrichi par l'IA au fil du projet.
Il capture les conventions spécifiques à la stack technique choisie.

### Instructions

À chaque reflect (phase 05), mets à jour ce skill avec :
1. Les patterns et conventions découverts pendant l'implémentation
2. Les anti-patterns à éviter (spécifiques à cette stack)
3. Les utilities/helpers créés et réutilisables
4. Les décisions techniques et leur justification

### Structure attendue

```markdown
## Stack : [stack du projet]

## Conventions de code
- [convention 1 — ex: "utiliser des server components par défaut (Next.js)"]
- [convention 2 — ex: "nommage PascalCase pour les composants, camelCase pour les utils"]

## Patterns adoptés
- [pattern 1 — ex: "Repository pattern pour l'accès DB"]
- [pattern 2 — ex: "Custom hooks pour la logique métier partagée"]

## Anti-patterns identifiés
- [anti-pattern 1 — ex: "Ne PAS utiliser `any` en TypeScript — toujours typer"]
- [anti-pattern 2 — ex: "Ne PAS faire de fetching dans useEffect — utiliser useSWR"]

## Utilities créées (à réutiliser, NE PAS dupliquer)
- [util 1 — ex: "formatDate() dans src/utils/date.ts"]
- [util 2 — ex: "useAuth() custom hook dans src/hooks/useAuth.ts"]

## Dépendances externes & APIs intégrées
- [dep 1 — ex: "Stripe v11 — paiements, voir src/lib/stripe.ts"]
- [dep 2 — ex: "SendGrid — emails transactionnels, voir src/lib/email.ts"]

## Sécurité (patterns validés pour ce projet)
- [sec 1 — ex: "bcrypt salt rounds=12 pour les mots de passe"]
- [sec 2 — ex: "Parameterized queries partout (jamais de string concat SQL)"]

## Performance (optimisations appliquées)
- [perf 1 — ex: "React.memo sur les composants liste (ProductCard, UserRow)"]
- [perf 2 — ex: "Pagination côté serveur pour les listes > 50 items"]
```

### Quand consulter ce skill

- AVANT d'implémenter une feature : vérifier les utilities existantes
- AVANT de créer un nouveau helper : vérifier qu'il n'existe pas déjà
- APRÈS chaque feature : enrichir avec les nouveaux patterns/utilities
- À chaque méta-rétro : nettoyer les patterns obsolètes
