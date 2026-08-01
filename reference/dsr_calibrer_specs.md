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
  exclure = "theta",
  bornes = TRUE
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

- bornes:

  Produire aussi les bornes d'appartenance `a` et `b`, en unites du
  canal. Defaut `TRUE`. Voir « Bornes absolues » ci-dessous ; `FALSE`
  rend des regles sans bornes, donc **relatives a l'emprise**.

## Value

Une liste de quatre elements :

- `specs`, directement utilisable comme argument `specs` de
  [`dsr_conductivite()`](https://pobsteta.github.io/dessertR/reference/dsr_conductivite.md)
  ;

- `diagnostic`, un `data.frame` (`canal`, `auc`, `sens`, `stable`,
  `retenu`, `poids`, `a`, `b`) trie par pouvoir discriminant
  decroissant. Avec plusieurs massifs, `auc` est la mediane et `stable`
  indique si le sens concorde partout ;

- `par_massif`, la mesure brute avant agregation (`canal`, `massif`,
  `auc`, `sens`) – c'est la qu'on lit *comment* un canal s'inverse, la
  ou `diagnostic` se contente de dire qu'il le fait ;

- `terrain`, les descripteurs de relief de chaque massif (`pente_med`,
  `pente_p90`, `rugosite_med`, `relief_iqr`). Voir « Terrain »
  ci-dessous.

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

**Bornes absolues, et pourquoi elles comptent.** La fonction rend aussi
les bornes `a` et `b` de chaque rampe, en unites du canal
(`bornes = TRUE`). Ce n'est pas un agrement : sans elles,
[`dsr_appartenance()`](https://pobsteta.github.io/dessertR/reference/dsr_appartenance.md)
derive ses bornes des quantiles de la donnee qu'on lui passe, et **la
sortie depend alors de l'etendue analysee**. Mesure sur le bloc wsfi,
une fenetre de 0,25 km2 rend 116 m de desserte detectee analysee seule,
et **0 m** analysee au sein de 4 km2 : le `seuil` de
[`dsr_detecter()`](https://pobsteta.github.io/dessertR/reference/dsr_detecter.md)
n'est pas une quantite absolue mais un rang dans la population fournie.
Deux sites d'etendues differentes ne sont pas comparables, et le regime
`corridor` change le bareme.

La convention est de faire aller la rampe du typique de l'ENVIRONNEMENT
(`mu = 0`) au franchement ROUTIER (`mu = 1`) :

|                |               |               |
|----------------|---------------|---------------|
| sens           | `a`           | `b`           |
| `croissante`   | q50(absence)  | q75(presence) |
| `decroissante` | q25(presence) | q50(absence)  |

Une borne, contrairement au sens et a l'AUC, est dans l'unite du canal
et ne se transporte pas forcement d'un massif a l'autre – le taux de
penetration brut varie d'un facteur 7 entre les deux massifs de
validation. Avec plusieurs massifs les bornes sont donc medianes, et
**calibrer sur les massifs qu'on va effectivement traiter reste la bonne
pratique**.

Cette correction ne suffit pas a elle seule a rendre une pile
independante de l'emprise : `vesselness` est rescalee **en amont** des
fonctions d'appartenance et demande son propre ancrage
([`dsr_c_vessel()`](https://pobsteta.github.io/dessertR/reference/dsr_c_vessel.md)).

**Terrain : instrumenter avant de stratifier.** Certains canaux
discriminent bien sur chaque massif mais dans des sens **opposes**. Sur
les deux massifs de validation, `pente` marque les routes par le bas en
montagne (une route suit le moindre pendage) et par le haut en plaine
(plateforme bombee, fosses), avec la meme AUC de 0,61 des deux cotes ;
`slrm` fait de meme. Le test `stable` les ecarte – prudence justifiee
tant qu'on ne sait pas a quoi rattacher l'inversion, mais qui perd de
l'information reelle.

L'hypothese naturelle est que ces signes sont stables **a l'interieur
d'une classe de relief**. Elle n'est pas tranchable avec deux massifs :
il en faudrait au moins deux par classe, sans quoi on calibrerait une
classification sur un seul echantillon – exactement l'erreur que cette
fonction existe pour eviter.

D'ou `terrain` et `par_massif`, qui **instrumentent sans stratifier** :
chaque calibration rend son relief a cote de ses signes, et la question
devient decidable quand les massifs s'accumuleront. Les descripteurs
sont plusieurs a dessein – rien ne dit d'avance si c'est la pente, la
rugosite ou l'amplitude du relief local qui predit les inversions, et
c'est aux donnees de le dire.

**Une regularite a falsifier.** Sur les deux massifs disponibles, les
canaux qui s'inversent sont exactement ceux qui situent la route dans la
forme GENERALE du paysage, et ceux qui restent stables decrivent la
route ELLE-MEME :

|  |  |  |
|----|----|----|
| canal | plaine (pente med. 2,2 deg) | montagne (22,3 deg) |
| `pente` | +1 | **-1** |
| `slrm` | +1 | **-1** |
| `rugosite` (texture) | +1 | +1 |
| `openness_neg` / `openness_pos` / `svf` (forme du voisinage) | -1 | -1 |
| `vesselness` (linearite) | +1 | +1 |

L'explication tiendrait en une phrase : en montagne une route suit le
moindre pendage, elle est donc **moins** pentue que son environnement ;
en plaine il n'y a pas de pendage a suivre, et ce qui la marque est sa
forme construite – bombement, fosses – donc **plus** pentue qu'un
terrain plat. Les autres canaux decrivent la route et non sa place dans
le paysage, ce qui expliquerait leur stabilite.

Ce n'est **pas une loi** : deux massifs ne l'etablissent pas. C'est une
prediction, et elle est falsifiable – un troisieme massif dont `pente`
s'inverserait sans changement de classe de relief la refuterait. Elle
vaut surtout parce qu'elle reduit le probleme : si elle tient, seuls
`pente` et `slrm` demandent un conditionnement au terrain.

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
#>          canal       auc sens stable retenu poids         a         b
#> 1   vesselness 0.7104864    1   TRUE   TRUE     3 0.0000000 0.3107341
#> 2     rugosite 0.5682943   -1   TRUE   TRUE     1 0.2522887 0.2828020
#> 3        pente 0.5408892   -1   TRUE  FALSE     0        NA        NA
#> 4 openness_neg 0.5091054    1   TRUE  FALSE     0        NA        NA
#> 5         slrm 0.5075298   -1   TRUE  FALSE     0        NA        NA
#> 6 openness_pos 0.5059567   -1   TRUE  FALSE     0        NA        NA
#> 7          svf 0.5055245   -1   TRUE  FALSE     0        NA        NA
# }
```
