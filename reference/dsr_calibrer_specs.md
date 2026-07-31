# Calibrer les regles de conductivite sur un reseau de reference

Mesure, canal par canal, ce qui distingue reellement une route de son
environnement sur **vos** donnees, et en deduit un jeu de regles
utilisable tel quel par
[`dsr_conductivite()`](https://pobsteta.github.io/dessertR/reference/dsr_conductivite.md).

## Usage

``` r
dsr_calibrer_specs(
  couches,
  reference,
  pres = 3,
  absent = 20,
  auc_min = 0.55,
  poids_max = 3,
  n = 2500,
  exclure = "theta"
)
```

## Arguments

- couches:

  Un `SpatRaster` multi-bandes
  ([`dsr_layers_dtm()`](https://pobsteta.github.io/dessertR/reference/dsr_layers_dtm.md)),
  ou une **liste** de piles – une par massif.

- reference:

  Reseau de reference (`sf`/`sfc` de lignes), ou une liste de meme
  longueur que `couches`.

- pres:

  Distance (m) en deca de laquelle une cellule compte comme « sur route
  ». Defaut 3.

- absent:

  Distance (m) au-dela de laquelle une cellule compte comme « hors route
  ». Defaut 20. La bande intermediaire est ignoree : c'est le bord de
  plateforme, ni route ni environnement.

- auc_min:

  AUC minimale pour qu'un canal entre dans les regles. Defaut 0.55. En
  dessous, le canal n'apporte pas de quoi payer le bruit qu'il ajoute.

- poids_max:

  Poids attribue au canal le plus discriminant ; les autres sont
  proportionnels a leur ecart au hasard. Defaut 3.

- n:

  Taille des echantillons compares. Defaut 2500.

- exclure:

  Canaux ignores. Defaut `"theta"`, qui est une orientation et non une
  intensite.

## Value

Une liste : `specs`, directement utilisable comme argument `specs` de
[`dsr_conductivite()`](https://pobsteta.github.io/dessertR/reference/dsr_conductivite.md),
et `diagnostic`, un `data.frame` (`canal`, `auc`, `sens`, `retenu`,
`poids`) trie par pouvoir discriminant decroissant. Avec plusieurs
massifs, `auc` est la mediane et une colonne `stable` indique si le sens
concorde partout.

## Details

**Pourquoi cette fonction existe.** Les regles par defaut
([`dsr_specs_geomorpho()`](https://pobsteta.github.io/dessertR/reference/dsr_specs_geomorpho.md))
reposent sur une intuition physique : une route est lisse, elle occupe
un creux, elle est lineaire. Mesuree sur deux massifs Lidar HD,
l'intuition sur la rugosite est **fausse et inversee** – une piste
empierree a ornieres est plus rugueuse, a 50 cm, qu'un versant forestier
localement plan. Le canal le plus discriminant des deux jeux (AUC 0,78
et 0,68) etait donc utilise a l'envers, et la conductivite qui en
resultait tombait au niveau du hasard (0,51 et 0,54). Signes corriges,
elle remonte a 0,77 et 0,72.

**Ce que la fonction mesure.** Pour chaque canal, l'aire sous la courbe
ROC entre les cellules proches du reseau de reference (`pres`) et celles
qui en sont eloignees (`absent`). L'AUC est rendue **orientee** : 0,5
signifie aucun pouvoir discriminant, et `sens` dit si le canal marque la
route par le haut ou par le bas. Les canaux multi-echelles sont
regroupes par base et moyennes, comme le fait
[`dsr_conductivite()`](https://pobsteta.github.io/dessertR/reference/dsr_conductivite.md)
– mesurer autrement calibrerait autre chose que ce qui sera utilise.

**Plusieurs massifs valent mieux qu'un, et pas seulement pour la
precision.** En passant une liste, un canal n'est retenu que si son sens
est **le meme partout**. Ce n'est pas un raffinement : sur les deux
massifs de validation, la `pente` marque les routes par le bas dans l'un
et par le haut dans l'autre. Calibree sur un seul, elle entrait dans les
regles ; calibree sur les deux, elle en est ecartee. Un canal dont le
signe depend du relief n'a rien a faire dans une regle.

**Ce que la reference peut et ne peut pas etre.** Sa POSITION doit faire
autorite – la BD TOPO convient, sa precision planimetrique etant
metrique. Sa largeur, non : elle n'entre pas dans le calcul. Un reseau
approximatif (trace GPS, numerisation sur fond satellite) deplacerait
les echantillons « presence » hors de l'emprise reelle et calibrerait du
bruit.

## See also

[`dsr_conductivite()`](https://pobsteta.github.io/dessertR/reference/dsr_conductivite.md),
[`dsr_specs_geomorpho()`](https://pobsteta.github.io/dessertR/reference/dsr_specs_geomorpho.md),
[`dsr_layers_dtm()`](https://pobsteta.github.io/dessertR/reference/dsr_layers_dtm.md).

## Examples

``` r
# \donttest{
mnt <- terra::rast(nrows = 60, ncols = 60, xmin = 0, xmax = 60, ymin = 0,
  ymax = 60, crs = "EPSG:2154")
terra::values(mnt) <- runif(3600)
couches <- dsr_layers_dtm(mnt, res = 1)
axe <- sf::st_sfc(sf::st_linestring(cbind(c(5, 55), c(30, 30))), crs = 2154)
cal <- dsr_calibrer_specs(couches, axe)
cal$diagnostic
#>          canal       auc sens stable retenu poids
#> 1   vesselness 0.6678266    1   TRUE   TRUE     3
#> 2     rugosite 0.5542620   -1   TRUE   TRUE     1
#> 3        pente 0.5189014    1   TRUE  FALSE     0
#> 4 openness_neg 0.5109477    1   TRUE  FALSE     0
#> 5 openness_pos 0.5036254    1   TRUE  FALSE     0
#> 6          svf 0.5026314    1   TRUE  FALSE     0
#> 7         slrm 0.5003655    1   TRUE  FALSE     0
# }
```
