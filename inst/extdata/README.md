# Jeu de donnees d'exemple

Secteur de 200 x 200 m extrait d'un bloc Lidar HD reel (montagne, Lambert-93),
centre sur un **franchissement route x cours d'eau** (test des ponts). Genere par
`data-raw/make_example.R`. Total < 3,5 Mo.

- `exemple_nuage.laz` : nuage classe ecrete (~327 000 points, LAS 1.4).
- `exemple_mnt.tif` / `exemple_mnh.tif` : MNT et MNH a 50 cm, memes emprises.
- `exemple_bdtopo.gpkg` : extrait BD TOPO, couches `troncon_de_route` (4) et
  `troncon_hydrographique` (1).

Utilisation :

```r
laz <- system.file("extdata", "exemple_nuage.laz", package = "dessertR")
mnt <- terra::rast(system.file("extdata", "exemple_mnt.tif", package = "dessertR"))
roads <- sf::st_read(system.file("extdata", "exemple_bdtopo.gpkg", package = "dessertR"),
                     "troncon_de_route")
```

Donnees IGN Lidar HD et BD TOPO sous licence ouverte Etalab 2.0 : redistribution
autorisee. Voir `LICENSE.note` pour l'attribution.
