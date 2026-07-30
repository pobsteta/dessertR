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
  max_pas = 500
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
