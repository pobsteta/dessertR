# Classer les lineaires detectes et proposer un balisage OSM

Attribue a chaque lineaire une classe forestiere – desserte,
cloisonnement d'exploitation, layon parcellaire – a partir de ce que le
paquet a mesure, et propose le balisage OpenStreetMap correspondant. La
sortie est une **proposition auditable**, pas un jeu pret a televerser.

## Usage

``` r
dsr_classer(
  aretes,
  stations = NULL,
  id = "troncon",
  ndvi = NULL,
  reference = NULL,
  parcellaire = NULL,
  panneaux = NULL,
  tol_parcelle = 5,
  part_parcelle = 0.6,
  tol_panneau = 15,
  champ_acces = "access",
  champ_source = "source",
  part_minerale = 0.5,
  sous_type_parcelle = c("section", "border"),
  ...
)
```

## Arguments

- aretes:

  `sf` de `LINESTRING` : la sortie `aretes` de
  [`dsr_reseau()`](https://pobsteta.github.io/dessertR/reference/dsr_reseau.md),
  ou tout reseau classe. Les colonnes `connecte_public`
  ([`dsr_reseau()`](https://pobsteta.github.io/dessertR/reference/dsr_reseau.md))
  et `PEIGNE`
  ([`dsr_peignes()`](https://pobsteta.github.io/dessertR/reference/dsr_peignes.md))
  sont utilisees si presentes.

- stations:

  `sf`/`data.frame` des stations
  ([`dsr_measure()`](https://pobsteta.github.io/dessertR/reference/dsr_measure.md))
  portant la colonne `id` ; `NULL` pour se passer des criteres de
  profil.

- id:

  Colonne identifiant le troncon. Defaut `"troncon"`.

- ndvi:

  `SpatRaster` de NDVI
  ([`dsr_ndvi()`](https://pobsteta.github.io/dessertR/reference/dsr_ndvi.md))
  ; `NULL` pour ne pas juger la nature de la surface.

- reference:

  `sf`/`sfc` du reseau de reference (BD TOPO, couche interne) : ce qu'il
  porte est une desserte. `NULL` pour ne pas s'y rapporter – tous les
  lineaires sont alors juges sur leur seule structure.

- parcellaire:

  `sf`/`sfc` des limites de parcelles ; `NULL` pour ne pas tester la
  coincidence. Le paquet n'acquiert pas cette couche : elle vient de
  l'amont, qui seul sait ce qu'elle porte – d'ou `sous_type_parcelle`.

- panneaux:

  `sf` `POINT`/`LINESTRING` attestant une restriction d'acces, portant
  `champ_acces` et, si possible, `champ_source` ; `NULL` (defaut) pour
  n'emettre aucun tag d'acces.

- tol_parcelle, part_parcelle:

  Distance (m) et part de longueur au-dela de laquelle une trace est
  reputee suivre le parcellaire. Defauts 5 et 0.6.

- tol_panneau:

  Distance (m) de rattachement d'un panneau a une trace. Defaut 15.

- champ_acces, champ_source:

  Colonnes de `panneaux`. Defauts `"access"` et `"source"`.

- part_minerale:

  Part de la largeur mesuree que la plage minerale doit couvrir pour que
  la surface soit dite minerale. Defaut 0.5.

- sous_type_parcelle:

  Sous-type OSM des limites fournies : `"section"` (defaut, parcellaire
  de gestion forestiere – ses limites sont les layons materialises au
  sol) ou `"border"` (limites de propriete, un parcellaire cadastral).
  Le choix n'est pas devinable depuis la geometrie.

- ...:

  Passe a
  [`dsr_peignes()`](https://pobsteta.github.io/dessertR/reference/dsr_peignes.md)
  quand `aretes` ne porte pas `PEIGNE`.

## Value

Le `sf` d'entree, augmente de `CLASSE`, `CLASSE_CONF` (part de criteres
renseignes qui concordent), `CLASSE_MOTIF` (les criteres qui ont vote,
en clair) et `OSM_TAGS` (proposition de balisage, `NA` si aucune).

## Details

**La decision porte sur des structures, pas sur des seuils de largeur.**
Sur MNT 50 cm sous couvert, la rupture chaussee/accotement n'est le plus
souvent pas resolue et `LARGEUR_ROULABLE` rend une plateforme (voir
`BORDS_CHAUSSEE`) : un seuil de largeur porterait alors sur une grandeur
qui n'est pas celle qu'on croit mesurer. `BORDS_CHAUSSEE` lui-meme ne
sert pas de critere : il dit si la mesure a REUSSI, pas si la route est
construite – une route batie sous couvert dense peut n'y resoudre aucun
bord. Les criteres retenus sont donc structurels – portage par la
reference, appartenance a un peigne
([`dsr_peignes()`](https://pobsteta.github.io/dessertR/reference/dsr_peignes.md)),
presence de fosses, coincidence avec le parcellaire – et le seul seuil
radiometrique, celui du NDVI, est determine par Otsu sur la donnee
([`dsr_largeur_ndvi()`](https://pobsteta.github.io/dessertR/reference/dsr_largeur_ndvi.md)).

**Cascade de decision.** Les structures sont evaluees d'abord, puis
l'ouvrage – reference ou fosses – qui prime sur elles :

1.  dent d'un peigne, non minerale, sans fosse -\>
    `cloisonnement_exploitation` ;

2.  coincide avec une limite du parcellaire et non minerale -\>
    `layon_parcellaire` ;

3.  porte par la reference ou creuse de fosses, minerale -\>
    `route_forestiere` ;

4.  idem, non minerale -\> `piste_forestiere` ;

5.  idem, nature de surface inconnue -\> `desserte` ;

6.  sinon `indetermine`.

`desserte` n'est pas une classe de repli commode : c'est le refus de
trancher entre route et piste sans le canal optique. Sans NDVI, aucun
`surface=` ni `tracktype=` n'est propose.

**`connecte_public` est reporte, pas decisif.**
[`dsr_reseau()`](https://pobsteta.github.io/dessertR/reference/dsr_reseau.md)
l'attribue par COMPOSANTE : un cloisonnement greffe sur une piste
desservie herite d'un `TRUE` qui ne dit rien de lui. Il figure dans
`CLASSE_MOTIF` – ou son absence signale une composante isolee, donc un
candidat trace fossile – mais n'entre pas dans la cascade.

**Tags d'acces.** Aucun n'est emis par defaut : un panneau ne se lit pas
dans un MNT. Fournir `panneaux` – releve terrain, ou photos
geolocalisees d'un jumeau numerique – fait emettre `access=<valeur>`
accompagne de `source:access`, qui porte la provenance. Deux panneaux
contradictoires sur un meme troncon n'emettent rien et le motif le dit.

## References

Fil OSM-fr, « Layons, cloisonnements d'exploitation en forets publiques
», <https://forum.openstreetmap.fr/t/44555>.

## See also

[`dsr_peignes()`](https://pobsteta.github.io/dessertR/reference/dsr_peignes.md),
[`dsr_detecter()`](https://pobsteta.github.io/dessertR/reference/dsr_detecter.md),
[`dsr_reseau()`](https://pobsteta.github.io/dessertR/reference/dsr_reseau.md),
[`dsr_measure()`](https://pobsteta.github.io/dessertR/reference/dsr_measure.md).

## Examples

``` r
g <- lapply(seq(0, 60, by = 20), function(y)
  sf::st_linestring(cbind(c(0, 100), c(y, y))))
tr <- sf::st_sf(geometry = sf::st_sfc(g, crs = 2154))
dsr_classer(tr)[, c("CLASSE", "OSM_TAGS")]
#> Simple feature collection with 4 features and 2 fields
#> Geometry type: LINESTRING
#> Dimension:     XY
#> Bounding box:  xmin: 0 ymin: 0 xmax: 100 ymax: 60
#> Projected CRS: RGF93 v1 / Lambert-93
#>                       CLASSE                                OSM_TAGS
#> 1 cloisonnement_exploitation man_made=cutline;cutline=loggingmachine
#> 2 cloisonnement_exploitation man_made=cutline;cutline=loggingmachine
#> 3 cloisonnement_exploitation man_made=cutline;cutline=loggingmachine
#> 4 cloisonnement_exploitation man_made=cutline;cutline=loggingmachine
#>                    geometry
#> 1   LINESTRING (0 0, 100 0)
#> 2 LINESTRING (0 20, 100 20)
#> 3 LINESTRING (0 40, 100 40)
#> 4 LINESTRING (0 60, 100 60)
```
