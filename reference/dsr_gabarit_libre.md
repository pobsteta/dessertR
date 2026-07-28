# Gabarit libre sous branches le long d'un trace

Hauteur libre au-dessus de la chaussee – la hauteur de la plus basse
branche ou du plus bas echo de sursol qui surplombe l'emprise – calculee
directement sur le nuage classe (BRIEF section 3.7). Critere reel pour
un grumier (~4,5 m), totalement absent des bases existantes. Une valeur
elevee (jusqu'au `plafond`) signifie un ciel degage au-dessus de la
chaussee.

## Usage

``` r
dsr_gabarit_libre(
  trace,
  dalle,
  demi_largeur_route = 1.5,
  seuil_bas = 0.3,
  plafond = 8,
  res = 1,
  pas = 2
)
```

## Arguments

- trace:

  Un `sf`/`sfc` `LINESTRING` (ou la sortie de
  [`dsr_pathfinder()`](https://pobsteta.github.io/dessertR/reference/dsr_pathfinder.md)).

- dalle:

  Chemin d'un fichier LAZ/LAS/COPC classe.

- demi_largeur_route:

  Demi-largeur de chaussee consideree, en metres. Defaut 1.5.

- seuil_bas:

  Hauteur au sol minimale (m) d'un echo pour compter comme obstacle
  (ignore le sol et le bruit). Defaut 0.3.

- plafond:

  Hauteur (m) au-dela de laquelle on considere le ciel degage (absence
  d'obstacle). Defaut 8.

- res:

  Resolution de la grille de sursol, en metres. Defaut 1.

- pas:

  Espacement des stations le long du trace, en metres. Defaut 2.

## Value

Un `sf` `POINT` par station, avec `chainage` et `GABARIT_LIBRE` (m).

## See also

[`dsr_trafficability()`](https://pobsteta.github.io/dessertR/reference/dsr_trafficability.md).
