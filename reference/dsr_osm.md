# Reseau routier OpenStreetMap sur une emprise

Telecharge les lineaires `highway` d'OpenStreetMap sur l'emprise, en
**une requete**, et les rend projetes et decoupes.

## Usage

``` r
dsr_osm(
  emprise,
  valeurs = c("track", "path", "unclassified", "service", "residential", "tertiary"),
  cote = NULL,
  pause = 1,
  timeout = 90,
  cache_dir = NULL,
  politique_cache = "reacquerir"
)
```

## Arguments

- emprise:

  `sf`/`sfc`/`SpatVector`/`SpatRaster`, ou une sortie de
  [`dsr_catalog()`](https://pobsteta.github.io/dessertR/reference/dsr_catalog.md).
  Sa bbox est interrogee d'un seul tenant.

- valeurs:

  Valeurs de la cle `highway` retenues ; `NULL` pour toutes. Defaut :
  les classes forestieres utiles.

- cote:

  Plancher de bissection, en metres : une sous-emprise plus petite n'est
  plus decoupee. Defaut `NULL` (aucun plancher). **N'est plus un pas de
  grille** : le decoupage ne suit plus la grille kilometrique Lidar HD.

- pause:

  Secondes d'attente entre deux sous-emprises, en mode bissection
  seulement. Sans effet dans le cas nominal, qui ne fait qu'une requete.

- timeout:

  Plafond par requete, en secondes. Passe a libcurl **et** a Overpass.

- cache_dir:

  Repertoire de cache. `NULL` (defaut) : aucun cache, chaque appel
  retape le reseau.

- politique_cache:

  Que faire d'un cache produit avec **d'autres parametres** ?
  `"reacquerir"` (defaut), `"avertir"`, `"echouer"` ou `"ignorer"`.

## Value

Un `sf` `LINESTRING` dans le CRS de `emprise`, colonnes `highway` et
`osm_id`, sans doublon. `NULL` si OSM ne porte rien sur l'emprise.

## Details

**Une requete, pas cent.** Overpass plafonne le **nombre de requetes**,
pas la surface : le cout suit la densite de voirie, et une requete
`highway` sur une bbox de massif reste modeste. L'ancien tuilage
kilometrique transformait une emprise de 10 x 10 km en 100 requetes –
soit precisement ce qui declenche le `429` que tout le reste du code
s'efforce d'eviter – et retelechargeait tous les noeuds de chaque voie a
chaque dalle traversee. Le decoupage n'intervient plus qu'en **repli** :
sur un refus de volume ou de duree, l'emprise est bissectee en quadrants
(profondeur maximale 3, soit 64 sous-emprises au pire). Jamais sur un
`429`, qui appelle une rotation d'instance et non un decoupage.

**Trois issues, jamais confondues.** Des donnees, un vide legitime, ou
un refus. Un refus ne devient jamais une couche vide : une instance
bridee rend un XML **bien forme** de quelques centaines d'octets, sans
code HTTP d'erreur, avec un element `<remark>`. Lu naivement, cela dit «
rien ici » – l'erreur qui a fausse une journee de validation.

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

**Datez vos resultats.** OSM change tous les jours. Avec `cache_dir`, un
sidecar `osm.gpkg.provenance.json` enregistre la date de requete (UTC),
les instances servies, la requete Overpass exacte et le lineaire obtenu
: sans cela, deux executions a un mois d'ecart different **sans aucune
trace**, ce qui rend inciteable toute mesure de rappel.

## Performance

Mesures du 2026-08-13, instance `overpass-api.de`, cache froid :

|            |          |          |          |        |
|------------|----------|----------|----------|--------|
| emprise    | troncons | lineaire | requetes | duree  |
| 3 x 3 km   | 199      | 59,5 km  | 1        | 0,8 s  |
| 10 x 10 km | 2 116    | 562,7 km | 1        | 16,0 s |

La seconde valait 100 requetes et 100 s de `pause` avec le tuilage
kilometrique, avant meme de compter les `429` qu'elle provoquait.
Relecture depuis `cache_dir` : 0,08 s.

## Duree bornee

Aucun appel ne peut depasser `timeout * 4 * 3` secondes par emprise
interrogee – quatre instances, trois essais chacune. Le decoupage
multiplie ce plafond par le nombre de sous-emprises. Baisser `timeout`
resserre la borne. C'est la propriete que `osmdata` ne peut pas offrir :
son backoff de 60 s n'a pas de plafond.

## See also

[`dsr_detecter()`](https://pobsteta.github.io/dessertR/reference/dsr_detecter.md),
[`dsr_vectoriser()`](https://pobsteta.github.io/dessertR/reference/dsr_vectoriser.md),
[`dsr_classer()`](https://pobsteta.github.io/dessertR/reference/dsr_classer.md).

## Examples

``` r
if (FALSE) { # \dontrun{
emp <- sf::st_as_sfc(sf::st_bbox(mnt))
osm <- dsr_osm(emp, cache_dir = "cache/osm")
} # }
```
