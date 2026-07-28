# Conductivite apprise (lot 8). On fabrique une pile ou un seul canal porte le
# signal, avec une route rectiligne connue : le modele doit la retrouver.

pile_apprentissage <- function(n = 60) {
  r <- terra::rast(nrows = n, ncols = n, xmin = 0, xmax = n, ymin = 0, ymax = n,
    crs = "EPSG:2154")
  xy <- terra::xyFromCell(r, seq_len(terra::ncell(r)))
  d <- abs(xy[, 2] - n / 2)

  signal <- terra::rast(r)
  terra::values(signal) <- exp(-(d^2) / (2 * 2^2))
  bruit <- terra::rast(r)
  terra::values(bruit) <- stats::runif(terra::ncell(r))

  couches <- c(signal, bruit)
  names(couches) <- c("empreinte", "bruit")
  couches
}

route_ew <- function(n = 60) {
  sf::st_sf(id = 1, geometry = sf::st_sfc(
    sf::st_linestring(cbind(c(2, n - 2), c(n / 2, n / 2))), crs = 2154))
}

test_that("dsr_echantillon : deux classes equilibrees, canaux en colonnes", {
  skip_if_not_installed("terra"); skip_if_not_installed("sf")
  set.seed(1)
  ech <- dsr_echantillon(pile_apprentissage(), route_ew(), buffer_pos = 2,
    buffer_neg = 10, n_max = 400)

  expect_s3_class(ech, "data.frame")
  expect_equal(names(ech), c("y", "empreinte", "bruit"))
  expect_setequal(unique(ech$y), c(0L, 1L))
  expect_equal(sum(ech$y == 1L), sum(ech$y == 0L))
  expect_lte(nrow(ech), 400)
  # la bande grise (entre buffer_pos et buffer_neg) n'est pas prelevee :
  # les positifs portent une empreinte franchement plus forte.
  expect_gt(mean(ech$empreinte[ech$y == 1L]), mean(ech$empreinte[ech$y == 0L]))
})

test_that("dsr_echantillon : buffer_neg <= buffer_pos -> erreur", {
  skip_if_not_installed("terra"); skip_if_not_installed("sf")
  expect_error(
    dsr_echantillon(pile_apprentissage(), route_ew(), buffer_pos = 5,
      buffer_neg = 3),
    "buffer_neg"
  )
})

test_that("dsr_apprendre_conductivite : AUC de validation croisee elevee sur un signal net", {
  skip_if_not_installed("terra"); skip_if_not_installed("sf")
  set.seed(2)
  ech <- dsr_echantillon(pile_apprentissage(), route_ew(), buffer_pos = 2,
    buffer_neg = 10, n_max = 600)
  mod <- dsr_apprendre_conductivite(ech, methode = "glm", k = 5)

  expect_s3_class(mod, "dsr_modele_conductivite")
  expect_equal(mod$canaux, c("empreinte", "bruit"))
  expect_gt(mod$auc_vc, 0.9)
  expect_false(is.na(mod$auc_app))
  expect_equal(mod$prevalence, 0.5, tolerance = 1e-9)
  # cli ecrit sur stdout ou stderr selon le contexte : on capture les deux.
  txt <- c(capture.output(print(mod)),
    capture.output(print(mod), type = "message"))
  expect_true(any(grepl("Conductivite apprise", txt)))
})

test_that("dsr_apprendre_conductivite : une seule classe -> erreur", {
  ech <- data.frame(y = rep(1L, 10), a = stats::runif(10))
  expect_error(dsr_apprendre_conductivite(ech), "classes")
})

test_that("predict : raster de probabilite aligne, plus fort sur la route", {
  skip_if_not_installed("terra"); skip_if_not_installed("sf")
  set.seed(3)
  couches <- pile_apprentissage()
  ech <- dsr_echantillon(couches, route_ew(), buffer_pos = 2, buffer_neg = 10,
    n_max = 600)
  mod <- dsr_apprendre_conductivite(ech, k = NULL)

  p <- stats::predict(mod, couches)
  expect_s4_class(p, "SpatRaster")
  expect_equal(names(p), "p_route")
  expect_equal(terra::ncell(p), terra::ncell(couches))

  xy <- terra::xyFromCell(p, seq_len(terra::ncell(p)))
  v <- terra::values(p, mat = FALSE)
  sur <- abs(xy[, 2] - 30) < 2
  loin <- abs(xy[, 2] - 30) > 15
  expect_gt(mean(v[sur]), mean(v[loin]))
})

test_that("predict : canal manquant -> erreur informative", {
  skip_if_not_installed("terra"); skip_if_not_installed("sf")
  set.seed(4)
  couches <- pile_apprentissage()
  mod <- dsr_apprendre_conductivite(
    dsr_echantillon(couches, route_ew(), buffer_pos = 2, buffer_neg = 10,
      n_max = 200),
    k = NULL
  )
  expect_error(stats::predict(mod, couches[["bruit"]]), "empreinte")
})

test_that("dsr_conductivite : method model utilise le modele et respecte sigma_min", {
  skip_if_not_installed("terra"); skip_if_not_installed("sf")
  set.seed(5)
  couches <- pile_apprentissage()
  mod <- dsr_apprendre_conductivite(
    dsr_echantillon(couches, route_ew(), buffer_pos = 2, buffer_neg = 10,
      n_max = 600),
    k = NULL
  )
  sg <- dsr_conductivite(couches, method = "model", modele = mod,
    sigma_min = 0.05)

  expect_equal(names(sg), "sigma_geo")
  mm <- terra::minmax(sg)
  expect_gte(mm[1], 0.05)
  expect_lte(mm[2], 1)
})

test_that("dsr_conductivite : method model sans modele -> erreur informative", {
  skip_if_not_installed("terra")
  couches <- pile_apprentissage(20)
  expect_error(dsr_conductivite(couches, method = "model"), "apprise")
})
