# Profils transversaux le long d'un trace

Preleve, tous les `pas` metres le long d'un trace, un profil d'altitude
**perpendiculaire** au trace, echantillonne sur le MNT (BRIEF section
3.6). C'est la matiere premiere de
[`dsr_measure()`](https://pobsteta.github.io/dessertR/reference/dsr_measure.md).

## Usage

``` r
dsr_profils(
  trace,
  mnt,
  pas = 2,
  demi_largeur = 8,
  pas_travers = 0.5,
  methode = c("bilinear", "simple")
)
```

## Arguments

- trace:

  Un `sf`/`sfc` `LINESTRING` (ou l'element `trace` de
  [`dsr_pathfinder()`](https://pobsteta.github.io/dessertR/reference/dsr_pathfinder.md)).

- mnt:

  Le MNT (`SpatRaster`), de preference a 50 cm.

- pas:

  Espacement des profils le long du trace, en metres. Defaut 2.

- demi_largeur:

  Demi-largeur des profils, en metres. Defaut 8.

- pas_travers:

  Pas d'echantillonnage transversal, en metres. Defaut 0.5.

- methode:

  Interpolation de l'extraction : `"bilinear"` (defaut, pour un MNT
  continu) ou `"simple"` (plus proche voisin, pour une grille a trous
  comme la hauteur de sursol).

## Value

Une liste : `stations` (`sf` `POINT` des centres, avec `chainage`),
`offsets` (positions transversales, m), `z` (matrice
`stations x offsets` des altitudes), `normales` (matrice `stations x 2`,
vecteur transversal unitaire par station).

## See also

[`dsr_measure()`](https://pobsteta.github.io/dessertR/reference/dsr_measure.md).
