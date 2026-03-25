# Brief — SEO GEO Content Platform

## Vision

Plateforme de contenu SEO/GEO optimisée, construite avec Astro (SSG), qui génère automatiquement des articles basés sur des données de recherche de mots-clés (SE Ranking API). Le site est conçu pour performer à la fois sur les moteurs de recherche classiques (Google) et sur les moteurs génératifs (ChatGPT Search, Perplexity, Google AI Overviews). Un système de stratégie social media accompagne chaque article publié.

**En une phrase** : un site qui se positionne, génère son contenu, et distribue sa stratégie social — piloté par des données SEO réelles.

## Fonctionnalités cibles

### Epic 1 — Fondations site Astro SSG
- Structure Astro avec Content Collections (Zod schemas) pour les articles
- Layout responsive, design system minimal (pas de framework CSS lourd — Tailwind ou vanilla)
- BaseHead component avec SEO meta complet (title, description, canonical, OG, Twitter Cards)
- JSON-LD structured data : WebSite, Organization, BreadcrumbList sur toutes les pages
- Sitemap automatique (`@astrojs/sitemap`)
- `robots.txt` configuré pour les AI crawlers (GPTBot, PerplexityBot, ClaudeBot, ChatGPT-User → Allow)
- `llms.txt` à la racine (résumé du site pour les LLMs)
- Core Web Vitals optimisé (Image component, zero JS by default, `compressHTML: true`)
- Page 404 personnalisée

### Epic 2 — SEO technique avancé
- Schema.org `Article` / `BlogPosting` sur chaque article (avec `datePublished`, `dateModified`, `author`, `publisher`)
- Schema.org `FAQPage` auto-généré quand l'article contient des questions (H2/H3 en forme de question)
- Schema.org `HowTo` pour les articles tutoriels (détection via tag ou frontmatter)
- Breadcrumbs navigables avec schema `BreadcrumbList`
- Table des matières auto-générée (remark-toc + rehype-slug + rehype-autolink-headings)
- Temps de lecture estimé (remark-reading-time)
- Liens externes avec `rel="noopener noreferrer"` automatique (rehype-external-links)
- Pagination pour les listes d'articles
- Tags et catégories avec pages dédiées
- Inter-linking automatique entre articles du même cluster thématique

### Epic 3 — Intégration SE Ranking API
- Connexion à l'API SE Ranking (authentification API key)
- Script/CLI pour récupérer les keyword suggestions par niche/seed keyword
  - Volume de recherche, difficulté, CPC, tendance
  - SERP features (featured snippet, PAA, local pack)
  - Keywords des concurrents
- Stockage local des données SE Ranking (JSON/SQLite) pour éviter les appels API inutiles
- Dashboard ou page admin listant les opportunités de mots-clés
- Priorisation automatique des keywords : volume × (1 - difficulté) = score d'opportunité

### Epic 4 — Génération automatique d'articles
- Pipeline de génération d'articles basé sur les keywords prioritaires
- Structure d'article optimisée GEO :
  - Titre H1 avec le keyword principal
  - Réponse directe dans les 2 premières phrases (inverted pyramid)
  - H2/H3 qui matchent les "People Also Ask" (données SE Ranking)
  - Bullet points et listes numérotées pour les étapes
  - Bloc TL;DR en haut de l'article
  - Statistiques et données chiffrées (citabilité)
  - Conclusion avec CTA
- Frontmatter auto-rempli : title, description (max 160 chars), tags, category, keywords
- Génération de la meta description optimisée pour le CTR
- Système de revue humaine : les articles générés sont en `draft: true` par défaut
- Commande : `npm run generate-article -- --keyword "mot clé"` ou batch via liste

### Epic 5 — Stratégie social media
- Pour chaque article publié (passage de `draft: true` → `draft: false`) :
  - Génération de posts adaptés par plateforme :
    - **Twitter/X** : thread de 3-5 tweets avec hook + key points + lien
    - **LinkedIn** : post long format avec storytelling + lien
    - **Instagram** : suggestion de visuel + caption avec hashtags
  - Stockage dans un fichier `.social.json` associé à l'article
- Calendrier éditorial : fichier `content/social-calendar.json` avec les posts planifiés
- Pas de publication automatique (hors scope) — juste la génération du contenu prêt à poster
- Commande : `npm run generate-social -- --article "slug-article"`

### Epic 6 — Optimisation GEO (Generative Engine Optimization)
- Audit GEO automatisé par article :
  - Vérification de la structure (H1, H2 question-based, listes, TL;DR)
  - Vérification du schema.org (FAQPage si questions, Article obligatoire)
  - Score de citabilité (présence de stats, de définitions claires, de sources)
  - Vérification des AI crawler permissions dans robots.txt
- Rapport GEO global du site (score moyen, articles à optimiser)
- Content clusters : regroupement thématique des articles, avec page pilier par cluster
- Maillage interne automatique entre articles du même cluster

