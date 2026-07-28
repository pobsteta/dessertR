# Indice de vegetation normalise (NDVI) depuis une ortho infrarouge

Calcule le NDVI `(PIR - Rouge) / (PIR + Rouge)` a partir d'une ortho
infrarouge couleur – la BD ORTHO IRC de l'IGN, dont les bandes sont dans
l'ordre PIR, Rouge, Vert. Contrairement a un modele de hauteur de
canopee predit, le NDVI est calcule sur les pixels **natifs** de l'ortho
(20 cm) : c'est la seule grandeur optique a l'echelle d'une chaussee
forestiere.

## Usage

``` r
dsr_ndvi(irc, bandes = c(pir = 1, rouge = 2))
```

## Arguments

- irc:

  `SpatRaster` multi-bandes de l'ortho IRC.

- bandes:

  Indices ou noms des bandes proche infrarouge et rouge. Defaut
  `c(pir = 1, rouge = 2)`, l'ordre de la BD ORTHO IRC.

## Value

Un `SpatRaster` a une bande nommee `ndvi`, valeurs dans `[-1, 1]`.

## Details

Le rapport est sans dimension : aucune normalisation radiometrique n'est
requise, des comptes numeriques 8 bits conviennent. Les pixels ou
`PIR + Rouge` s'annule sont mis a `NA`.

Limites, a garder en tete avant d'en tirer une largeur : sous couvert
ferme la chaussee est a l'ombre et son NDVI remonte ; une piste enherbee
ne se distingue pas du sous-bois ; le millesime de l'ortho n'est pas
celui du lidar.

## See also

[`dsr_largeur_ndvi()`](https://pobsteta.github.io/dessertR/reference/dsr_largeur_ndvi.md),
[`dsr_canaux_externes()`](https://pobsteta.github.io/dessertR/reference/dsr_canaux_externes.md)
pour verser le NDVI dans la pile de canaux.

## Examples

``` r
irc <- terra::rast(xmin = 0, xmax = 10, ymin = 0, ymax = 10,
  resolution = 1, nlyrs = 3, crs = "EPSG:2154")
terra::values(irc) <- cbind(rep(200, 100), rep(50, 100), rep(60, 100))
terra::global(dsr_ndvi(irc), "mean")
#>      mean
#> ndvi  0.6
```
