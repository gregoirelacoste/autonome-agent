Tu démarres un nouveau projet autonome.

0. Si le dossier `learnings/` contient des fichiers, lis-les.
   Ce sont les apprentissages des projets précédents.
   Intègre les règles et pièges pertinents dans ton CLAUDE.md initial.
   Ne copie pas aveuglément — adapte au contexte de CE projet.

1. Lis .orc/BRIEF.md pour comprendre le contexte, la vision et les contraintes.

2. Initialise le projet technique :
   - Structure de dossiers adaptée à la stack demandée
   - package.json / dépendances de base
   - Configuration (tsconfig, eslint, playwright, etc.)
   - .gitignore

3. Crée CLAUDE.md avec :
   - Description du projet
   - Commandes disponibles (dev, build, test, lint)
   - Architecture choisie et pourquoi
   - Conventions de code
   - Règles strictes (build doit passer, tests obligatoires, etc.)
   - Section "## Conventions de stack" avec les patterns spécifiques
     à la stack choisie (React, Astro, Java, etc.)
   - Section "## Anti-patterns" avec les erreurs classiques de cette stack

4. Crée le dossier `.orc/codebase/` — la mémoire structurée du projet :

   **INDEX.md** — la carte sémantique (TOUJOURS lu, max 40 lignes) :
   ```markdown
   # Codebase Index
   > Carte sémantique du projet. Lu avant chaque feature.
   > Pour le détail, consulte le fichier indiqué.

   ## Modules (→ .orc/codebase/modules.md)
   (sera rempli au fil des features)

   ## Utilities & Helpers (→ .orc/codebase/utilities.md)
   (fonctions réutilisables — NE PAS dupliquer)

   ## External Integrations (→ .orc/codebase/integrations.md)
   (APIs, services tiers, SDKs)

   ## Data Models (→ .orc/codebase/data-models.md)
   (schémas DB, types, interfaces)

   ## Architecture Decisions (→ .orc/codebase/architecture.md)
   (choix techniques et justification)

   ## Security Patterns (→ .orc/codebase/security.md)
   (patterns de sécurité validés pour ce projet)
   ```

   **Fichiers de détail** (créés vides, remplis au fil des features) :
   - `.orc/codebase/modules.md` — fonctions, classes, composants par dossier
   - `.orc/codebase/utilities.md` — helpers réutilisables avec signature et chemin
   - `.orc/codebase/integrations.md` — APIs/services intégrés, config, erreurs
   - `.orc/codebase/data-models.md` — schémas DB, types TS, interfaces
   - `.orc/codebase/architecture.md` — décisions prises, justification, alternatives rejetées
   - `.orc/codebase/security.md` — patterns de sécurité adoptés, vérifications faites

   **Règle clé** : l'INDEX.md reste COMPACT (max 40 lignes).
   Chaque section indique le fichier de détail + un résumé d'une phrase.
   L'IA lit l'index, puis pioche SEULEMENT le fichier de détail utile.

5. Crée les skills de base dans .claude/skills/ :
   - implement-feature.md (workflow d'implémentation)
   - fix-tests.md (workflow de correction de tests)
   - research.md (workflow de veille)
   - review-own-code.md (auto-review avant commit)
   - stack-conventions.md (rempli avec les conventions de la stack choisie)

6. Initialise la structure kanban et le ROADMAP.md :
   ```bash
   mkdir -p .orc/roadmap/{backlog,todo,in-progress,done}
   ```
   Crée `.orc/ROADMAP.md` :
   ```
   # Roadmap
   > Sera structurée après la phase de recherche initiale.
   ```

7. Initialise stack-conventions.md avec les patterns de la stack :
   - Si React/Next.js : hooks patterns, server/client components, state management
   - Si Astro : islands architecture, content collections, SSG vs SSR
   - Si Java/Spring : dependency injection, repository pattern, DTOs
   - Si Python/Django : models, views, serializers, middleware
   - Adapte au contexte du BRIEF, pas de conventions génériques inutiles

8. Crée un dossier `scripts/` avec des utilitaires adaptés à la stack :
   - `scripts/dev.sh` — lance le serveur dev avec rechargement auto
   - `scripts/test.sh` — lance les tests avec options utiles (watch, coverage, filtre)
   - `scripts/setup.sh` — installe les dépendances + configure l'env
   Adapte selon la stack. Chaque script doit être exécutable (`chmod +x`).
   Ne crée pas de scripts inutiles — uniquement ceux qui accélèrent le dev.

9. Gestion de l'environnement :
   - Crée un `.env.example` avec toutes les variables d'environnement nécessaires
     (clés API, URLs de service, secrets) avec des valeurs placeholder
   - Documente chaque variable avec un commentaire
   - Si la stack utilise une base de données, prévois un script de seed
     (`scripts/seed.sh` ou via la commande de la stack : `npx prisma db seed`, etc.)

10. Crée un pipeline CI basique adapté à la stack :
    - `.github/workflows/ci.yml` si GitHub est probable
    - Étapes : install → lint → build → test
    - Adapte selon la stack (npm, pip, gradle, go, etc.)
    - Garde le pipeline simple (pas de deploy, juste validation)

11. Commite : "chore: bootstrap project structure"
