# Reseau routier OpenStreetMap sur une emprise

Telecharge les lineaires `highway` d'OpenStreetMap, **dalle par dalle**,
et les rend projetes et decoupes sur l'emprise.

## Usage

``` r
dsr_osm(
  emprise,
  valeurs = c("track", "path", "unclassified", "service", "residential", "tertiary"),
  cote = DSR_TAILLE_DALLE,
  pause = 1
)
```

## Arguments

- emprise:

  `sf`/`sfc`/`SpatVector`/`SpatRaster`, ou une sortie de
  [`dsr_catalog()`](https://pobsteta.github.io/dessertR/reference/dsr_catalog.md).
  Son emprise est decoupee en dalles.

- valeurs:

  Valeurs de la cle `highway` retenues ; `NULL` pour toutes. Defaut :
  les classes forestieres utiles.

- cote:

  Cote des tuiles de requete, en metres. Defaut 1000 (grille Lidar HD).

- pause:

  Secondes d'attente entre deux dalles, pour menager les quotas. Defaut
  1.

## Value

Un `sf` `LINESTRING` dans le CRS de `emprise`, colonnes `highway` et
`osm_id`, sans doublon (une voie a cheval sur deux dalles n'est rendue
qu'une fois). `NULL` si OSM ne porte rien sur l'emprise.

## Details

**Pourquoi decouper par dalle.** Une requete unique sur un massif entier
depasse les quotas d'Overpass et echoue en bloc ; decoupee sur la grille
kilometrique du Lidar HD, elle devient une suite de requetes courtes,
chacune relancable, et le decoupage coincide avec celui du reste du
traitement
([`dsr_catalog()`](https://pobsteta.github.io/dessertR/reference/dsr_catalog.md)).
Une dalle qui echoue n'emporte pas les autres.

**Ce qu'OSM peut servir ici, et ce qu'il ne peut pas.** La question de
[`dsr_detecter()`](https://pobsteta.github.io/dessertR/reference/dsr_detecter.md)
– « quelle desserte la reference ignore-t-elle ? » – n'a pas de verite
terrain par construction. Les `track` et `path` d'OSM en couvrent une
partie et fournissent donc un **rappel** mesurable. En revanche OSM
n'est **ni** un metre etalon de largeur (aucun attribut fiable), **ni**
une verite de position : une part du lineaire forestier y est tracee sur
trace GPS agregee (`source=strava heatmap`) ou sur fond satellite. Meme
regle que pour toute sortie d'un autre algorithme : comparaison, jamais
calibrage.

## See also

[`dsr_detecter()`](https://pobsteta.github.io/dessertR/reference/dsr_detecter.md),
[`dsr_vectoriser()`](https://pobsteta.github.io/dessertR/reference/dsr_vectoriser.md).

## Examples

``` r
if (FALSE) { # \dontrun{
emp <- sf::st_as_sfc(sf::st_bbox(mnt))
osm <- dsr_osm(emp)
} # }
```
