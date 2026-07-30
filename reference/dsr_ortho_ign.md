# Ortho IGN (RVB ou IRC) sur une emprise

Telecharge l'ortho de la Geoplateforme IGN a sa resolution native, en
tuilant la requete. Sert le canal optique du paquet
([`dsr_ndvi()`](https://pobsteta.github.io/dessertR/reference/dsr_ndvi.md)).

## Usage

``` r
dsr_ortho_ign(
  emprise,
  couche = "ORTHOIMAGERY.ORTHOPHOTOS.IRC",
  res = 0.2,
  pas = 200
)
```

## Arguments

- emprise:

  `sf`/`sfc`/`SpatVector`/`SpatRaster` donnant l'emprise voulue.

- couche:

  Couche WMS. Defaut l'ortho IRC (PIR, Rouge, Vert), celle qu'attend
  [`dsr_ndvi()`](https://pobsteta.github.io/dessertR/reference/dsr_ndvi.md).
  `"ORTHOIMAGERY.ORTHOPHOTOS"` pour le RVB.

- res:

  Resolution demandee, en metres. Defaut 0.2.

- pas:

  Cote des tuiles de requete, en metres. Defaut 200 (soit 1000 px a 20
  cm, loin de la limite du service).

## Value

Un `SpatRaster` trois bandes en `EPSG:2154`, ou `NULL` si le service n'a
rien rendu.

## Details

Trois pieges du service, tous rencontres et tous silencieux :

- le WMS **impose `VERSION=1.3.0`** – toute autre valeur est rejetee ;

- en `EPSG:2154` l'ordre des axes est **(X, Y)**. Un BBOX inverse ne
  leve aucune erreur : le service rend un GeoTIFF valide et
  **entierement vide** ;

- le GeoTIFF rendu **n'a pas toujours de CRS**. Sans reaffectation, les
  croisements ulterieurs sortent un avertissement `CRS do not match` et,
  selon les cas, des valeurs fausses.

Le tuilage n'est pas un detail : au-dela d'environ 4096 pixels de cote,
un appel unique force a **degrader la resolution**. Comme l'interet du
canal optique est precisement d'etre a l'echelle d'une chaussee, on
decoupe pour preserver le 20 cm natif.

## See also

[`dsr_ndvi()`](https://pobsteta.github.io/dessertR/reference/dsr_ndvi.md),
[`dsr_canaux_externes()`](https://pobsteta.github.io/dessertR/reference/dsr_canaux_externes.md).

## Examples

``` r
if (FALSE) { # \dontrun{
irc <- dsr_ortho_ign(sf::st_as_sfc(sf::st_bbox(mnt)))
ndvi <- dsr_ndvi(irc)
} # }
```
