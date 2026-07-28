# Construction du jeu de donnees d'exemple de inst/extdata/ (BRIEF L0).
# Extrait un secteur de 200 x 200 m du bloc de validation wsfi, centre sur un
# franchissement route x cours d'eau (test des tabliers de pont) : nuage classe
# ecrete, MNT et MNH 50 cm croppes, extrait BD TOPO (routes, eau).
#
# Donnees IGN sous licence ouverte Etalab : redistribution autorisee (mention
# d'attribution dans inst/extdata/LICENSE.note). A relancer si la source change.

suppressMessages({library(terra); library(sf); library(lasR)})

P <- Sys.getenv("DSR_WSFI",
  "/home/pascal/.local/share/nemeton/projects/20260717_101641_wsfi/cache")
OUT <- "inst/extdata"
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)

# Emprise : 200 x 200 m autour du franchissement (737916, 6385847).
cx <- 737916; cy <- 6385847; d <- 100
xmin <- cx - d; xmax <- cx + d; ymin <- cy - d; ymax <- cy + d
emp <- sf::st_as_sfc(sf::st_bbox(c(xmin = xmin, ymin = ymin, xmax = xmax, ymax = ymax),
  crs = sf::st_crs(2154)))

# 1. Nuage classe ecrete (decime pour rester < ~4 Mo, structure conservee).
pipe <- lasR::reader_las_rectangles(xmin, ymin, xmax, ymax) +
  lasR::sampling_poisson(0.5) +
  lasR::write_las(file.path(OUT, "exemple_nuage.laz"))
lasR::exec(pipe, on = file.path(P, "layers/lidar_nuage"))

# 2. MNT et MNH 50 cm croppes.
ext_r <- terra::ext(xmin, xmax, ymin, ymax)
for (prod in c("mnt", "mnh")) {
  r <- terra::crop(terra::rast(file.path(P, sprintf("layers/lidar_%s_mosaic.tif", prod))), ext_r)
  terra::writeRaster(r, file.path(OUT, sprintf("exemple_%s.tif", prod)),
    overwrite = TRUE, gdal = c("COMPRESS=DEFLATE", "PREDICTOR=3"))
}

# 3. Extrait BD TOPO (routes, eau) dans l'emprise.
clip <- function(f, couche = NULL) {
  args <- list(file.path(P, f), quiet = TRUE)
  if (!is.null(couche)) args$layer <- couche
  x <- sf::st_zm(do.call(sf::st_read, args))
  sf::st_intersection(x[sf::st_intersects(x, emp, sparse = FALSE)[, 1], ], emp)
}
roads <- clip("layers/roads.gpkg")
eau <- clip("layers/water_network.gpkg")
gpkg <- file.path(OUT, "exemple_bdtopo.gpkg")
if (file.exists(gpkg)) unlink(gpkg)
sf::st_write(roads, gpkg, layer = "troncon_de_route", quiet = TRUE)
sf::st_write(eau, gpkg, layer = "troncon_hydrographique", append = TRUE, quiet = TRUE)

message(sprintf("Exemple ecrit dans %s (LAZ %.1f Mo, %d routes, %d cours d'eau).",
  OUT, file.info(file.path(OUT, "exemple_nuage.laz"))$size / 1e6, nrow(roads), nrow(eau)))
