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


# --- Garde-fous et variantes d'echantillonnage (lot 8) -----------------------

test_that("dsr_echantillon : entrees invalides -> erreurs", {
  skip_if_not_installed("terra"); skip_if_not_installed("sf")
  expect_error(dsr_echantillon("pas un raster", route_ew()), "SpatRaster")
  expect_error(dsr_echantillon(pile_apprentissage(), NULL), "positifs")
})

test_that("dsr_echantillon : negatifs explicites, polygonaux ou lineaires", {
  skip_if_not_installed("terra"); skip_if_not_installed("sf")
  set.seed(11)
  couches <- pile_apprentissage()

  # negatifs polygonaux : un carre loin de la route
  poly <- sf::st_sf(geometry = sf::st_sfc(sf::st_polygon(list(cbind(
    c(2, 25, 25, 2, 2), c(2, 2, 20, 20, 2)))), crs = 2154))
  e1 <- dsr_echantillon(couches, route_ew(), negatifs = poly, buffer_pos = 2,
    n_max = 300)
  expect_true(all(c(0L, 1L) %in% e1$y))
  expect_gt(mean(e1$empreinte[e1$y == 1L]), mean(e1$empreinte[e1$y == 0L]))

  # negatifs lineaires : tamponnes comme les positifs
  ligne <- sf::st_sf(geometry = sf::st_sfc(
    sf::st_linestring(cbind(c(5, 55), c(8, 8))), crs = 2154))
  e2 <- dsr_echantillon(couches, route_ew(), negatifs = ligne, buffer_pos = 2,
    n_max = 300)
  expect_true(all(c(0L, 1L) %in% e2$y))
})

test_that("dsr_echantillon : emprise et prelevement non equilibre", {
  skip_if_not_installed("terra"); skip_if_not_installed("sf")
  set.seed(12)
  couches <- pile_apprentissage()
  emp <- sf::st_sf(geometry = sf::st_sfc(sf::st_polygon(list(cbind(
    c(0, 40, 40, 0, 0), c(0, 0, 60, 60, 0)))), crs = 2154))

  ech <- dsr_echantillon(couches, route_ew(), buffer_pos = 2, buffer_neg = 10,
    emprise = emp, n_max = 400)
  expect_true(all(c(0L, 1L) %in% ech$y))
  # les cellules prelevees sont bien dans l'emprise
  xy <- terra::xyFromCell(couches, attr(ech, "cellules"))
  expect_lte(max(xy[, 1]), 40)

  libre <- dsr_echantillon(couches, route_ew(), buffer_pos = 2, buffer_neg = 10,
    n_max = 500, equilibre = FALSE)
  expect_lte(nrow(libre), 500)
  # prevalence reelle conservee : beaucoup plus de negatifs que de positifs
  expect_gt(sum(libre$y == 0L), sum(libre$y == 1L))
})

test_that("dsr_echantillon : aucune cellule pour une classe -> erreur", {
  skip_if_not_installed("terra"); skip_if_not_installed("sf")
  # buffer_neg couvrant toute la grille : plus aucun negatif a prelever.
  expect_error(
    dsr_echantillon(pile_apprentissage(), route_ew(), buffer_pos = 2,
      buffer_neg = 500),
    "Echantillon vide"
  )
})

test_that("dsr_apprendre_conductivite : entrees invalides -> erreurs", {
  expect_error(dsr_apprendre_conductivite("pas une table"), "data.frame")
  expect_error(dsr_apprendre_conductivite(data.frame(a = 1:4)), "y")
  expect_error(dsr_apprendre_conductivite(data.frame(y = c(0L, 1L))), "canal")
})

test_that("dsr_apprendre_conductivite : moteur ranger", {
  skip_if_not_installed("terra"); skip_if_not_installed("sf")
  skip_if_not_installed("ranger")
  set.seed(13)
  couches <- pile_apprentissage()
  ech <- dsr_echantillon(couches, route_ew(), buffer_pos = 2, buffer_neg = 10,
    n_max = 400)
  mod <- dsr_apprendre_conductivite(ech, methode = "ranger", k = 3,
    num.trees = 50)

  expect_s3_class(mod, "dsr_modele_conductivite")
  expect_identical(mod$methode, "ranger")
  expect_gt(mod$auc_vc, 0.9)

  p <- stats::predict(mod, couches)
  expect_s4_class(p, "SpatRaster")
  mm <- terra::minmax(p)
  expect_gte(mm[1], 0); expect_lte(mm[2], 1)
})

test_that("predict : sortie sur data.frame et canaux manquants", {
  skip_if_not_installed("terra"); skip_if_not_installed("sf")
  set.seed(14)
  couches <- pile_apprentissage()
  mod <- dsr_apprendre_conductivite(
    dsr_echantillon(couches, route_ew(), buffer_pos = 2, buffer_neg = 10,
      n_max = 300),
    k = NULL)

  p <- stats::predict(mod, data.frame(empreinte = c(1, 0), bruit = c(0.5, 0.5)))
  expect_length(p, 2)
  expect_true(all(p >= 0 & p <= 1))
  expect_gt(p[1], p[2])   # empreinte forte -> probabilite de route plus haute

  expect_error(stats::predict(mod, data.frame(bruit = 0.5)), "empreinte")
  expect_error(stats::predict(mod, "ni raster ni table"), "SpatRaster")
})

test_that("dsr_sigma_surf : method model passe par le modele", {
  skip_if_not_installed("terra"); skip_if_not_installed("sf")
  set.seed(15)
  couches <- pile_apprentissage()
  mod <- dsr_apprendre_conductivite(
    dsr_echantillon(couches, route_ew(), buffer_pos = 2, buffer_neg = 10,
      n_max = 400),
    k = NULL)

  ss <- dsr_sigma_surf(couches, method = "model", modele = mod, sigma_min = 0.1)
  expect_equal(names(ss), "sigma_surf")
  mm <- terra::minmax(ss)
  expect_gte(mm[1], 0.1); expect_lte(mm[2], 1)

  expect_error(dsr_sigma_surf(couches, method = "model"), "apprise")
  expect_error(dsr_conductivite(couches, method = "model", modele = "pas un modele"),
    "apprise")
})

test_that("AUC : une seule classe -> NA", {
  expect_true(is.na(.dsr_auc(c(1L, 1L, 1L), c(0.2, 0.5, 0.8))))
  expect_true(is.na(.dsr_auc(c(0L, 0L), c(0.2, 0.8))))
})
