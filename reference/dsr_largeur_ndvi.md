# Largeur de la plage minerale par NDVI le long d'un trace

Mesure, station par station, la largeur de la plage continue centree sur
l'axe ou le NDVI reste **sous** un seuil – la signature du mineral, donc
de la chaussee nue. Le seuil est determine automatiquement par la
methode d'Otsu (maximisation de la variance interclasse) sur l'ensemble
des profils, ce qui evite d'imposer une valeur qui depend du millesime,
de la saison et de l'exposition.

## Usage

``` r
dsr_largeur_ndvi(
  trace,
  ndvi,
  seuil = "otsu",
  pas = 2,
  demi_largeur = 8,
  pas_travers = 0.2,
  liss_travers = 5
)
```

## Arguments

- trace:

  Un `sf`/`sfc` `LINESTRING` (ou l'element `trace` de
  [`dsr_pathfinder()`](https://pobsteta.github.io/dessertR/reference/dsr_pathfinder.md)).

- ndvi:

  `SpatRaster` du NDVI, typiquement la sortie de
  [`dsr_ndvi()`](https://pobsteta.github.io/dessertR/reference/dsr_ndvi.md).

- seuil:

  `"otsu"` (defaut) pour un seuil determine automatiquement, ou une
  valeur numerique imposee.

- pas:

  Espacement des stations le long du trace, en metres. Defaut 2.

- demi_largeur:

  Demi-largeur des profils, en metres. Defaut 8.

- pas_travers:

  Pas d'echantillonnage transversal, en metres. Defaut 0.2, la
  resolution native de la BD ORTHO.

- liss_travers:

  Fenetre de lissage transversal (nombre d'echantillons, impair). Defaut
  5 : le NDVI pixel a pixel est bruite (ombres portees, ornieres,
  gravillons).

## Value

Un `sf` `POINT` par station, avec `chainage`, `LARGEUR_NDVI` (m, `NA` si
la plage sort du profil), `NDVI_AXE` (valeur sur l'axe) et `TRONQUE`.
L'attribut `"seuil"` porte le seuil retenu.

## Details

**Mesure independante, pas mesure de reference.** `LARGEUR_NDVI` est un
second avis, calcule sur une source qui ne partage aucune erreur avec le
MNT ; c'est ce qui la rend utile. Elle ne remplace pas
`LARGEUR_ROULABLE` : une piste enherbee ou ombragee ne donne aucun
contraste spectral, et l'ortho n'a pas le millesime du lidar. La
comparer a `LARGEUR_ROULABLE` renseigne sur l'etat de surface (mineral
degage contre enherbement), pas sur l'exactitude de la mesure MNT.

Le seuil est **global** et non par station : sur une trentaine
d'echantillons transversaux, Otsu est instable. Il est renvoye dans
l'attribut `"seuil"` du resultat.

## See also

[`dsr_ndvi()`](https://pobsteta.github.io/dessertR/reference/dsr_ndvi.md),
[`dsr_measure()`](https://pobsteta.github.io/dessertR/reference/dsr_measure.md).

## Examples

``` r
# \donttest{
r <- terra::rast(xmin = 0, xmax = 60, ymin = 0, ymax = 60,
  resolution = 0.5, crs = "EPSG:2154")
xy <- terra::xyFromCell(r, seq_len(terra::ncell(r)))
terra::values(r) <- ifelse(abs(xy[, 2] - 30) <= 2, 0.05, 0.75)
tr <- sf::st_sf(geometry = sf::st_sfc(
  sf::st_linestring(cbind(c(5, 55), c(30, 30))), crs = 2154))
l <- dsr_largeur_ndvi(tr, r, pas_travers = 0.5)
stats::median(l$LARGEUR_NDVI, na.rm = TRUE)
#> [1] 4.009766
# }
```
