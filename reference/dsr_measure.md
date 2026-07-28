# Mesurer la geometrie de la desserte le long d'un trace

Derive, station par station, les attributs geometriques d'une desserte a
partir des profils transversaux
([`dsr_profils()`](https://pobsteta.github.io/dessertR/reference/dsr_profils.md))
et du fil du trace (BRIEF section 3.6) : largeur roulable, devers,
presence de fosses, pente longitudinale, plus les metriques globales de
rayon de courbure et de sinuosite. Optionnellement la confiance du MNT
(densite de points sol) et le deplacement par rapport a une geometrie de
reference (BD TOPO).

## Usage

``` r
dsr_measure(
  trace,
  mnt,
  pas = 2,
  demi_largeur = 8,
  pas_travers = 0.5,
  seuil_devers = 0.15,
  prof_fosse = 0.2,
  liss_travers = 3,
  liss_long = 5,
  methode_largeur = c("planeite", "gradient"),
  tol_planeite = 0.1,
  base_courbure = 30,
  reference = NULL,
  confiance = NULL
)
```

## Arguments

- trace:

  Un `sf`/`sfc` `LINESTRING` (ou la sortie de
  [`dsr_pathfinder()`](https://pobsteta.github.io/dessertR/reference/dsr_pathfinder.md)).

- mnt:

  Le MNT (`SpatRaster`).

- pas, demi_largeur, pas_travers:

  Parametres des profils, voir
  [`dsr_profils()`](https://pobsteta.github.io/dessertR/reference/dsr_profils.md).

- seuil_devers:

  Pente transversale (m/m) sous laquelle la surface est consideree
  roulable. Defaut 0.15 (~8,5 deg) ; sur route de montagne a fort
  devers, monter a 0.20. Methode `"gradient"` seulement.

- prof_fosse:

  Profondeur minimale (m) d'un creux lateral pour compter un fosse.
  Defaut 0.2.

- liss_travers, liss_long:

  Fenetres de lissage (en echantillons) des profils, transversale et
  longitudinale. Indispensables sur un MNT bruite sous couvert dense
  (voir Details). Defaut 3 et 5.

- methode_largeur:

  `"planeite"` (defaut) ou `"gradient"` (methode historique) ; voir
  Details.

- tol_planeite:

  Ecart maximal (m) au plan de chaussee ajuste, methode `"planeite"`
  seulement. Defaut 0.10.

- base_courbure:

  Longueur (m) de la fenetre d'ajustement du cercle de courbure. `0`
  pour revenir au cercle circonscrit a trois stations consecutives.
  Defaut 30.

- reference:

  Geometrie de reference `sf`/`sfc` (p. ex. le troncon BD TOPO
  d'origine) pour le `DEPLACEMENT` ; `NULL` pour l'omettre.

- confiance:

  `SpatRaster` de confiance (p. ex. `densite_sol` de
  [`dsr_layers_pc()`](https://pobsteta.github.io/dessertR/reference/dsr_layers_pc.md))
  pour `CONFIANCE_MNT` ; `NULL` pour l'omettre.

## Value

Une liste : `stations` (`sf` `POINT` avec `LARGEUR_ROULABLE`, `DEVERS`,
`FOSSES`, `PENTE_LONG`, et si fournis `CONFIANCE_MNT`, `DEPLACEMENT`),
et `resume` (metriques globales : `LARGEUR_ROULABLE_MED`,
`PENTE_LONG_MOY`, `PENTE_LONG_MAX`, `RAYON_COURBURE_MIN`,
`RAYON_COURBURE_P05`, `SINUOSITE`).

## Details

La finesse des mesures depend directement de la qualite du MNT. Sous
couvert dense, le MNT interpole a partir de points sol epars presente un
bruit vertical decimetrique a metrique (BRIEF, risque n.3) qui degrade
la largeur roulable et la pente longitudinale, d'ou le lissage
(`liss_travers`, `liss_long`).

**Ce que coute la grille.** La largeur est mesuree sur le MNT, donc sur
un produit **interpole** : le bord de plateforme est une ligne de
rupture, et c'est precisement ce qu'une interpolation arrondit. Sur une
plateforme de synthese de 4,00 m, selon la grille dont on part :

|                                   |                 |
|-----------------------------------|-----------------|
| source                            | largeur mesuree |
| MNT 50 cm (cellules moyennees)    | 3,56 m (-0,44)  |
| micro-MNT 25 cm, memes points     | 3,66 m (-0,34)  |
| points sol bruts, sans grille     | 3,78 m (-0,22)  |
| profil parfait, echantillonne fin | 3,99 m (-0,01)  |

Deux enseignements. D'abord l'estimateur lui-meme est **juste** : sur
une donnee propre il retrouve la largeur au centimetre. Ensuite le
micro-MNT sur points sol bruts evoque au BRIEF section 3.6 vaut environ
**0,2 m** — reel, mais plus modeste que ce que le brief laissait
attendre.

Fait contre-intuitif : le biais ne bouge pas quand la densite de points
sol passe de 20 a 1 point par metre carre. Pour *cette* mesure, ce n'est
pas le nombre de points qui coute, c'est le fait de passer par une
grille. (La simulation moyenne les points par cellule ; un MNT IGN
interpole par TIN preserve mieux les lignes de rupture, l'ecart reel est
donc probablement plus faible.)

**Largeur roulable.** `"planeite"` ajuste le plan de chaussee sur une
fenetre centrale puis s'ecarte tant que la surface reste a moins de
`tol_planeite` de ce plan, avec interpolation du bord entre
echantillons. `"gradient"` retient la plage ou la pente transversale
reste sous `seuil_devers`. Sur un profil de synthese de largeur connue
(4,00 m, bombement 3 %) :

|              |                |                |
|--------------|----------------|----------------|
| bruit du MNT | `"gradient"`   | `"planeite"`   |
| aucun        | 3,00 m (-1,00) | 3,92 m (-0,08) |
| 5 cm         | 2,56 m (-1,44) | 3,72 m (-0,28) |
| 10 cm        | 0,93 m (-3,08) | 3,66 m (-0,34) |

Surtout, le biais de `"gradient"` depend du pas transversal (-3,74 m a
`pas_travers = 0.1`, 0,00 m a 1 m) autant que de `seuil_devers` : un
seuil cale sur un jeu ne vaut que pour ce pas et ce niveau de bruit.
C'est pourquoi `"planeite"` est le defaut — voir
[`dsr_calibrer_largeur()`](https://pobsteta.github.io/dessertR/reference/dsr_calibrer_largeur.md)
pour la suite.

`tol_planeite` a une lecture physique : il doit **depasser la fleche du
bombement**, soit `bombement x largeur / 2`. Une route de 6 m bombee a 3
% (fleche 9 cm) passe avec le defaut de 10 cm ; la meme bombee a 6 %
(fleche 18 cm) est tronquee a 4,4 m et demande 0,20. Le bombement,
symetrique, n'est pas un devers : `DEVERS` ne retient que l'inclinaison
d'ensemble, celle qui compte pour la stabilite d'un chargement.

**Rayon de courbure.** Il est ajuste par un cercle des moindres carres
sur une fenetre de `base_courbure` metres, et non sur trois stations
consecutives. La quantification du trace vectorise (un sommet par
cellule) rend le cercle circonscrit inutilisable : sur un arc de rayon
vrai 60 m, quantifie au metre puis lisse, la mediane des rayons vaut

|                                       |         |
|---------------------------------------|---------|
| estimateur                            | mediane |
| 3 stations consecutives               | 16,6 m  |
| cercle des moindres carres, base 20 m | 49,0 m  |
| cercle des moindres carres, base 30 m | 56,5 m  |
| cercle des moindres carres, base 50 m | 60,0 m  |

La base par defaut (30 m) est aussi l'ordre de grandeur d'un ensemble
routier grumier : c'est l'echelle a laquelle la courbure contraint
reellement le passage. `RAYON_COURBURE_P05` est le quantile 5 % ; le
preferer au minimum, qui reste sensible a une station aberrante.

## See also

[`dsr_profils()`](https://pobsteta.github.io/dessertR/reference/dsr_profils.md),
[`dsr_pathfinder()`](https://pobsteta.github.io/dessertR/reference/dsr_pathfinder.md),
[`dsr_calibrer_largeur()`](https://pobsteta.github.io/dessertR/reference/dsr_calibrer_largeur.md).

## Examples

``` r
# \donttest{
mnt <- terra::rast(nrows = 60, ncols = 60, xmin = 0, xmax = 60, ymin = 0,
  ymax = 60, resolution = 1, crs = "EPSG:2154")
terra::values(mnt) <- 100
tr <- sf::st_sf(geometry = sf::st_sfc(
  sf::st_linestring(cbind(c(5, 55), c(30, 30))), crs = 2154))
m <- dsr_measure(tr, mnt)
m$resume
#> $LARGEUR_ROULABLE_MED
#> [1] 16
#> 
#> $PENTE_LONG_MOY
#> [1] 0
#> 
#> $PENTE_LONG_MAX
#> [1] 0
#> 
#> $RAYON_COURBURE_MIN
#> [1] Inf
#> 
#> $RAYON_COURBURE_P05
#> [1] Inf
#> 
#> $SINUOSITE
#> [1] 1
#> 
# }
```
