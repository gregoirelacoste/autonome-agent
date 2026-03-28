PHASE DOCUMENTATION UTILISATEUR — Le MVP est fonctionnel.

Le produit est utilisable. Génère la documentation pour les utilisateurs finaux (pas les développeurs).

1. Lis CLAUDE.md, .orc/BRIEF.md, et .orc/ROADMAP.md
2. Lis les rapports d'acceptance : .orc/logs/acceptance-*.md
3. Explore le code pour comprendre les fonctionnalités implémentées

### Documentation à générer

Crée un dossier `docs/` (ou enrichis-le) avec :

**docs/getting-started.md** — Guide de démarrage :
- Prérequis (Node, Python, Docker... selon la stack)
- Installation en 3 étapes max
- Premier lancement
- Premier scénario utilisateur (le parcours principal)

**docs/features.md** — Guide des fonctionnalités :
- Une section par feature implémentée
- Screenshots ou descriptions du comportement attendu
- Cas d'usage typiques

**docs/faq.md** — Questions fréquentes :
- Problèmes courants et solutions
- Limites connues du produit

### Mettre à jour le README.md

- Section "Quick Start" claire et testée
- Badges si pertinent (build status, version)
- Lien vers docs/

RÈGLES :
- Écris pour l'UTILISATEUR, pas le développeur
- Pas de jargon technique sauf si le produit est technique
- Chaque instruction doit être copiable/exécutable
- Max 3 fichiers de doc — concis > exhaustif
