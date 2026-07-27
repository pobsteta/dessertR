# Fonction d'appartenance floue

Transforme un canal continu en un degre d'appartenance dans `[0, 1]`
(BRIEF section 3.4). Trois formes : rampe croissante, rampe
decroissante, ou cloche (plateau trapezoidal). Quand les bornes ne sont
pas fournies, elles sont derivees des quantiles des donnees — pratique
pour une premiere conductivite *inspectable* avant calibration, a figer
ensuite sur un jeu de validation.

## Usage

``` r
dsr_appartenance(
  x,
  type = c("croissante", "decroissante", "cloche"),
  a = NULL,
  b = NULL,
  marge = NULL
)
```

## Arguments

- x:

  Un `SpatRaster` mono-couche, ou un vecteur numerique.

- type:

  `"croissante"`, `"decroissante"` ou `"cloche"`.

- a, b:

  Bornes de la rampe (`a` = debut, `b` = fin). Pour `"cloche"`, `a` et
  `b` delimitent le plateau et `marge` sa retombee. `NULL` -\> quantiles
  (`croissante`/`decroissante` : 0.5 et 0.95 ; `cloche` : 0.25 et 0.75).

- marge:

  Largeur des flancs de la cloche (unites de `x`). `NULL` -\>
  `(b - a) / 2`.

## Value

Un objet de meme type que `x` (raster ou vecteur), valeurs dans
`[0, 1]`.

## See also

[`dsr_conductivite()`](https://pobsteta.github.io/dessertR/reference/dsr_conductivite.md).

## Examples

``` r
v <- c(0, 25, 50, 75, 100)
dsr_appartenance(v, "croissante", a = 20, b = 80)
#> [1] 0.00000000 0.08333333 0.50000000 0.91666667 1.00000000
```
