# Detecter la desserte hors reference

Repere les axes de desserte probables **absents du reseau de reference**
: les cellules de forte conductivite geomorphologique (et, si fourni, de
forte linearite `vesselness`) situees **hors** d'un tampon autour de la
reference, regroupees en composantes connexes puis reduites a une
centre-ligne par analyse en composantes principales (BRIEF section 3.9).
Complementaire du recalage, qui lui conserve la reference
([`dsr_repositionner()`](https://pobsteta.github.io/dessertR/reference/dsr_repositionner.md)).

## Usage

``` r
dsr_detecter(
  sigma_geo,
  reference = NULL,
  vesselness = NULL,
  seuil = 0.6,
  seuil_vessel = 0.3,
  buffer_ref = 15,
  long_min = 30,
  ratio_min = 3,
  pas_bin = 5
)
```

## Arguments

- sigma_geo:

  Conductivite geomorphologique
  ([`dsr_conductivite()`](https://pobsteta.github.io/dessertR/reference/dsr_conductivite.md)),
  `SpatRaster`.

- reference:

  `sf`/`sfc` du reseau de reference (BD TOPO) a exclure ; `NULL` pour ne
  rien exclure.

- vesselness:

  Raster de linearite
  ([`dsr_layers_dtm()`](https://pobsteta.github.io/dessertR/reference/dsr_layers_dtm.md))
  pour restreindre aux structures lineaires ; `NULL` pour l'ignorer.

- seuil, seuil_vessel:

  Seuils de conductivite et de linearite. Defaut 0.6 et 0.3.

- buffer_ref:

  Demi-largeur (m) du corridor de reference a exclure. Defaut 15.

- long_min:

  Longueur minimale (m) d'un axe detecte. Defaut 30.

- ratio_min:

  Rapport d'allongement minimal (grand axe / petit axe) d'une composante
  pour etre traitee comme lineaire. Defaut 3.

- pas_bin:

  Pas d'echantillonnage (m) le long de l'axe principal pour la
  centre-ligne. Defaut 5.

## Value

Un `sf` `LINESTRING` des axes detectes (colonnes `id`, `longueur`), ou
un `sf` vide si aucun. A affiner avec `vecnet` pour une vectorisation
topologique complete.

## See also

[`dsr_conductivite()`](https://pobsteta.github.io/dessertR/reference/dsr_conductivite.md),
[`dsr_repositionner()`](https://pobsteta.github.io/dessertR/reference/dsr_repositionner.md).
