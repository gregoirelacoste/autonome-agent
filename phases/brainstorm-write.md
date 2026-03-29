BRAINSTORM — Rédaction des tickets pour {{PROJECT_NAME}}

Tu dois écrire les tickets finaux validés par l'humain dans le kanban du projet.

## Tickets sélectionnés par l'humain

{{SELECTION_SUMMARY}}

## Propositions complètes (avec recherche et justifications)

{{PROPOSALS}}

## Brief produit (pour cohérence)

{{BRIEF}}

---

## Instructions

Écris chaque ticket validé comme un fichier markdown dans `{{PROJECT_DIR}}/.orc/roadmap/todo/`.

### Nommage des fichiers

- Format : `NNN-slug-court.md`
- Commence à NNN = {{NEXT_ID}} (zéro-paddé sur 3 chiffres : 001, 002, etc.)
- Le slug est 2-4 mots en kebab-case dérivés du titre
- Incrémente l'ID de 1 pour chaque ticket

### Format EXACT de chaque fichier

```
---
id: NNN
title: "Titre concis et orienté action"
priority: P0|P1|P2|P3
type: feature|bugfix|evolution|refactor
effort: XS|S|M|L|XL
tags: [tag1, tag2, tag3]
epic: nom-epic-kebab-case
created: YYYY-MM-DD
source: brainstorm
---

## Contexte
Pourquoi ce ticket existe. Justification métier claire.
Si applicable, cite le brief : "Le brief mentionne que..."
Si la recherche web a trouvé des éléments pertinents, cite-les ici.

## Spécification
Ce qui doit être implémenté concrètement.
Sois précis sur :
- Les fichiers/modules à modifier ou créer
- Les APIs ou librairies à utiliser
- Le comportement attendu (entrées → sorties)
- Les cas limites à gérer

## Critères de validation
- [ ] Critère testable 1
- [ ] Critère testable 2
- [ ] Critère testable 3
(3-5 critères par ticket, tous vérifiables)

## Notes
Trouvailles de la recherche web pertinentes pour l'implémentation.
Liens, exemples, patterns recommandés.
Considérations techniques ou alternatives envisagées.
```

### Règles

- Chaque ticket doit être **autosuffisant** : un développeur peut le lire et implémenter sans contexte extérieur
- La spécification est le coeur : c'est ce que Claude Code lira pour coder. Sois détaillé.
- Les critères doivent être **testables automatiquement** quand c'est possible
- L'epic doit être cohérent entre les tickets du même thème
- Les tags permettent le filtrage — utilise les domaines pertinents (auth, ui, api, db, perf, etc.)
- Intègre les trouvailles de la recherche web dans les sections Contexte et Notes
- L'ordre d'implémentation est déterminé par la priorité : P0 en premier, P3 en dernier
- Les dépendances entre tickets doivent être mentionnées dans le Contexte ("Après le ticket NNN...")
