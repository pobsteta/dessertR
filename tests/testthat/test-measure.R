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


# --- Largeur : planeite contre gradient --------------------------------------

# Profil transversal de largeur CONNUE : plateforme bombee, fosses, talus.
# Sert de verite terrain de synthese pour departager les deux estimateurs.
# `bombement` est le devers de drainage, SYMETRIQUE (une route bombee n'a pas
# de devers net) ; `devers` est l'inclinaison d'ensemble, celle qui compte pour
# la stabilite. Les deux sont distincts et doivent le rester a la mesure.
profil_synthetique <- function(offsets, W = 4, camber = 0.03, devers = 0,
                               prof = 0.5, larg_fosse = 1, talus = 0.5,
                               bruit = 0) {
  a <- abs(offsets)
  z <- ifelse(a <= W / 2, -camber * a,
       ifelse(a <= W / 2 + larg_fosse,
              -camber * W / 2 - prof * sin(pi * (a - W / 2) / larg_fosse),
              -camber * W / 2 + talus * (a - W / 2 - larg_fosse)))
  z + devers * offsets + stats::rnorm(length(z), 0, bruit)
}

largeur_de <- function(methode, W = 4, camber = 0.03, bruit = 0, pt = 0.25,
                       liss = 3, n = 20) {
  offs <- seq(-8, 8, by = pt)
  ic <- which.min(abs(offs))
  mean(replicate(n, {
    zi <- dsr_lisser(profil_synthetique(offs, W = W, camber = camber,
      bruit = bruit), liss)
    dsr_mesurer_profil(zi, offs, ic, 0.15, 0.2, methode = methode)$largeur
  }))
}

test_that("planeite : biais faible et stable quand le bruit du MNT monte", {
  set.seed(1)
  for (bruit in c(0, 0.05, 0.10)) {
    expect_lt(abs(largeur_de("planeite", bruit = bruit) - 4), 0.6)
  }
})

test_that("planeite bat le gradient sur un profil de largeur connue", {
  set.seed(2)
  for (bruit in c(0.05, 0.10)) {
    plan <- abs(largeur_de("planeite", bruit = bruit) - 4)
    grad <- abs(largeur_de("gradient", bruit = bruit) - 4)
    expect_lt(plan, grad)
  }
})

test_that("planeite ne depend guere du pas transversal, le gradient si", {
  set.seed(3)
  pl <- vapply(c(0.1, 0.25, 0.5), function(pt) largeur_de("planeite", pt = pt),
    numeric(1))
  gr <- vapply(c(0.1, 0.25, 0.5), function(pt) largeur_de("gradient", pt = pt,
    bruit = 0.05), numeric(1))
  # c'est l'argument central : un seuil cale sur le gradient ne vaut que pour
  # un pas donne, donc n'est pas transferable.
  expect_lt(diff(range(pl)), diff(range(gr)))
})

test_that("planeite : le devers est restitue, le bombement ne le pollue pas", {
  offs <- seq(-8, 8, by = 0.25)
  ic <- which.min(abs(offs))
  mesure <- function(devers) {
    dsr_mesurer_profil(profil_synthetique(offs, devers = devers), offs, ic,
      0.15, 0.2, methode = "planeite")$devers
  }
  # bombement symetrique seul : aucun devers net
  expect_equal(mesure(0), 0, tolerance = 1e-6)
  expect_equal(mesure(0.04), 0.04, tolerance = 0.005)
  expect_equal(mesure(0.08), 0.08, tolerance = 0.005)
})

test_that("planeite : tol_planeite doit couvrir la fleche du bombement", {
  offs <- seq(-8, 8, by = 0.25)
  ic <- which.min(abs(offs))
  larg <- function(W, bomb, tol) {
    dsr_mesurer_profil(profil_synthetique(offs, W = W, camber = bomb), offs, ic,
      0.15, 0.2, methode = "planeite", tol_planeite = tol)$largeur
  }
  # fleche = bombement * W/2. Sous la tolerance, la largeur est juste.
  expect_lt(abs(larg(6, 0.03, 0.10) - 6), 0.5)   # fleche 0,09 < 0,10
  # au-dessus, la plateforme est tronquee -- et relever la tolerance la retrouve.
  expect_lt(larg(6, 0.06, 0.10), 5)              # fleche 0,18 > 0,10
  expect_lt(abs(larg(6, 0.06, 0.20) - 6), 0.5)   # fleche 0,18 < 0,20
})

