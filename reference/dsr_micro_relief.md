# Canaux de micro-relief openness et SVF d'un MNT

Derive le **sky-view factor** et l'**openness** (positive et negative)
d'un modele de terrain – les canaux morphometriques qui portent la
signature d'une desserte (depression de plateforme, talus amont et aval,
fosses lateraux) bien mieux que le MNT brut (BRIEF section 3.2).
Enveloppe SIG du noyau Rust `rvt_svf_opns` (portage valide de la Relief
Visualization Toolbox, Apache 2.0, vendorise depuis le paquet
`foretaccess`) : le balayage d'horizon vit dans le crate, `terra` ne
fait que recoller les canaux sur la grille du MNT.

## Usage

``` r
dsr_micro_relief(
  mnt,
  radius_m = 10,
  radius_min_m = NULL,
  num_directions = 16L,
  canaux = c("svf", "openness_pos", "openness_neg")
)
```

## Arguments

- mnt:

  Le MNT, `SpatRaster` mono-couche (cellules supposees carrees ; la
  premiere couche est prise si plusieurs) ou chemin de GeoTIFF.

- radius_m:

  Rayon de recherche d'horizon maximal, en **metres**. Defaut 10.

- radius_min_m:

  Rayon minimal en metres (reduction du bruit). Defaut `NULL` -\> un
  pixel.

- num_directions:

  Nombre de directions azimutales balayees. Defaut 16.

- canaux:

  Canaux a renvoyer, parmi `"svf"`, `"openness_pos"`, `"openness_neg"`.
  Defaut : les trois.

## Value

Un `SpatRaster` aligne sur `mnt`, une couche par canal demande (`svf` en
0..1, `openness_pos`/`openness_neg` en degres), `NA` la ou le MNT est
`NA`. Les noms coincident avec le vocabulaire de
[`dsr_canaux_externes()`](https://pobsteta.github.io/dessertR/reference/dsr_canaux_externes.md).

## Details

L'**openness negative** est l'openness du MNT **inverse** (elle allume
les talus amont et les fosses), calculee ici en passant le noyau sur
`-z`.

Le rayon de recherche est donne en **metres** et converti en pixels
selon la resolution du MNT. Alimenter un MNT a **1 m ou plus grossier**
(voir
[`dsr_grille_reference()`](https://pobsteta.github.io/dessertR/reference/dsr_grille_reference.md))
: a 50 cm le balayage coute ~4 fois plus et le petit rayon ne capte que
du bruit d'interpolation. Pour la pile multi-echelle du BRIEF, appeler
la fonction a plusieurs rayons (2 / 5 / 10 m).

## See also

[`dsr_grille_reference()`](https://pobsteta.github.io/dessertR/reference/dsr_grille_reference.md),
[`dsr_canaux_externes()`](https://pobsteta.github.io/dessertR/reference/dsr_canaux_externes.md).

## Examples

``` r
mnt <- terra::rast(
  nrows = 30, ncols = 30, xmin = 0, xmax = 30, ymin = 0, ymax = 30,
  crs = "EPSG:2154"
)
terra::values(mnt) <- 100 # terrain plat -> svf = 1, openness = 90
mr <- dsr_micro_relief(mnt, radius_m = 5)
names(mr)
#> [1] "svf"          "openness_pos" "openness_neg"
```
