# Repositionner un reseau de reference sous contrainte

Recale chaque troncon d'un reseau de reference (BD TOPO) sur le MNT
lidar via le pathfinder, **sans jamais s'ecarter de plus de
`deviation_max` metres de l'axe d'origine** (couloir dur) et en etant
attire vers cet axe (contrainte douce). La reference fait autorite : la
validation a montre qu'un repositionnement libre sur `sigma_geo`
accroche des lineaires paralleles (fosses, traces fossiles, risque n.1
du BRIEF) et degrade la mesure. La contrainte l'empeche.

## Usage

``` r
dsr_repositionner(
  reseau,
  sigma_geo,
  theta = NULL,
  poids = NULL,
  deviation_max = 10,
  attraction = 1,
  lambda = 4,
  mu = 2,
  sigma_min = 0.05
)
```

## Arguments

- reseau:

  Un `sf` de `LINESTRING` (reseau de reference, p. ex. BD TOPO).

- sigma_geo:

  Conductivite geomorphologique
  ([`dsr_conductivite()`](https://pobsteta.github.io/dessertR/reference/dsr_conductivite.md)),
  `SpatRaster`.

- theta, poids:

  Orientation et force d'anisotropie
  ([`dsr_layers_dtm()`](https://pobsteta.github.io/dessertR/reference/dsr_layers_dtm.md)),
  alignes sur `sigma_geo` ; `NULL` -\> isotrope.

- deviation_max:

  Ecart lateral maximal a l'axe d'origine, en metres. Defaut 10.

- attraction:

  Force du rappel vers l'axe (0 = aucun ; plus grand = plus colle a
  l'axe). Defaut 1.

- lambda, mu, sigma_min:

  Parametres du pathfinder
  ([`dsr_pathfinder()`](https://pobsteta.github.io/dessertR/reference/dsr_pathfinder.md)).

## Value

Le `sf` d'entree, geometries recalees, avec les colonnes
`DEPLACEMENT_MAX` et `DEPLACEMENT_MOY` (ecart a l'axe d'origine, m) et
`RECALE` (logique : `FALSE` = repli sur l'origine).

## Details

La **totalite du reseau de reference est conservee** : si le pathfinder
echoue sur un troncon, on garde sa geometrie d'origine. Le recalage ne
peut donc que deplacer un axe dans son couloir, jamais en supprimer.

## See also

[`dsr_pathfinder()`](https://pobsteta.github.io/dessertR/reference/dsr_pathfinder.md),
[`dsr_conductivite()`](https://pobsteta.github.io/dessertR/reference/dsr_conductivite.md),
[`dsr_measure()`](https://pobsteta.github.io/dessertR/reference/dsr_measure.md).