test_that("dsr_measure : les deux methodes de largeur sont selectionnables", {
  skip_if_not_installed("terra"); skip_if_not_installed("sf")
  mnt <- road_mnt(n = 80, fun = function(d) ifelse(abs(d) <= 5, 100,
    100 + 3 * (abs(d) - 5)))
  tr <- sf::st_sf(geometry = sf::st_sfc(
    sf::st_linestring(cbind(c(5, 75), c(40, 40))), crs = 2154))
  for (meth in c("planeite", "gradient")) {
    m <- dsr_measure(tr, mnt, pas = 2, demi_largeur = 10, pas_travers = 0.25,
      liss_travers = 1, methode_largeur = meth)
    expect_gt(median(m$stations$LARGEUR_ROULABLE), 6)
    expect_lt(median(m$stations$LARGEUR_ROULABLE), 11)
  }
})


# --- Rayon de courbure : cercle des moindres carres --------------------------

test_that("le cercle MC retrouve un rayon connu la ou trois stations echouent", {
  skip_if_not_installed("terra"); skip_if_not_installed("sf")
  th <- seq(0, pi / 3, length.out = 400)
  arc <- cbind(60 * sin(th) + 20, 60 * cos(th))
  quant <- unique(round(arc))            # ce que rend un trace vectorise

  r3 <- dsr_rayon_courbure_vec(quant)
  r30 <- .dsr_rayon_cercle(quant, 30)
  r50 <- .dsr_rayon_cercle(quant, 50)
  med <- function(r) stats::median(r[is.finite(r)])

  expect_lt(med(r3), 10)                 # trois stations : effondre a ~2 m
  expect_gt(med(r30), med(r3))
  expect_gt(med(r50), med(r30))
  expect_lt(abs(med(r50) - 60), 15)      # base 50 m : proche du rayon vrai
})

test_that(".dsr_rayon_cercle : alignement et fenetre trop courte -> Inf", {
  droit <- cbind(seq(0, 100, by = 2), 30)
  expect_true(all(is.infinite(.dsr_rayon_cercle(droit, 30))))
  expect_true(all(is.infinite(.dsr_rayon_cercle(droit, 0))))
  expect_true(all(is.infinite(.dsr_rayon_cercle(cbind(1:3, 1:3), 30))))
})

test_that("dsr_measure : base_courbure = 0 revient aux trois stations", {
  skip_if_not_installed("terra"); skip_if_not_installed("sf")
  mnt <- road_mnt(n = 80, fun = function(d) 100 + 0 * d)
  x <- seq(5, 75, by = 2); y <- 40 + 15 * sin(pi * (x - 5) / 70)
  tr <- sf::st_sf(geometry = sf::st_sfc(sf::st_linestring(cbind(x, y)),
    crs = 2154))
  m3 <- dsr_measure(tr, mnt, pas = 2, base_courbure = 0)
  m30 <- dsr_measure(tr, mnt, pas = 2, base_courbure = 30)
  expect_true(is.finite(m3$resume$RAYON_COURBURE_MIN))
  expect_true(is.finite(m30$resume$RAYON_COURBURE_MIN))
  expect_true("RAYON_COURBURE_P05" %in% names(m30$resume))
  expect_gte(m30$resume$RAYON_COURBURE_P05, m30$resume$RAYON_COURBURE_MIN)
})


# --- Calibrage ---------------------------------------------------------------

test_that("dsr_calibrer_largeur : balaie la grille et classe par MAE", {
  skip_if_not_installed("terra"); skip_if_not_installed("sf")
  mnt <- road_mnt(n = 80, fun = function(d) ifelse(abs(d) <= 5, 100,
    100 + 3 * (abs(d) - 5)))
  tr <- sf::st_sf(geometry = sf::st_sfc(
    sf::st_linestring(cbind(c(5, 75), c(40, 40))), crs = 2154))
  ref <- sf::st_sf(largeur_m = 10, geometry = sf::st_sfc(
    sf::st_linestring(cbind(c(5, 75), c(40, 40))), crs = 2154))

  res <- dsr_calibrer_largeur(tr, mnt, ref, "largeur_m",
    grille = data.frame(methode_largeur = c("planeite", "gradient"),
      stringsAsFactors = FALSE),
    pas = 4, demi_largeur = 10, pas_travers = 0.25, liss_travers = 1)

  expect_s3_class(res, "data.frame")
  expect_true(all(c("n", "biais", "mae", "rmse", "med_dsr", "med_ref") %in% names(res)))
  expect_equal(nrow(res), 2)
  expect_false(is.unsorted(res$mae))     # trie du meilleur au pire
  expect_true(all(res$n > 0))
  expect_equal(unique(res$med_ref), 10)
})

test_that("dsr_calibrer_largeur : garde-fous", {
  skip_if_not_installed("terra"); skip_if_not_installed("sf")
  mnt <- road_mnt(fun = function(d) 100 + 0 * d)
  tr <- ligne_ew()
  ref <- sf::st_sf(largeur_m = 5, geometry = sf::st_geometry(tr))
  expect_error(dsr_calibrer_largeur(tr, mnt, ref, "absente"), "absente")
  expect_error(dsr_calibrer_largeur("pas un sf", mnt, ref, "largeur_m"), "sf")
})
