# Predire une conductivite apprise

Applique un modele ajuste par
[`dsr_apprendre_conductivite()`](https://pobsteta.github.io/dessertR/reference/dsr_apprendre_conductivite.md)
a une pile de canaux ou a une table. Sur un `SpatRaster`, la sortie est
un raster de probabilite alignee sur l'entree ; les cellules dont un
canal manque restent `NA`.

## Usage

``` r
# S3 method for class 'dsr_modele_conductivite'
predict(object, newdata, ...)

# S3 method for class 'dsr_modele_conductivite'
print(x, ...)
```

## Arguments

- object:

  Un objet `dsr_modele_conductivite`.

- newdata:

  `SpatRaster` portant au moins les canaux du modele, ou `data.frame` de
  memes colonnes.

- ...:

  Ignore.

- x:

  Un objet `dsr_modele_conductivite`.

## Value

Un `SpatRaster` mono-couche `p_route`, ou un vecteur numerique selon la
classe de `newdata`.

## See also

[`dsr_apprendre_conductivite()`](https://pobsteta.github.io/dessertR/reference/dsr_apprendre_conductivite.md),
[`dsr_conductivite()`](https://pobsteta.github.io/dessertR/reference/dsr_conductivite.md).
