# Trace de moindre cout anisotrope entre deux points

Recherche le chemin optimal sur la conductivite geomorphologique
`sigma_geo`, avec un **cout anisotrope** (les deplacements en travers de
l'orientation locale `theta` sont penalises : une route a une direction)
et une **penalite de courbure** (BRIEF section 3.5). Le voisinage 16
supprime le biais de metrication du Dijkstra 8-connexe (traces en
escalier). Le pathfinder tourne sur `sigma_geo` (robuste a la
vegetation) ; l'etat de la desserte se lit ensuite le long du trace
([`dsr_etat()`](https://pobsteta.github.io/dessertR/reference/dsr_etat.md)).

## Usage

``` r
dsr_pathfinder(
  sigma_geo,
  depart,
  arrivee,
  theta = NULL,
  poids = NULL,
  k = 16L,
  lambda = 4,
  mu = 2,
  sigma_min = 0.05,
  cout_cumule = FALSE
)
```

## Arguments

- sigma_geo:

  Conductivite geomorphologique, `SpatRaster` mono-couche (sortie de
  [`dsr_conductivite()`](https://pobsteta.github.io/dessertR/reference/dsr_conductivite.md))
  ; `NA` = infranchissable.

- depart, arrivee:

  Extremites : un `POINT` `sf`/`sfc`, un couple numerique `c(x, y)`, ou
  un indice de cellule entier.

- theta:

  Orientation locale des lineaires en degres (`vesselness` / `theta` de
  [`dsr_layers_dtm()`](https://pobsteta.github.io/dessertR/reference/dsr_layers_dtm.md)),
  aligne sur `sigma_geo` ; `NULL` -\> isotrope.

- poids:

  Force de l'anisotropie par cellule (p. ex. `vesselness`, 0..1), aligne
  sur `sigma_geo` ; `NULL` -\> 0 (isotrope).

- k:

  Nombre de caps discrets de l'etat d'orientation. Defaut 16.

- lambda:

  Poids de l'anisotropie (penalite de traverse). Defaut 4.

- mu:

  Poids de la courbure (penalite de changement de cap). Defaut 2.

- sigma_min:

  Plancher de conductivite (evite les resistances infinies). Defaut
  0.05.

- cout_cumule:

  Renvoyer aussi le champ de cout minimal a la source (utile pour
  l'incertitude laterale). Defaut `FALSE`.

## Value

Une liste : `trace` (un `sf` `LINESTRING`, du depart a l'arrivee, avec
la colonne `cout`), `cout` (le cout total) et `cout_cumule` (un
`SpatRaster` ou `NULL`).

## See also

[`dsr_conductivite()`](https://pobsteta.github.io/dessertR/reference/dsr_conductivite.md),
[`dsr_layers_dtm()`](https://pobsteta.github.io/dessertR/reference/dsr_layers_dtm.md),
[`dsr_etat()`](https://pobsteta.github.io/dessertR/reference/dsr_etat.md).

## Examples

``` r
# \donttest{
sg <- terra::rast(nrows = 40, ncols = 40, xmin = 0, xmax = 40, ymin = 0,
  ymax = 40, crs = "EPSG:2154")
terra::values(sg) <- 0.1
sg[20, ] <- 0.95 # un couloir conducteur horizontal
tr <- dsr_pathfinder(sg, c(1, 20.5), c(39, 20.5))
tr$cout
#> [1] 40
# }
```
