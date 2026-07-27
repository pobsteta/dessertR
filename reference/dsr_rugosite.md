# Rugosite residuelle du MNT

Une route est **anormalement lisse** (BRIEF section 3.2). On retire la
tendance locale (passe-haut par soustraction d'une moyenne focale) puis
on mesure l'ecart-type residuel dans la meme fenetre : cela neutralise
l'effet de la pente et isole la micro-texture. La version issue des
points sol bruts (`rugosite_sol`, module nuage) reste meilleure car non
lissee par l'interpolation du MNT.

## Usage

``` r
dsr_rugosite(mnt, fenetre_m = 5)
```

## Arguments

- mnt:

  Le MNT (`SpatRaster` ou chemin).

- fenetre_m:

  Cote de la fenetre en metres. Defaut 5.

## Value

Un `SpatRaster` mono-couche `rugosite` (unites du MNT).

## See also

[`dsr_layers_dtm()`](https://pobsteta.github.io/dessertR/reference/dsr_layers_dtm.md).
