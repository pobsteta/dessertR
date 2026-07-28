make_grid <- function(n = 40, val = 0.1) {
  g <- terra::rast(nrows = n, ncols = n, xmin = 0, xmax = n, ymin = 0, ymax = n,
    crs = "EPSG:2154")
  terra::values(g) <- val
  g
}

test_that("le trace suit un couloir conducteur droit", {
  skip_if_not_installed("terra")
  skip_if_not_installed("sf")
  sg <- make_grid(40, 0.08)
  sg[20, ] <- 0.95 # couloir horizontal
  tr <- dsr_pathfinder(sg, c(1, 20.5), c(39, 20.5))
  expect_s3_class(tr$trace, "sf")
  expect_true(is.finite(tr$cout))
  pxy <- sf::st_coordinates(tr$trace)[, 2]
  expect_lt(mean(abs(pxy - 20.5)), 2) # reste dans le couloir
})

test_that("voisinage 16 : trace quasi droit sur grille uniforme (metrication)", {
  skip_if_not_installed("terra")
  skip_if_not_installed("sf")
  sg <- make_grid(30, 0.7)
  tr <- dsr_pathfinder(sg, 1, terra::ncell(sg))
  p <- sf::st_coordinates(tr$trace)[, 1:2]
  d_eucl <- sqrt(sum((p[nrow(p), ] - p[1, ])^2))
  d_path <- sum(sqrt(rowSums(diff(p)^2)))
  expect_lt(d_path / d_eucl, 1.05)
})

test_that("l'anisotropie penalise la traverse de l'orientation", {
  skip_if_not_installed("terra")
  sg <- make_grid(20, 0.7)
  th <- terra::rast(sg); terra::values(th) <- 0 # E-W partout
  wt <- terra::rast(sg); terra::values(wt) <- 1
  iso  <- dsr_pathfinder(sg, 1, terra::ncell(sg), lambda = 0)$cout
  ani  <- dsr_pathfinder(sg, 1, terra::ncell(sg), theta = th, poids = wt, lambda = 6)$cout
  expect_gt(ani, iso) # trajet diagonal traverse theta
})

test_that("une barriere NA de deux cellules rend la cible inatteignable", {
  skip_if_not_installed("terra")
  sg <- make_grid(20, 0.6)
  sg[, 10] <- NA; sg[, 11] <- NA # barriere large de 2 (etanche au voisinage 16)
  expect_error(dsr_pathfinder(sg, c(2, 10), c(18, 10)), "Aucun chemin")
})

test_that("cout_cumule renvoie un raster aligne", {
  skip_if_not_installed("terra")
  sg <- make_grid(15, 0.7)
  tr <- dsr_pathfinder(sg, 1, terra::ncell(sg), cout_cumule = TRUE)
  expect_s4_class(tr$cout_cumule, "SpatRaster")
  expect_equal(terra::res(tr$cout_cumule), terra::res(sg))
})

test_that("theta non aligne sur sigma_geo est refuse", {
  skip_if_not_installed("terra")
  sg <- make_grid(20, 0.7)
  th <- make_grid(25, 0)
  expect_error(dsr_pathfinder(sg, 1, 400, theta = th), "aligne")
})

test_that("dsr_repositionner : respecte la contrainte laterale et conserve tout", {
  skip_if_not_installed("terra"); skip_if_not_installed("sf")
  n <- 60
  sg <- terra::rast(nrows = n, ncols = n, xmin = 0, xmax = n, ymin = 0, ymax = n,
    crs = "EPSG:2154")
  terra::values(sg) <- 0.05
  xy <- terra::xyFromCell(sg, seq_len(terra::ncell(sg)))
  sg[abs(xy[, 2] - 30) < 1] <- 0.7    # axe reel proche de la BD TOPO
  sg[abs(xy[, 2] - 45) < 1] <- 0.95   # leurre parallele fort a 15 m
  reseau <- sf::st_sf(id = 1:2, geometry = sf::st_sfc(
    sf::st_linestring(cbind(c(2, 58), c(30, 30))),
    sf::st_linestring(cbind(c(2, 58), c(50, 50))), crs = 2154))

  r <- dsr_repositionner(reseau, sg, deviation_max = 10, attraction = 1)
  # aucun troncon perdu
  expect_equal(nrow(r), nrow(reseau))
  # jamais au-dela de la contrainte (le leurre a 15 m est hors d'atteinte)
  expect_true(all(r$DEPLACEMENT_MAX[r$RECALE] <= 10 + 1e-6))
  expect_true(all(c("DEPLACEMENT_MAX", "DEPLACEMENT_MOY", "RECALE") %in% names(r)))
})

test_that("dsr_repositionner : replie sur l'axe si le pathfinder echoue", {
  skip_if_not_installed("terra"); skip_if_not_installed("sf")
  sg <- terra::rast(nrows = 20, ncols = 20, xmin = 0, xmax = 20, ymin = 0,
    ymax = 20, crs = "EPSG:2154")
  terra::values(sg) <- NA_real_ # aucune conductivite -> pathfinder impossible
  reseau <- sf::st_sf(id = 1, geometry = sf::st_sfc(
    sf::st_linestring(cbind(c(2, 18), c(10, 10))), crs = 2154))
  r <- dsr_repositionner(reseau, sg, deviation_max = 10)
  expect_equal(nrow(r), 1)          # conserve
  expect_false(r$RECALE[1])         # repli sur l'origine
})
