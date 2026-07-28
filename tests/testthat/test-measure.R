road_mnt <- function(n = 60, fun) {
  mnt <- terra::rast(nrows = n, ncols = n, xmin = 0, xmax = n, ymin = 0,
    ymax = n, resolution = 1, crs = "EPSG:2154")
  xy <- terra::xyFromCell(mnt, seq_len(terra::ncell(mnt)))
  terra::values(mnt) <- fun(xy[, 2] - n / 2) # d = distance a l'axe y = n/2
  mnt
}
ligne_ew <- function(n = 60) {
  sf::st_sf(geometry = sf::st_sfc(
    sf::st_linestring(cbind(c(5, n - 5), c(n / 2, n / 2))), crs = 2154))
}

test_that("dsr_profils renvoie une matrice stations x offsets", {
  skip_if_not_installed("terra"); skip_if_not_installed("sf")
  mnt <- road_mnt(fun = function(d) 100 + 0 * d)
  pr <- dsr_profils(ligne_ew(), mnt, pas = 2, demi_largeur = 6, pas_travers = 0.5)
  expect_named(pr, c("stations", "offsets", "z", "normales"))
  expect_equal(ncol(pr$z), length(pr$offsets))
  expect_equal(nrow(pr$z), nrow(pr$stations))
})

test_that("largeur roulable : plateforme plate encadree de talus raides", {
  skip_if_not_installed("terra"); skip_if_not_installed("sf")
  # plateforme plate |d|<=5 (largeur 10), talus de pente 3 au-dela. Tolerance
  # large : la maille de 1 m rabote ~1 m de chaque bord a l'interpolation.
  mnt <- road_mnt(n = 80, fun = function(d) ifelse(abs(d) <= 5, 100, 100 + 3 * (abs(d) - 5)))
  tr <- sf::st_sf(geometry = sf::st_sfc(
    sf::st_linestring(cbind(c(5, 75), c(40, 40))), crs = 2154))
  m <- dsr_measure(tr, mnt, pas = 2, demi_largeur = 10, pas_travers = 0.25, liss_travers = 1)
  expect_gt(median(m$stations$LARGEUR_ROULABLE), 6)
  expect_lt(median(m$stations$LARGEUR_ROULABLE), 11)
})

test_that("devers : une plateforme inclinee a 8% est mesuree", {
  skip_if_not_installed("terra"); skip_if_not_installed("sf")
  mnt <- road_mnt(fun = function(d) ifelse(abs(d) <= 3, 100 + 0.08 * d,
    100 + 0.08 * d + 3 * (abs(d) - 3)))
  m <- dsr_measure(ligne_ew(), mnt, pas = 2, pas_travers = 0.25, liss_travers = 1)
  expect_equal(abs(median(m$stations$DEVERS)), 0.08, tolerance = 0.02)
})

test_that("trace droit sur MNT plan : pente ~0, sinuosite 1, courbure infinie", {
  skip_if_not_installed("terra"); skip_if_not_installed("sf")
  mnt <- road_mnt(fun = function(d) 100 + 0 * d)
  m <- dsr_measure(ligne_ew(), mnt, pas = 2)
  expect_lt(m$resume$PENTE_LONG_MOY, 1e-6)
  expect_equal(m$resume$SINUOSITE, 1, tolerance = 1e-6)
  expect_true(is.infinite(m$resume$RAYON_COURBURE_MIN))
})

test_that("trace courbe : sinuosite > 1 et rayon de courbure fini", {
  skip_if_not_installed("terra"); skip_if_not_installed("sf")
  mnt <- road_mnt(n = 80, fun = function(d) 100 + 0 * d)
  x <- seq(5, 75, by = 2); y <- 40 + 15 * sin(pi * (x - 5) / 70)
  tr <- sf::st_sf(geometry = sf::st_sfc(sf::st_linestring(cbind(x, y)), crs = 2154))
  m <- dsr_measure(tr, mnt, pas = 2)
  expect_gt(m$resume$SINUOSITE, 1)
  expect_true(is.finite(m$resume$RAYON_COURBURE_MIN))
})

test_that("dsr_measure : DEPLACEMENT a une reference et CONFIANCE_MNT", {
  skip_if_not_installed("terra"); skip_if_not_installed("sf")
  mnt <- road_mnt(fun = function(d) 100 + 0 * d)
  conf <- terra::rast(mnt); terra::values(conf) <- 7
  ref <- sf::st_sf(geometry = sf::st_sfc(
    sf::st_linestring(cbind(c(5, 55), c(33, 33))), crs = 2154)) # decale de 3 m
  m <- dsr_measure(ligne_ew(), mnt, reference = ref, confiance = conf)
  expect_true(all(c("DEPLACEMENT", "CONFIANCE_MNT") %in% names(m$stations)))
  expect_equal(median(m$stations$DEPLACEMENT), 3, tolerance = 0.5)
  expect_equal(median(m$stations$CONFIANCE_MNT), 7, tolerance = 1e-6)
})
