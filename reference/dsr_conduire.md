# Suivre une route depuis une amorce (agent conducteur)

Vectorise une route en la **parcourant** : depuis une amorce orientee,
l'agent avance par pas, regarde en eventail devant lui, et part vers la
direction la moins couteuse. Reimplementation terra/sf de l'algorithme
de vecnet (Roussel *et al.* 2023) adossee au noyau Rust du paquet.

## Usage

``` r
dsr_conduire(
  sigma,
  amorce,
  reseau = NULL,
  portee = 100,
  fov = 160,
  conductivite_min = 0.6,
  seuil = 0.1,
  tampon = 10,
  avance = 0.8,
  trouee_max = 2.5,
  max_pas = 500,
  franchissabilite = NULL,
  franchissabilite_min = 0.45
)
```

## Arguments

- sigma:

  Conductivite (`SpatRaster` mono-couche), typiquement la sortie de
  [`dsr_conductivite()`](https://pobsteta.github.io/dessertR/reference/dsr_conductivite.md)
  ou une carte de probabilite. `NA` admis.

- amorce:

  Amorce orientee : un `LINESTRING` `sf`/`sfc`. Son dernier point est la
  position de depart, sa direction donne le cap initial.

- reseau:

  Reseau deja vectorise (`sf`/`sfc`), rendu infranchissable : l'agent
  s'arrete en le rejoignant. `NULL` (defaut) pour aucun.

- portee:

  Distance de visee, en metres. Defaut 100.

- fov:

  Champ de vision total, en degres. Defaut 160.

- conductivite_min:

  Conductivite en deca de laquelle une direction n'est plus consideree
  comme roulable. Fixe le cout maximal admissible
  (`portee / conductivite_min`). Defaut 0.6.

- seuil:

  Plancher de conductivite applique a la fenetre de travail. Defaut 0.1.

- tampon:

  Demi-largeur (m) de neutralisation du reseau et de la trace deja
  parcourue. Defaut 10.

- avance:

  Fraction de la portee effectivement parcourue a chaque pas. Defaut 0.8
  : avancer de la portee entiere ferait manquer les embranchements
  situes juste avant le point vise.

- trouee_max:

  Longueur maximale de trouee toleree, en multiples de la portee. Defaut
  2.5.

- max_pas:

  Nombre maximal de pas. Defaut 500.

- franchissabilite:

  `SpatRaster` **aligne sur `sigma`** disant ou l'emprise est encore
  degagee – typiquement
  [`dsr_sigma_surf()`](https://pobsteta.github.io/dessertR/reference/dsr_sigma_surf.md).
  Les cellules sous `franchissabilite_min` deviennent maximalement
  resistantes sans devenir infranchissables. `NULL` (defaut) pour ne
  poser aucune contrainte. Voir les details.

- franchissabilite_min:

  Seuil sous lequel une cellule est tenue pour refermee. Defaut 0.45.
  Sans effet si `franchissabilite` est `NULL`. Ce que ce chiffre fait
  reellement est explique dans les details – ce n'est pas tout a fait ce
  qu'il annonce, et la valeur est mesuree, pas choisie.

## Value

Une liste : `route` (`sfc` `LINESTRING`, l'amorce comprise), `amorces`
(`sfc` des embranchements rencontres, ou `NULL`), `n_pas`, `arret`
(motif d'arret) et `n_troncons`, le nombre de pas reellement parcourus,
amorce exclue. **`n_troncons == 0` signifie que l'agent n'a pas pu
avancer** : `route` n'est alors que l'amorce rendue telle quelle, et non
une route decouverte.

## Details

**Ce que cette fonction fait et que
[`dsr_pathfinder()`](https://pobsteta.github.io/dessertR/reference/dsr_pathfinder.md)
ne fait pas.** Le pathfinder relie deux points connus. L'agent ne sait
pas ou il va : il suit la conductivite. Il en decoule deux proprietes
que le squelette et le pathfinder n'ont pas :

- **robustesse aux trouees** – une coupure de conductivite est franchie
  si la route reprend derriere, parce que le cout admissible est module
  par la *profondeur* du creux dans le profil angulaire et non par sa
  seule valeur ;

- **decouverte des embranchements** – les directions ecartees a chaque
  pas sont autant d'amorces, rendues dans `amorces`, a repasser a la
  fonction pour explorer le reseau de proche en proche.

**Arret.** L'agent s'arrete quand il rejoint `reseau`, quand aucune
direction n'est admissible, quand il sort de l'emprise, quand il a roule
trop longtemps au-dessus du cout maximal (`trouee_max` fois la portee),
ou apres `max_pas` pas.

**Suivre une carte et etre arrete par une autre.** `sigma` dit ou aller,
`franchissabilite` dit ou l'on ne passe plus. C'est la separation posee
par le BRIEF section 3.4 – `sigma_geo` porte l'empreinte, `sigma_surf`
porte l'etat present – appliquee au conducteur : il suit l'empreinte et
se fait freiner par l'etat, au lieu de suivre un melange des deux.

Cette separation a ete introduite apres une mesure.
[`dsr_indice_detection()`](https://pobsteta.github.io/dessertR/reference/dsr_indice_detection.md)
ponderait le canal de surface a 2 ; ramene a sa valeur mesuree (0,5), la
carte s'ameliore nettement (AUC 0,698 -\> 0,738) et le vectoriseur par
squelette avec elle, mais l'agent, lui, se degrade – il divague, son
ecart median a la reference passant de 3,3 a 5,2 m. L'explication tient
en une phrase : l'ancien poids ecrasait la carte partout ou le
sous-etage est ferme, ce qui **retenait** l'agent. Ce garde-fou etait
reel mais accidentel, et il se payait d'une carte de detection degradee.
Passer `franchissabilite` le retablit la ou il doit etre, sans rien
devoir a la ponderation de la detection.

**Ce que `franchissabilite_min` fait vraiment.** Pas ce que son nom
laisse croire. Avec les regles par defaut de
[`dsr_specs_surface()`](https://pobsteta.github.io/dessertR/reference/dsr_specs_surface.md),
les bornes d'appartenance sont laissees a `NULL`, donc derivees des
quantiles : `a` est la **mediane** du canal et `b` son 95e centile
([`dsr_appartenance()`](https://pobsteta.github.io/dessertR/reference/dsr_appartenance.md)).
Il en decoule que la moitie des cellules ont, par construction,
`mu(taux_penetration) = 0` – ramene au plancher `sigma_min` – et
`mu(densite_sousetage) = 1`. Leur fusion vaut alors
`exp((2 * log(1) + log(0.05)) / 3) = 0.368`, et `sigma_surf` presente un
mode massif a cette valeur : 50 % des cellules sur wsfi, 34 % sur ltcp.

Le seuil se place au-dessus de ce mode. Il ne mesure donc pas une
fermeture de sous-etage : il selectionne les cellules dont le **taux de
penetration depasse sa propre mediane**. C'est un critere de RANG
deguise en valeur absolue, et physiquement il dit « ne pas circuler la
ou le lidar ne voit pas le sol ».

Cette lecture a une consequence pratique heureuse : le seuil se
transporte d'un massif a l'autre bien mieux qu'un seuil absolu ne le
devrait. Le taux de penetration brut vaut 0,04 sur wsfi et 0,31 sur ltcp
– un facteur 7 – et la meme valeur convient aux deux, parce que la
normalisation par quantiles absorbe l'ecart en amont. Elle a aussi une
consequence genante : fixer `a` et `b` explicitement dans `specs`
deplace le mode et **invalide le defaut**.

**Pourquoi 0,45 et non 0,4.** Le balayage
(`dev/07_calibrer_franchissabilite.R`, 9 seuils sur deux massifs) donne
des F1 **indiscernables sur toute la plage** – 0,355 a 0,367 une fois
lisses, sur un profil chaotique : un petit deplacement du seuil change
quelles amorces aboutissent, et la cascade se propage par le reseau
accumule. Prendre l'argmax d'un tel profil serait du surajustement.

C'est l'ECART A LA REFERENCE qui tranche :

|          |                   |                   |            |
|----------|-------------------|-------------------|------------|
| seuil    | ecart median wsfi | ecart median ltcp | moyenne    |
| 0,375    | 2,27 m            | **13,37 m**       | 7,82 m     |
| 0,40     | 2,57 m            | **12,91 m**       | 7,74 m     |
| **0,45** | 2,62 m            | **4,06 m**        | **3,34 m** |
| 0,50     | 2,24 m            | 6,93 m            | 4,58 m     |
| 0,55     | 2,86 m            | 4,58 m            | 3,72 m     |

Sur ltcp l'ecart vaut 4 a 7 m partout **sauf entre 0,375 et 0,40**, ou
il explose a 13 m. L'anomalie est cette zone etroite – juste au-dessus
du mode, la ou le plancher ecrase le contraste sur les deux tiers de la
carte et laisse l'agent divaguer – et l'ancien defaut s'y trouvait. 0,45
en sort au premier cran, sans rien couter sur wsfi (2,62 contre 2,57 m).

Une version anterieure de ce paragraphe concluait « ce qui compte est le
cote du mode, au-dessus l'ecart tombe a 2-3 m sur les deux massifs ».
C'etait mesure sur un agent qui perdait alors 19 amorces sur 26 sur ltcp
(corrige depuis) ; la regle ne survit pas a la correction.

## See also

[`dsr_pathfinder()`](https://pobsteta.github.io/dessertR/reference/dsr_pathfinder.md),
[`dsr_vectoriser()`](https://pobsteta.github.io/dessertR/reference/dsr_vectoriser.md),
[`dsr_reseau()`](https://pobsteta.github.io/dessertR/reference/dsr_reseau.md).

## Examples

``` r
# Carte synthetique : une route rectiligne de conductivite 1 sur fond a 0.1.
r <- terra::rast(nrows = 100, ncols = 100, xmin = 0, xmax = 200,
  ymin = 0, ymax = 200, crs = "EPSG:2154")
terra::values(r) <- 0.1
xy <- terra::xyFromCell(r, seq_len(terra::ncell(r)))
r[abs(xy[, 2] - 100) < 4] <- 1
amorce <- sf::st_sfc(sf::st_linestring(cbind(c(10, 25), c(100, 100))),
  crs = "EPSG:2154")
ans <- dsr_conduire(r, amorce, portee = 40)
ans$arret
#> [1] "hors_emprise"
```
