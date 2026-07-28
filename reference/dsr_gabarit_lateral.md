# Largeur de la trouee de canopee et surplomb le long d'un trace

Mesure, station par station, la largeur de la **trouee de canopee**
centree sur l'axe – la plage continue ou la hauteur de vegetation reste
sous `seuil_ouvert` – et, si la largeur de chaussee est fournie, le
**surplomb** : de combien les houppiers empietent sur l'emprise
roulable. C'est le critere lateral absent de
[`dsr_trafficability()`](https://pobsteta.github.io/dessertR/reference/dsr_trafficability.md),
et la reponse a la question operationnelle *ou elaguer*.

## Usage

``` r
dsr_gabarit_lateral(
  trace,
  chm,
  largeur = NULL,
  pas = 2,
  demi_largeur = 8,
  pas_travers = 0.5,
  seuil_ouvert = 2,
  liss_travers = 1
)
```

## Arguments

- trace:

  Un `sf`/`sfc` `LINESTRING` (ou l'element `trace` de
  [`dsr_pathfinder()`](https://pobsteta.github.io/dessertR/reference/dsr_pathfinder.md)).

- chm:

  `SpatRaster` de hauteur de vegetation (CHM predit depuis l'ortho, ou
  MNH lidar). Une seule bande utilisee.

- largeur:

  Largeur roulable par station, pour le surplomb : un vecteur numerique
  (longueur 1 ou nombre de stations), ou le `sf` `stations` de
  [`dsr_measure()`](https://pobsteta.github.io/dessertR/reference/dsr_measure.md)
  dont la colonne `LARGEUR_ROULABLE` est reprise. `NULL` (defaut) :
  `SURPLOMB` et `HAUT_SURPLOMB` valent `NA`. Le decoupage en stations
  etant deterministe, un
  [`dsr_measure()`](https://pobsteta.github.io/dessertR/reference/dsr_measure.md)
  et un `dsr_gabarit_lateral()` appeles sur le meme trace avec le meme
  `pas` donnent le meme nombre de stations.

- pas:

  Espacement des stations le long du trace, en metres. Defaut 2.

- demi_largeur:

  Demi-largeur des profils, en metres. Defaut 8. Une trouee plus large
  que `2 * demi_largeur` est tronquee (colonne `TRONQUE`).

- pas_travers:

  Pas d'echantillonnage transversal, en metres. Defaut 0.5.

- seuil_ouvert:

  Hauteur (m) sous laquelle une cellule compte comme degagee. Defaut 2 :
  en deca on est dans l'herbe et le semis, qui ne genent pas un grumier
  lateralement.

- liss_travers:

  Fenetre de lissage transversal (nombre d'echantillons, impair). Defaut
  1 (aucun lissage) : contrairement au MNT, un CHM porte de vraies
  ruptures qu'il ne faut pas arrondir.

## Value

Un `sf` `POINT` par station, avec `chainage`, `LARGEUR_DEGAGEE` (m),
`DEGAGE_G` et `DEGAGE_D` (distance de l'axe au bord de trouee, m, par
cote), `TRONQUE` (la trouee sort du profil), et si `largeur` est fourni
`SURPLOMB` (m d'emprise recouverte, 0 si aucun) et `HAUT_SURPLOMB`
(hauteur du plus bas houppier empietant, lue au plus proche voisin pour
rester une valeur de cellule reelle ; `Inf` si aucun).

## Details

**Ce n'est pas une mesure de largeur de chaussee.** La trouee et la
chaussee divergent de facon variable selon le peuplement riverain ; voir
l'en-tete du fichier. `LARGEUR_DEGAGEE` ne doit jamais alimenter
[`dsr_calibrer_largeur()`](https://pobsteta.github.io/dessertR/reference/dsr_calibrer_largeur.md).

**Le surplomb est detecte, sa hauteur est surestimee.** Un modele de
hauteur de canopee donne le **sommet** du houppier, pas le dessous de la
branche. Une branche basse d'un arbre de 25 m est vue a 25 m :
`HAUT_SURPLOMB` est donc un indicateur **permissif**, qui attrape a coup
sur la regeneration et les rejets de bord de route (le cas dominant) et
rate les branches basses des grands arbres. Seul
[`dsr_gabarit_libre()`](https://pobsteta.github.io/dessertR/reference/dsr_gabarit_libre.md),
sur le nuage classe, donne le dessous de branche.

**Attention a la maille reelle.** Un CHM predit par les modeles
Open-Canopy a une maille native de l'ordre de 1,5 m ; sureechantillonne
a 0,20 m il *declare* 0,20 m mais ne porte que l'information de sa
maille d'origine. Le paquet ne peut pas detecter ce cas – la fonction ne
signale que la resolution declaree. Pour une mesure au decimetre, il n'y
a que le MNT.

## See also

[`dsr_gabarit_libre()`](https://pobsteta.github.io/dessertR/reference/dsr_gabarit_libre.md)
pour le gabarit vertical sur le nuage,
[`dsr_trafficability()`](https://pobsteta.github.io/dessertR/reference/dsr_trafficability.md)
qui consomme `SURPLOMB` et `HAUT_SURPLOMB`.

## Examples

``` r
# \donttest{
chm <- terra::rast(xmin = 0, xmax = 60, ymin = 0, ymax = 60,
  resolution = 1, crs = "EPSG:2154")
terra::values(chm) <- 20
# Un couloir degage de 6 m de large autour de y = 30
xy <- terra::xyFromCell(chm, seq_len(terra::ncell(chm)))
chm[abs(xy[, 2] - 30) <= 3] <- 0
tr <- sf::st_sf(geometry = sf::st_sfc(
  sf::st_linestring(cbind(c(5, 55), c(30, 30))), crs = 2154))
g <- dsr_gabarit_lateral(tr, chm, largeur = 4)
summary(g$LARGEUR_DEGAGEE)
#>    Min. 1st Qu.  Median    Mean 3rd Qu.    Max. 
#>     5.2     5.2     5.2     5.2     5.2     5.2 
# }
```
