# Indice de detection de desserte hors reference

Fusionne les signaux disponibles en une carte de probabilite
`p_desserte` dans `[0, 1]`, **hors du corridor du reseau de reference**
(BRIEF section 3.9). C'est l'entree de
[`dsr_vectoriser()`](https://pobsteta.github.io/dessertR/reference/dsr_vectoriser.md).

## Usage

``` r
dsr_indice_detection(
  sigma_geo,
  sigma_surf = NULL,
  vesselness = NULL,
  poids = c(geo = 1, surf = 2, vessel = 1),
  seuil_vessel = 0.3,
  reference = NULL,
  buffer_ref = 15,
  emprise = NULL
)
```

## Arguments

- sigma_geo:

  Conductivite geomorphologique
  ([`dsr_conductivite()`](https://pobsteta.github.io/dessertR/reference/dsr_conductivite.md)),
  `SpatRaster`.

- sigma_surf:

  Conductivite de surface
  ([`dsr_sigma_surf()`](https://pobsteta.github.io/dessertR/reference/dsr_sigma_surf.md))
  ; `NULL` pour se passer du canal nuage (detection nettement moins
  sure).

- vesselness:

  Raster de linearite
  ([`dsr_layers_dtm()`](https://pobsteta.github.io/dessertR/reference/dsr_layers_dtm.md))
  ; `NULL` pour l'ignorer.

- poids:

  Vecteur nomme des poids `geo`, `surf` et `vessel`. Defaut
  `c(geo = 1, surf = 2, vessel = 1)`. Un poids nul ou un canal absent
  retire simplement le terme.

- seuil_vessel:

  Debut de la rampe d'appartenance sur `vesselness`. Defaut 0.3.

- reference:

  `sf`/`sfc` du reseau de reference (BD TOPO) a exclure ; `NULL` pour ne
  rien exclure.

- buffer_ref:

  Demi-largeur (m) du corridor de reference a exclure. Defaut 15.

- emprise:

  `sf`/`sfc` polygonal restreignant la zone balayee (regime `corridor`)
  ; `NULL` pour balayer toute la grille (regime `complet`).

## Value

Un `SpatRaster` mono-couche `p_desserte`, `NA` hors emprise et dans le
corridor de reference.

## Details

La fusion est une **moyenne geometrique ponderee**, comme
[`dsr_conductivite()`](https://pobsteta.github.io/dessertR/reference/dsr_conductivite.md).
Le poids par defaut privilegie le canal de surface : pistes de debardage
et cloisonnements se lisent d'abord dans la **discontinuite du
sous-etage** — une trouee lineaire persistante — et non dans le terrain,
ou leur empreinte est faible ou noyee dans les traces fossiles (BRIEF
section 3.9 et risque n.1).

`vesselness` n'entre pas en dur mais via une rampe croissante a partir
de `seuil_vessel`
([`dsr_appartenance()`](https://pobsteta.github.io/dessertR/reference/dsr_appartenance.md)),
pour ne pas annuler brutalement une cellule par ailleurs convaincante.

## See also

[`dsr_vectoriser()`](https://pobsteta.github.io/dessertR/reference/dsr_vectoriser.md),
[`dsr_detecter()`](https://pobsteta.github.io/dessertR/reference/dsr_detecter.md),
[`dsr_conductivite()`](https://pobsteta.github.io/dessertR/reference/dsr_conductivite.md).

## Examples

``` r
# \donttest{
sg <- terra::rast(
  nrows = 40, ncols = 40, xmin = 0, xmax = 40, ymin = 0, ymax = 40,
  crs = "EPSG:2154"
)
terra::values(sg) <- 0.2
p <- dsr_indice_detection(sg)
# }
```
