# Modele de relief local simplifie (SLRM / MSTP)

Le SLRM (Simple Local Relief Model) fait ressortir une route comme
**terrasse locale plane**, robuste a la largeur (BRIEF section 3.2).
C'est le residu signe du MNT apres retrait d'une surface lissee :
`MNT - moyenne_focale(MNT)`. L'apport multi-echelle (plusieurs fenetres)
est le vrai gain sur ALSroads.

## Usage

``` r
dsr_slrm(mnt, fenetres_m = c(5, 15))
```

## Arguments

- mnt:

  Le MNT (`SpatRaster` ou chemin).

- fenetres_m:

  Vecteur de cotes de fenetre en metres. Defaut `c(5, 15)`.

## Value

Un `SpatRaster`, une couche `slrm_<fenetre>` par echelle.

## See also

[`dsr_layers_dtm()`](https://pobsteta.github.io/dessertR/reference/dsr_layers_dtm.md).
