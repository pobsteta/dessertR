# Construire un reseau topologiquement coherent

Assemble une collection de traces en un reseau valide (BRIEF section
3.8) : collage des noeuds partages, deduplication des paralleles, puis
analyse de connectivite (composantes, rattachement au reseau public).
Une desserte qui ne rejoint pas le reseau public est signalee comme
artefact probable.

## Usage

``` r
dsr_reseau(
  traces,
  tol_noeud = 1,
  largeur_dedupe = 3,
  reseau_public = NULL,
  tol_public = 5
)
```

## Arguments

- traces:

  Un `sf` de `LINESTRING` (traces corriges).

- tol_noeud:

  Distance de collage des extremites, en metres. Defaut 1.

- largeur_dedupe:

  Ecart de deduplication des paralleles, en metres. Defaut 3.

- reseau_public:

  `sf`/`sfc` du reseau public (routes ouvertes) pour la verification de
  connectivite ; `NULL` pour l'omettre.

- tol_public:

  Distance (m) de rattachement d'un noeud au reseau public. Defaut 5.

## Value

Une liste : `aretes` (`sf` des traces retenus, avec `composant` et, si
`reseau_public`, `connecte_public`), `noeuds` (`sf` `POINT` des noeuds),
`graphe` (objet `igraph`), et `resume` (nombre d'aretes, de noeuds, de
composantes, longueur non rattachee au public).

## See also

[`dsr_coller_noeuds()`](https://pobsteta.github.io/dessertR/reference/dsr_coller_noeuds.md),
[`dsr_dedupe_paralleles()`](https://pobsteta.github.io/dessertR/reference/dsr_dedupe_paralleles.md),
[`dsr_sfnetwork()`](https://pobsteta.github.io/dessertR/reference/dsr_sfnetwork.md).