## Stack technique

- **Framework** : Astro 4.x/5.x (SSG pur, pas de SSR)
- **Content** : MDX via Content Collections + Zod schemas
- **Styling** : Tailwind CSS (utility-first, tree-shaken)
- **SEO** : `astro-seo` + `@astrojs/sitemap` + `schema-dts` pour les types JSON-LD
- **Markdown** : `rehype-slug`, `rehype-autolink-headings`, `rehype-external-links`, `remark-toc`, `remark-reading-time`
- **Données SEO** : SE Ranking API (REST, API key auth)
- **Stockage données** : fichiers JSON locaux (pas de BDD — le site est statique)
- **Génération articles** : Claude API (ou Claude CLI) appelé par des scripts Node.js
- **Hébergement** : Cloudflare Pages (CDN global, gratuit, TTFB rapide)
- **CI/CD** : GitHub Actions → build Astro → deploy Cloudflare Pages
- **Package manager** : pnpm

## Utilisateurs cibles

1. **Le propriétaire du site** (toi) — pilote la stratégie, valide les articles, publie le contenu social
2. **Les lecteurs** — arrivent via Google, Perplexity, ChatGPT Search, réseaux sociaux
3. **Les moteurs IA** — consomment le contenu structuré pour leurs réponses

## Concurrents connus

<!-- À adapter selon ta niche — exemples génériques -->
- Sites de contenu SEO automatisés : Autoblogging.ai, Koala.sh, Byword.ai
- Outils SEO + content : Surfer SEO, Clearscope, Frase.io
- Plateformes tout-en-un : HubSpot Blog, WordPress + Yoast + GPT plugins

## Contraintes

- **Performance** : Lighthouse score > 95 sur toutes les métriques (Astro SSG aide beaucoup)
- **Contenu** : les articles générés doivent passer en `draft: true` → revue humaine obligatoire avant publication
- **API SE Ranking** : respecter les rate limits, cacher les résultats localement
- **Pas de publication sociale automatique** : ORC génère le contenu social, l'humain publie
- **Pas de paywall / auth** : site public, pas de comptes utilisateurs
- **Budget API** : prévoir une variable d'env pour la clé SE Ranking, et un mode offline (utilise le cache local)

## Ce qui est hors scope

- **CMS / back-office web** : pas de panel admin web, tout se gère en CLI et fichiers
- **Publication sociale automatique** : pas de connexion aux API Twitter/LinkedIn/Instagram — juste la génération du contenu
- **E-commerce / monétisation** : pas de boutique, pas d'affiliation (peut être ajouté plus tard)
- **Multi-langue** : V1 en une seule langue (à préciser). L'i18n peut être ajouté en V2
- **SSR / pages dynamiques** : tout est statique (SSG). Pas d'API routes côté serveur sauf scripts de génération au build time
- **Analytics avancés** : pas de tracking custom. Utiliser Cloudflare Web Analytics (gratuit, privacy-friendly) ou ajouter un script simple type Plausible/Umami

## Notes pour ORC

### Configuration recommandée
```bash
# .orc/config.sh
BUILD_COMMAND="pnpm build"
TEST_COMMAND="pnpm astro check && pnpm run lint"
QUALITY_COMMAND="npx lighthouse --chrome-flags='--headless --no-sandbox' http://localhost:4321 --output=json --quiet | node -e 'const r=JSON.parse(require(\"fs\").readFileSync(\"/dev/stdin\",\"utf8\")); const s=Object.values(r.categories).map(c=>c.score*100); if(Math.min(...s)<90) process.exit(1)'"
LINT_COMMAND="pnpm run lint"
GIT_STRATEGY="pr"
GITHUB_TRACKING_ISSUE=true
EPIC_SIZE=3
PAUSE_EVERY_N_FEATURES=5
```

### Clés API nécessaires (variables d'env)
- `SE_RANKING_API_KEY` — clé API SE Ranking
- `ANTHROPIC_API_KEY` — pour la génération d'articles (si scripts de génération utilisent l'API Claude directement)

### Priorités
1. Le site doit être fonctionnel et déployable avant de connecter SE Ranking
2. La génération d'articles peut utiliser des données mock au début
3. Le social est le dernier epic — le site doit d'abord exister

### À préciser par l'humain avant de lancer
- [ ] **Niche / thématique du site** (ex: tech, finance, santé, voyage...)
- [ ] **Langue** : français ? anglais ? les deux ?
- [ ] **Nom de domaine** (même provisoire)
- [ ] **Compte SE Ranking** : as-tu déjà un abonnement avec accès API ?
- [ ] **Seed keywords** : 3-5 mots-clés de départ pour la recherche
- [ ] **Tone of voice** : expert formel ? conversationnel ? vulgarisation ?
- [ ] **Volume cible** : combien d'articles en V1 ? (10 ? 50 ? 100 ?)
