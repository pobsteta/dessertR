# Cataloguer un jeu de dalles Lidar HD

Construit un index spatial des dalles LAZ, MNT et MNH et les apparie sur
la grille kilometrique. C'est le socle de tout le reste : les
traitements se font *par dalle*, jamais par troncon.

## Usage

``` r
dsr_catalog(
  laz = NULL,
  mnt = NULL,
  mnh = NULL,
  crs = DSR_CRS_DEFAUT,
  entetes = TRUE
)
```

## Arguments

- laz, mnt, mnh:

  Repertoires ou vecteurs de chemins. `NULL` si absent.

- crs:

  Code EPSG. Defaut 2154 (RGF93 / Lambert-93).

- entetes:

  Lire les en-tetes LAS pour recuperer les emprises reelles, le nombre
  de points et les metadonnees de production. Peu couteux (aucun point
  n'est decompresse) mais suppose un acces disque a chaque fichier.

## Value

Un objet `sf` de classe `dsr_catalog`, une ligne par dalle.

## Examples

``` r
if (FALSE) { # \dontrun{
cat <- dsr_catalog(
  laz = "~/lidarhd/laz",
  mnt = "~/lidarhd/mnt",
  mnh = "~/lidarhd/mnh"
)
plot(sf::st_geometry(cat))
} # }
```
