# Etat de la desserte par croisement des deux conductivites

Classe chaque cellule en quatre etats selon le croisement de `sigma_geo`
(empreinte dans le terrain) et `sigma_surf` (emprise encore degagee),
par seuillage (BRIEF section 3.4) :

## Usage

``` r
dsr_etat(sigma_geo, sigma_surf, seuil_geo = 0.5, seuil_surf = 0.5)
```

## Arguments

- sigma_geo, sigma_surf:

  `SpatRaster` mono-couche alignes, dans `[0, 1]` (sorties de
  [`dsr_conductivite()`](https://pobsteta.github.io/dessertR/reference/dsr_conductivite.md)
  et
  [`dsr_sigma_surf()`](https://pobsteta.github.io/dessertR/reference/dsr_sigma_surf.md)).

- seuil_geo, seuil_surf:

  Seuils de bascule fort/faible. Defaut 0.5.

## Value

Un `SpatRaster` categoriel `etat` (facteur a 4 niveaux, voir
description), aligne sur les entrees.

## Details

- `en_service`:

  `sigma_geo` fort et `sigma_surf` fort.

- `abandonnee`:

  `sigma_geo` fort et `sigma_surf` faible – **le signal recherche** :
  route recolonisee.

- `trouee_sans_route`:

  `sigma_geo` faible et `sigma_surf` fort – faux positif
  geomorphologique (coupe rase, ligne electrique, layon).

- `hors_route`:

  les deux faibles.

L'etat n'est reellement interpretable que **le long d'un trace retenu**
par le pathfinder ; en raster plein il sert d'inspection et de
diagnostic.

## See also

[`dsr_conductivite()`](https://pobsteta.github.io/dessertR/reference/dsr_conductivite.md),
[`dsr_sigma_surf()`](https://pobsteta.github.io/dessertR/reference/dsr_sigma_surf.md),
[`dsr_divergence()`](https://pobsteta.github.io/dessertR/reference/dsr_divergence.md).

## Examples

``` r
# \donttest{
sg <- terra::rast(nrows = 4, ncols = 4, xmin = 0, xmax = 4, ymin = 0, ymax = 4,
  crs = "EPSG:2154")
ss <- terra::rast(sg)
terra::values(sg) <- c(rep(0.9, 8), rep(0.1, 8))
terra::values(ss) <- rep(c(0.9, 0.1), 8)
e <- dsr_etat(sg, ss)
terra::levels(e)
#> [[1]]
#>   value              etat
#> 1     1        en_service
#> 2     2        abandonnee
#> 3     3 trouee_sans_route
#> 4     4        hors_route
#> 
# }
```
