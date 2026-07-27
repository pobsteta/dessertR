test_that("dsr_appartenance : rampe croissante aux valeurs connues", {
  v <- c(0, 20, 50, 80, 100)
  mu <- dsr_appartenance(v, "croissante", a = 20, b = 80)
  expect_equal(mu, c(0, 0, 0.5, 1, 1), tolerance = 1e-9)
})

test_that("dsr_appartenance : decroissante = miroir de croissante", {
  v <- seq(0, 100, by = 10)
  up <- dsr_appartenance(v, "croissante", a = 20, b = 80)
  dn <- dsr_appartenance(v, "decroissante", a = 20, b = 80)
  expect_equal(up + dn, rep(1, length(v)), tolerance = 1e-9)
})

test_that("dsr_appartenance : sortie raster reste un raster dans [0,1]", {
  skip_if_not_installed("terra")
  r <- terra::rast(nrows = 10, ncols = 10, xmin = 0, xmax = 10, ymin = 0,
    ymax = 10, crs = "EPSG:2154")
  terra::values(r) <- stats::runif(terra::ncell(r), 0, 100)
  mu <- dsr_appartenance(r, "croissante", a = 20, b = 80)
  expect_s4_class(mu, "SpatRaster")
  mm <- terra::minmax(mu)
  expect_gte(mm[1], 0)
  expect_lte(mm[2], 1)
})

test_that("dsr_conductivite : sigma_geo dans [sigma_min, 1] et empreinte plus forte sur la vallee", {
  skip_if_not_installed("terra")
  n <- 70
  g <- terra::rast(nrows = n, ncols = n, xmin = 0, xmax = n, ymin = 0, ymax = n,
    crs = "EPSG:2154")
  xy <- terra::xyFromCell(g, seq_len(terra::ncell(g)))
  d <- (xy[, 2] - xy[, 1]) / sqrt(2)
  terra::values(g) <- 100 - 2 * exp(-(d^2) / (2 * 3^2))

  pile <- dsr_layers_dtm(g, res = 1, rayons_openness = c(2, 5),
    echelles_vessel = c(1, 2), fenetres_slrm = 5)
  sg <- dsr_conductivite(pile, sigma_min = 0.05)

  expect_equal(names(sg), "sigma_geo")
  mm <- terra::minmax(sg)
  expect_gte(mm[1], 0.05)
  expect_lte(mm[2], 1)

  vals <- terra::values(sg, mat = FALSE)
  ligne <- which(abs(d) < 1); dehors <- which(abs(d) > 8)
  expect_gt(median(vals[ligne], na.rm = TRUE), median(vals[dehors], na.rm = TRUE))
})

test_that("dsr_conductivite : method model non implemente -> erreur informative", {
  skip_if_not_installed("terra")
  g <- terra::rast(nrows = 40, ncols = 40, xmin = 0, xmax = 40, ymin = 0,
    ymax = 40, crs = "EPSG:2154")
  terra::values(g) <- 100 + stats::runif(terra::ncell(g))
  pile <- dsr_layers_dtm(g, res = 1, rayons_openness = 2, echelles_vessel = 1,
    fenetres_slrm = 5)
  expect_error(dsr_conductivite(pile, method = "model"), "apprise")
})

test_that("dsr_conductivite : confiance nulle tire sigma vers l'incertain 0.5", {
  skip_if_not_installed("terra")
  g <- terra::rast(nrows = 40, ncols = 40, xmin = 0, xmax = 40, ymin = 0,
    ymax = 40, crs = "EPSG:2154")
  terra::values(g) <- 100 + stats::runif(terra::ncell(g))
  pile <- dsr_layers_dtm(g, res = 1, rayons_openness = 2, echelles_vessel = 1,
    fenetres_slrm = 5)
  conf <- terra::rast(pile[[1]]); terra::values(conf) <- 0
  sg <- dsr_conductivite(pile, confiance = conf)
  expect_equal(unname(terra::global(sg, "mean", na.rm = TRUE)[1, 1]), 0.5,
    tolerance = 1e-9)
})

test_that("dsr_conductivite : aucun canal correspondant -> erreur", {
  skip_if_not_installed("terra")
  r <- terra::rast(nrows = 10, ncols = 10, xmin = 0, xmax = 10, ymin = 0,
    ymax = 10, crs = "EPSG:2154")
  terra::values(r) <- 1
  names(r) <- "inconnu"
  expect_error(dsr_conductivite(r), "Aucun canal")
})
