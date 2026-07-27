# Ingerer des canaux morphometriques externes et les aligner

Reprend des canaux geomorphologiques deja calcules ailleurs –
typiquement l'openness et le SVF produits par un outil valide plutot que
recalcules ici – et les depose sur la grille de reference de la dalle
(BRIEF sections 3.1 et 6). Chaque canal est reprojete puis
reechantillonne sur la grille ; un canal deja cale dessus est simplement
recadre, sans reechantillonnage.

## Usage

``` r
dsr_canaux_externes(
  couches,
  reference,
  methode = c("bilinear", "near", "cubic", "average"),
  methodes = NULL,
  refuser_composite = TRUE
)
```

## Arguments

- couches:

  Liste **nommee** : nom de canal -\> chemin de GeoTIFF ou `SpatRaster`.
  Les noms attendus figurent dans DSR_CANAUX_DTM ; les variantes
  multi-echelles se suffixent par le rayon (`openness_neg_5`). Un nom
  hors vocabulaire est accepte mais signale (garde-fou anti-faute).

- reference:

  Grille de reference : un `SpatRaster` gabarit (typiquement la sortie
  de
  [`dsr_grille_reference()`](https://pobsteta.github.io/dessertR/reference/dsr_grille_reference.md))
  ou un chemin.

- methode:

  Methode de reechantillonnage par defaut : `"bilinear"` (continu,
  defaut), `"near"` (categoriel ou angulaire), `"cubic"`, `"average"`.

- methodes:

  Liste nommee optionnelle pour surcharger la methode canal par
  canal, p. ex. `list(theta = "near")` pour une orientation angulaire.

- refuser_composite:

  Si `TRUE` (defaut), rejette un raster 8 bits (0-255) : c'est la
  signature d'un composite RVT etire (CVAT / VAT), un produit de
  visualisation incompatible avec les fonctions d'appartenance de la
  conductivite. Mettre `FALSE` seulement pour un fond de carte assume.

## Value

Un `SpatRaster` multi-bandes aligne sur `reference`, une bande par
canal, nommee comme les entrees de `couches`.

## Details

Source recommandee : `foretaccess::micro_relief()`, dont le noyau Rust
est un portage valide de la Relief Visualization Toolbox et qui rend
directement les bandes `svf`, `openness_pos` et `openness_neg` (memes
noms que le vocabulaire interne). Alimente-le avec la grille de
reference 1 m de la dalle et l'alignement est exact.

## See also

[`dsr_grille_reference()`](https://pobsteta.github.io/dessertR/reference/dsr_grille_reference.md).

## Examples

``` r
# \donttest{
mnt <- terra::rast(
  xmin = 0, xmax = 20, ymin = 0, ymax = 20, resolution = 0.5,
  crs = "EPSG:2154"
)
terra::values(mnt) <- runif(terra::ncell(mnt))
grille <- dsr_grille_reference(mnt, res = 1)

# Un canal openness deja calcule (ici bidon) a 0.5 m, aligne sur la grille 1 m
opns <- terra::rast(mnt)
terra::values(opns) <- runif(terra::ncell(opns), 60, 90)
pile <- dsr_canaux_externes(list(openness_neg = opns), reference = grille)
names(pile)
#> [1] "openness_neg"
# }
```
