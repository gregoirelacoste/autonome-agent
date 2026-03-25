PHASE RECHERCHE INITIALE

Avant de coder quoi que ce soit, fais une veille complète.

### 1. Benchmark concurrentiel

Recherche et analyse les concurrents directs et indirects.
Pour chacun, documente :
- URL et pricing
- Features principales
- Forces et faiblesses
- Ce que les utilisateurs en disent (avis, forums)
- Ce qui manque / opportunités

Utilise les concurrents listés dans BRIEF.md comme point de départ,
puis en découvre d'autres via WebSearch.

### 2. Attentes utilisateurs

Recherche sur Reddit, forums spécialisés, ProductHunt :
- Quelles features sont les plus demandées ?
- Qu'est-ce qui frustre dans les outils existants ?
- Quels cas d'usage ne sont pas couverts ?

### 3. Tendances tech & UX

- APIs publiques exploitables pour le domaine
- Patterns UX actuels dans le domaine
- Technologies adaptées au projet

### 4. Veille réglementaire (si applicable)

- Contraintes légales du domaine
- Changements récents ou à venir

### Output attendu

Pour chaque section :
1. Crée un fichier daté dans research/<catégorie>/YYYY-MM-DD-<sujet>.md
2. Mets à jour research/<catégorie>/SYNTHESIS.md
3. Mets à jour research/INDEX.md (max 50 lignes, insights clés uniquement)

Chaque insight doit se terminer par :
**Confiance :** `high` | `medium` | `low`
**Sources :** [nombre de sources qui confirment cet insight]
**Impact produit :** ce qu'on devrait en faire concrètement.

### 5. Cross-validation

Pour chaque insight majeur (qui influence la stratégie produit) :
- Confirme avec au moins 2 sources indépendantes
- Si une seule source → marque `confidence: low`
- Si les sources se contredisent → note les deux versions
- Ne base JAMAIS une décision stratégique sur un insight `low confidence` seul

IMPORTANT : cite toujours l'URL source exacte.
IMPORTANT : les insights `low confidence` ne doivent PAS être utilisés seuls pour prioriser des features.
