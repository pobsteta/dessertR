# Amorces d'exploration pour l'agent conducteur

Fabrique les amorces orientees dont
[`dsr_conduire()`](https://pobsteta.github.io/dessertR/reference/dsr_conduire.md)
a besoin pour demarrer, a partir de deux sources complementaires.

## Usage

``` r
dsr_amorces(p, reference = NULL, seuil = 0.6, longueur = 20, bordure = TRUE)
```

## Arguments

- p:

  Conductivite (`SpatRaster` mono-couche).

- reference:

  Reseau connu (`sf`/`sfc`), ou `NULL`.

- seuil:

  Conductivite minimale pour qu'un point de bordure amorce une
  exploration. Defaut 0.6.

- longueur:

  Longueur des amorces produites, en metres. Defaut 20.

- bordure:

  Chercher aussi les entrees de route sur le bord de l'emprise. Defaut
  `TRUE`.

## Value

Un `sfc` de `LINESTRING` orientes vers l'interieur, ou `NULL`.

## Details

**Depuis la reference (recommande).** Les extremites libres du reseau
deja connu – typiquement la BD TOPO – sont les meilleures amorces qui
soient : elles pointent exactement la ou la desserte cartographiee
s'arrete, donc la ou commence celle qui manque. C'est le cas d'usage
central du paquet, et il n'a pas d'equivalent dans vecnet, qui ne
dispose d'aucune reference.

**Depuis la bordure.** A defaut de reference, on cherche les endroits ou
une conductivite forte touche le bord de l'emprise : une route qui entre
dans la dalle. vecnet obtient le meme resultat en faisant rouler un
agent le long d'un contour interieur ; le balayage direct du bord donne
la meme chose sans le detour.

Les routes entierement interieures a l'emprise et sans lien avec la
reference ne sont atteintes par aucune des deux sources : elles le
seront par propagation, l'agent rendant a chaque pas les embranchements
rencontres.

## See also

[`dsr_conduire()`](https://pobsteta.github.io/dessertR/reference/dsr_conduire.md),
[`dsr_vectoriser()`](https://pobsteta.github.io/dessertR/reference/dsr_vectoriser.md).

## Examples

``` r
r <- terra::rast(nrows = 50, ncols = 50, xmin = 0, xmax = 100, ymin = 0,
  ymax = 100, crs = "EPSG:2154")
terra::values(r) <- 0.1
xy <- terra::xyFromCell(r, seq_len(terra::ncell(r)))
r[abs(xy[, 2] - 50) < 3] <- 1
length(dsr_amorces(r))
#> [1] 2
```
