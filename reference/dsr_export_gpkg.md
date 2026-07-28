# Exporter les couches d'un massif en GeoPackage

Ecrit un jeu de couches vectorielles `sf` dans un unique GeoPackage, une
couche par element nomme (BRIEF section 3). Ecrit optionnellement les
styles QGIS accompagnant les couches reconnues (`etat`, `aptitude`).

## Usage

``` r
dsr_export_gpkg(couches, fichier, styles = TRUE, overwrite = TRUE)
```

## Arguments

- couches:

  Liste **nommee** d'objets `sf` (p. ex.
  `list(trace = ..., stations = ..., etat = ..., reseau = ...)`).

- fichier:

  Chemin du GeoPackage de sortie.

- styles:

  Ecrire les fichiers `.qml` pour les couches stylables. Defaut `TRUE`.

- overwrite:

  Ecraser un GeoPackage existant. Defaut `TRUE`.

## Value

Le chemin du GeoPackage, invisiblement.

## See also

[`dsr_qml_categorise()`](https://pobsteta.github.io/dessertR/reference/dsr_qml_categorise.md),
[`dsr_rapport()`](https://pobsteta.github.io/dessertR/reference/dsr_rapport.md).

## Examples

``` r
# \donttest{
tr <- sf::st_sf(id = 1, geometry = sf::st_sfc(
  sf::st_linestring(cbind(c(0, 10), c(0, 0))), crs = 2154))
f <- tempfile(fileext = ".gpkg")
dsr_export_gpkg(list(trace = tr), f)
sf::st_layers(f)$name
#> [1] "trace"
# }
```
