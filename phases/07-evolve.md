PHASE ÉVOLUTION — Toutes les features de la ROADMAP sont terminées.

1. Relis .orc/BRIEF.md (la vision originale)
2. Analyse le projet dans son état actuel (code, tests, .orc/research/)
3. Lis .orc/research/INDEX.md et les SYNTHESIS.md
4. Lis les rapports d'acceptance : .orc/logs/acceptance-*.md

### Étape 1 : Score de maturité produit

Évalue le produit et écris le score dans .orc/logs/maturity-score.md :

| Critère | Score (1-5) | Justification |
|---------|-------------|---------------|
| **Parcours utilisateur principal** fonctionne | | Le user peut-il faire l'action principale du brief ? |
| **Données** se créent/lisent/modifient/suppriment | | CRUD fonctionne-t-il ? |
| **Erreurs** gérées proprement | | Pas de crash visible, messages clairs |
| **UI/UX** cohérente et utilisable | | Pas de pages cassées, navigation logique |
| **Tests** couvrent les scénarios clés | | Les tests valident le comportement, pas juste la compilation |
| **Documentation** utilisateur minimale | | README + setup instructions suffisantes |

**Score total : X/30**

### Étape 2 : Décision

**Si score >= 24/30 (produit mature)** → Option B (DONE)
**Si score < 24/30** → Option A (le pipeline auto-brainstorm se chargera de créer les tickets détaillés)

### Option A : Continuer

Note dans .orc/logs/maturity-score.md les 3 critères les plus faibles et les axes d'amélioration prioritaires. Le système lancera automatiquement un brainstorm complet (recherche web, propositions, rédaction de tickets) après cette phase.

**Ne crée PAS de tickets toi-même** — c'est la phase auto-brainstorm qui s'en charge avec un pipeline plus complet (recherche concurrence, diversité thématique, tickets détaillés).

### Option B : Projet complet
Crée DONE.md avec :
- Score de maturité final (tableau ci-dessus)
- Résumé du projet livré
- Features implémentées (liste)
- Métriques : features, tests, fichiers, coût total
- Ce qui reste à faire par un humain (feedback utilisateur, config prod, etc.)
