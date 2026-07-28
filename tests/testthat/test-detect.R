sigma_avec_piste <- function(n = 80) {
  sg <- terra::rast(nrows = n, ncols = n, xmin = 0, xmax = n, ymin = 0, ymax = n,
    crs = "EPSG:2154")
  terra::values(sg) <- 0.1
  xy <- terra::xyFromCell(sg, seq_len(terra::ncell(sg)))
  sg[abs(xy[, 2] - 20) < 1] <- 0.9                     # reference (y = 20)
  sg[abs((xy[, 2] - xy[, 1]) - 20) / sqrt(2) < 1] <- 0.85 # piste non cartographiee
  sg
}
ref_ew <- function() sf::st_sf(id = 1, geometry = sf::st_sfc(
  sf::st_linestring(cbind(c(2, 78), c(20, 20))), crs = 2154))

test_that("dsr_detecter trouve la piste hors reference et exclut la reference", {
  skip_if_not_installed("terra"); skip_if_not_installed("sf")
  det <- dsr_detecter(sigma_avec_piste(), reference = ref_ew(),
    seuil = 0.6, buffer_ref = 8, long_min = 30)
  expect_s3_class(det, "sf")
  expect_gte(nrow(det), 1)
  expect_true(all(det$longueur >= 30))
  # l'axe detecte est la diagonale (~45 deg), pas la reference horizontale
  co <- sf::st_coordinates(det[1, ])[, 1:2]
  ang <- (atan2(co[nrow(co), 2] - co[1, 2], co[nrow(co), 1] - co[1, 1]) * 180 / pi) %% 180
  expect_true(abs(ang - 45) < 15 || abs(ang - 135) < 15)
})

test_that("dsr_detecter : rien a detecter -> sf vide", {
  skip_if_not_installed("terra"); skip_if_not_installed("sf")
  sg <- terra::rast(nrows = 30, ncols = 30, xmin = 0, xmax = 30, ymin = 0,
    ymax = 30, crs = "EPSG:2154")
  terra::values(sg) <- 0.1 # tout sous le seuil
  expect_equal(nrow(dsr_detecter(sg, seuil = 0.6)), 0)
})

test_that("dsr_detecter : une tache non lineaire (blob) est ecartee", {
  skip_if_not_installed("terra"); skip_if_not_installed("sf")
  sg <- terra::rast(nrows = 40, ncols = 40, xmin = 0, xmax = 40, ymin = 0,
    ymax = 40, crs = "EPSG:2154")
  terra::values(sg) <- 0.1
  xy <- terra::xyFromCell(sg, seq_len(terra::ncell(sg)))
  sg[sqrt((xy[, 1] - 20)^2 + (xy[, 2] - 20)^2) < 6] <- 0.9 # disque, pas lineaire
  expect_equal(nrow(dsr_detecter(sg, seuil = 0.6, long_min = 20, ratio_min = 3)), 0)
})
