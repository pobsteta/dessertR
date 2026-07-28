# Etat de la desserte le long d'un trace

Echantillonne `sigma_geo` et `sigma_surf` le long d'un trace (sortie de
[`dsr_pathfinder()`](https://pobsteta.github.io/dessertR/reference/dsr_pathfinder.md)
ou geometrie de reference BD TOPO), en classe l'etat par troncon et
resume la repartition. C'est la lecture **pertinente** de l'etat : en
raster plein il est bruite (faux positifs geomorphologiques sous
couvert), mais le long du trace retenu il devient interpretable (BRIEF
section 3.4).

## Usage

``` r
dsr_etat_trace(
  trace,
  sigma_geo,
  sigma_surf,
  pas = 2,
  seuil_geo = 0.5,
  seuil_surf = 0.5
)
```

## Arguments

- trace:

  Un `sf`/`sfc` `LINESTRING` (ou l'element `trace` renvoye par
  [`dsr_pathfinder()`](https://pobsteta.github.io/dessertR/reference/dsr_pathfinder.md)).

- sigma_geo, sigma_surf:

  `SpatRaster` mono-couche alignes, dans `[0, 1]`.

- pas:

  Pas d'echantillonnage le long du trace, en metres. Defaut 2.

- seuil_geo, seuil_surf:

  Seuils de bascule fort/faible. Defaut 0.5.

## Value

Une liste :

- `troncons`:

  `sf` `LINESTRING` decoupe en segments d'etat homogene, colonnes
  `etat`, `longueur`, `sigma_geo`, `sigma_surf`, `divergence`.

- `profil`:

  `sf` `POINT` echantillonne, avec `chainage` (m) et les memes valeurs –
  le profil longitudinal.

- `resume`:

  `data.frame` : longueur et pourcentage par etat.

## See also

[`dsr_etat()`](https://pobsteta.github.io/dessertR/reference/dsr_etat.md),
[`dsr_pathfinder()`](https://pobsteta.github.io/dessertR/reference/dsr_pathfinder.md).
