# Mesurer la geometrie de la desserte le long d'un trace

Derive, station par station, les attributs geometriques d'une desserte a
partir des profils transversaux
([`dsr_profils()`](https://pobsteta.github.io/dessertR/reference/dsr_profils.md))
et du fil du trace (BRIEF section 3.6) : largeur roulable, devers,
presence de fosses, pente longitudinale, plus les metriques globales de
rayon de courbure et de sinuosite. Optionnellement la confiance du MNT
(densite de points sol) et le deplacement par rapport a une geometrie de
reference (BD TOPO).

## Usage

``` r
dsr_measure(
  trace,
  mnt,
  pas = 2,
  demi_largeur = 8,
  pas_travers = 0.5,
  seuil_devers = 0.12,
  prof_fosse = 0.2,
  liss_travers = 3,
  liss_long = 5,
  reference = NULL,
  confiance = NULL
)
```

## Arguments

- trace:

  Un `sf`/`sfc` `LINESTRING` (ou la sortie de
  [`dsr_pathfinder()`](https://pobsteta.github.io/dessertR/reference/dsr_pathfinder.md)).

- mnt:

  Le MNT (`SpatRaster`).

- pas, demi_largeur, pas_travers:

  Parametres des profils, voir
  [`dsr_profils()`](https://pobsteta.github.io/dessertR/reference/dsr_profils.md).

- seuil_devers:

  Pente transversale (m/m) sous laquelle la surface est consideree
  roulable. Defaut 0.12 (~7 deg).

- prof_fosse:

  Profondeur minimale (m) d'un creux lateral pour compter un fosse.
  Defaut 0.2.

- liss_travers, liss_long:

  Fenetres de lissage (en echantillons) des profils, transversale et
  longitudinale. Indispensables sur un MNT bruite sous couvert dense
  (voir Details). Defaut 3 et 5.

- reference:

  Geometrie de reference `sf`/`sfc` (p. ex. le troncon BD TOPO
  d'origine) pour le `DEPLACEMENT` ; `NULL` pour l'omettre.

- confiance:

  `SpatRaster` de confiance (p. ex. `densite_sol` de
  [`dsr_layers_pc()`](https://pobsteta.github.io/dessertR/reference/dsr_layers_pc.md))
  pour `CONFIANCE_MNT` ; `NULL` pour l'omettre.

## Value

Une liste : `stations` (`sf` `POINT` avec `LARGEUR_ROULABLE`, `DEVERS`,
`FOSSES`, `PENTE_LONG`, et si fournis `CONFIANCE_MNT`, `DEPLACEMENT`),
et `resume` (metriques globales : `LARGEUR_ROULABLE_MED`,
`PENTE_LONG_MOY`, `PENTE_LONG_MAX`, `RAYON_COURBURE_MIN`, `SINUOSITE`).

## Details

La finesse des mesures depend directement de la qualite du MNT. Sous
couvert dense, le MNT interpole a partir de points sol epars presente un
bruit vertical decimetrique a metrique (BRIEF, risque n.3) qui degrade
la largeur roulable et la pente longitudinale : d'ou le lissage
(`liss_travers`, `liss_long`) et l'interet, pour la mesure fine, de
descendre au MNT 50 cm et de recalculer un micro-MNT sur les seuls
points sol de l'emprise (a venir).

## See also

[`dsr_profils()`](https://pobsteta.github.io/dessertR/reference/dsr_profils.md),
[`dsr_pathfinder()`](https://pobsteta.github.io/dessertR/reference/dsr_pathfinder.md).

## Examples

``` r
# \donttest{
mnt <- terra::rast(nrows = 60, ncols = 60, xmin = 0, xmax = 60, ymin = 0,
  ymax = 60, resolution = 1, crs = "EPSG:2154")
terra::values(mnt) <- 100
tr <- sf::st_sf(geometry = sf::st_sfc(
  sf::st_linestring(cbind(c(5, 55), c(30, 30))), crs = 2154))
m <- dsr_measure(tr, mnt)
m$resume
#> $LARGEUR_ROULABLE_MED
#> [1] 15
#> 
#> $PENTE_LONG_MOY
#> [1] 0
#> 
#> $PENTE_LONG_MAX
#> [1] 0
#> 
#> $RAYON_COURBURE_MIN
#> [1] Inf
#> 
#> $SINUOSITE
#> [1] 1
#> 
# }
```
