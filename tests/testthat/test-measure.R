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


test_that("la detection de fosse reste muette quand la fenetre est hors emprise", {
  # Tout troncon qui atteint le bord de dalle donne des profils partiellement
  # NA. Le verdict etait deja bon (aucun fosse) mais chaque station emettait un
  # avertissement, ce qui noie ceux qui comptent.
  offsets <- seq(-8, 8, by = 0.5)
  zi <- rep(NA_real_, length(offsets))
  centre <- abs(offsets) <= 2
  zi[centre] <- 100
  ic <- which.min(abs(offsets))
  expect_silent(
    m <- dessertR:::dsr_mesurer_profil(zi, offsets, ic, seuil_devers = 0.15,
      prof_fosse = 0.2)
  )
  expect_equal(m$fosses, 0L)
})


# Profil en travers de synthese : chaussee bombee de largeur W, fosse et talus
# de deblai d'un cote, remblai de l'autre -- la geometrie d'une route de
# montagne, ou le critere de fosse par simple descente echoue.
profil_montagne <- function(x, W = 4, bomb = 0.03, deblai = 0.6, remblai = -0.6,
                            fosse = 0.5, larg_fosse = 0.8) {
  h <- W / 2
  vapply(x, function(u) {
    if (abs(u) <= h) return(-bomb * abs(u))
    d <- abs(u) - h
    zb <- -bomb * h
    if (u < 0) {
      if (d <= larg_fosse) zb - fosse * sin(pi * d / larg_fosse)
      else zb + deblai * (d - larg_fosse)
    } else {
      zb + remblai * d
    }
  }, numeric(1))
}

test_that("un versant qui descend sans remonter n'est pas un fosse", {
  off <- seq(-8, 8, by = 0.25)
  ic <- which.min(abs(off))
  zi <- dessertR:::dsr_lisser(profil_montagne(off), 3)
  m <- dessertR:::dsr_mesurer_profil(zi, off, ic, seuil_devers = 0.15,
    prof_fosse = 0.2)
  # Fosse amont seulement : le remblai aval descend de plusieurs metres mais ne
  # remonte jamais. Le critere par simple descente en declarait deux.
  expect_equal(m$fosses, 1L)
})

test_that("un fosse de chaque cote est bien compte deux fois", {
  off <- seq(-8, 8, by = 0.25)
  ic <- which.min(abs(off))
  # Profil symetrique : le cote amont (fosse + deblai) mire des deux cotes.
  sym <- profil_montagne(-abs(off))
  zi <- dessertR:::dsr_lisser(sym, 3)
  m <- dessertR:::dsr_mesurer_profil(zi, off, ic, seuil_devers = 0.15,
    prof_fosse = 0.2)
  expect_equal(m$fosses, 2L)
})

test_that("aucun fosse n'est declare sur un deblai sec", {
  off <- seq(-8, 8, by = 0.25)
  ic <- which.min(abs(off))
  zi <- dessertR:::dsr_lisser(profil_montagne(off, fosse = 0), 3)
  m <- dessertR:::dsr_mesurer_profil(zi, off, ic, seuil_devers = 0.15,
    prof_fosse = 0.2)
  expect_equal(m$fosses, 0L)
})

test_that("dsr_measure rend les deux bords, et leur somme fait la largeur", {
  skip_if_not_installed("terra")
  skip_if_not_installed("sf")
  mnt <- terra::rast(nrows = 60, ncols = 60, xmin = 0, xmax = 60, ymin = 0,
    ymax = 60, resolution = 1, crs = "EPSG:2154")
  xy <- terra::xyFromCell(mnt, seq_len(terra::ncell(mnt)))
  # Plateforme plate de 4 m centree sur y = 30, talus de part et d'autre.
  d <- abs(xy[, 2] - 30)
  terra::values(mnt) <- ifelse(d <= 2, 100, 100 - 0.6 * (d - 2))
  tr <- sf::st_sf(geometry = sf::st_sfc(
    sf::st_linestring(cbind(c(5, 55), c(30, 30))), crs = 2154))
  m <- dsr_measure(tr, mnt, pas = 2, pas_travers = 0.25)
  expect_true(all(c("BORD_G", "BORD_D") %in% names(m$stations)))
  expect_equal(m$stations$BORD_G + m$stations$BORD_D,
    m$stations$LARGEUR_ROULABLE, tolerance = 1e-8)
  expect_true(all(m$stations$BORD_G > 0 & m$stations$BORD_D > 0))
})


# Profil avec ACCOTEMENT : chaussee bombee de largeur W, puis un accotement
# plus penche, puis le talus. C'est l'accotement que la methode "chaussee" doit
# retrancher et que "planeite" retient.
profil_accotement <- function(x, W = 4, bomb = 0.03, epaule = 1,
                              pente_epaule = -0.06, talus = -0.6) {
  h <- W / 2
  vapply(x, function(u) {
    a <- abs(u)
    if (a <= h) return(-bomb * a)
    d <- a - h
    zb <- -bomb * h
    if (d <= epaule) zb + pente_epaule * d
    else zb + pente_epaule * epaule + talus * (d - epaule)
  }, numeric(1))
}

mesurer <- function(z, methode, pt = 0.25) {
  off <- seq(-8, 8, by = pt)
  dessertR:::dsr_mesurer_profil(dessertR:::dsr_lisser(z, 3), off,
    which.min(abs(off)), 0.15, 0.2, methode = methode, zb = z)
}

test_that('"chaussee" retranche l accotement que "planeite" retient', {
  off <- seq(-8, 8, by = 0.25)
  z <- profil_accotement(off, W = 4, epaule = 1, pente_epaule = -0.06)
  plat <- mesurer(z, "planeite")
  ch <- mesurer(z, "chaussee")
  expect_gt(plat$largeur, 5)              # la plateforme inclut l accotement
  expect_equal(ch$largeur, 4, tolerance = 0.1)
  expect_equal(ch$bords_nets, 2L)         # rupture resolue des deux cotes
})

test_that('"chaussee" ne retranche rien quand il n y a pas d accotement', {
  off <- seq(-8, 8, by = 0.25)
  z <- profil_accotement(off, W = 4, epaule = 0)
  plat <- mesurer(z, "planeite")
  ch <- mesurer(z, "chaussee")
  expect_equal(ch$largeur, plat$largeur, tolerance = 1e-8)
  expect_equal(ch$bords_nets, 0L)
})

test_that('"chaussee" retombe sur la plateforme quand le bruit noie la rupture', {
  set.seed(3)
  off <- seq(-8, 8, by = 0.25)
  z <- profil_accotement(off, W = 4, epaule = 1) + rnorm(length(off), 0, 0.05)
  plat <- mesurer(z, "planeite")
  ch <- mesurer(z, "chaussee")
  # Mieux vaut rendre la plateforme, en le disant, qu inventer un bord.
  expect_equal(ch$largeur, plat$largeur, tolerance = 1e-8)
  expect_equal(ch$bords_nets, 0L)
})

test_that('"chaussee" suit la largeur reelle de la chaussee', {
  off <- seq(-8, 8, by = 0.25)
  l <- vapply(c(3, 4, 5), function(W) {
    mesurer(profil_accotement(off, W = W, epaule = 1), "chaussee")$largeur
  }, numeric(1))
  expect_equal(l, c(3, 4, 5), tolerance = 0.15)
})

test_that("dsr_measure expose BORDS_CHAUSSEE pour la seule methode chaussee", {
  skip_if_not_installed("terra")
  skip_if_not_installed("sf")
  mnt <- terra::rast(nrows = 60, ncols = 60, xmin = 0, xmax = 60, ymin = 0,
    ymax = 60, resolution = 0.5, crs = "EPSG:2154")
  xy <- terra::xyFromCell(mnt, seq_len(terra::ncell(mnt)))
  terra::values(mnt) <- 100 + profil_accotement(xy[, 2] - 30, W = 4, epaule = 1)
  tr <- sf::st_sf(geometry = sf::st_sfc(
    sf::st_linestring(cbind(c(5, 55), c(30, 30))), crs = 2154))
  expect_true("BORDS_CHAUSSEE" %in%
    names(dsr_measure(tr, mnt, pas = 2, pas_travers = 0.25)$stations))
  expect_false("BORDS_CHAUSSEE" %in%
    names(dsr_measure(tr, mnt, pas = 2, pas_travers = 0.25,
      methode_largeur = "planeite")$stations))
})

test_that('"chaussee" degrade proprement sur un profil sans chaussee', {
  off <- seq(-8, 8, by = 0.25)
  z <- rep(NA_real_, length(off))
  m <- mesurer(z, "chaussee")
  expect_equal(m$largeur, 0)
  expect_equal(m$bords_nets, 0L)
})


test_that("dsr_calibrer_largeur classe les methodes sur une verite connue", {
  skip_if_not_installed("terra")
  skip_if_not_installed("sf")
  # Chaussee de 4 m avec 1 m d'accotement a 6 % : "planeite" mesure la
  # plateforme, "chaussee" la chaussee. La verite terrain dit 4 m.
  mnt <- terra::rast(nrows = 120, ncols = 120, xmin = 0, xmax = 60, ymin = 0,
    ymax = 60, resolution = 0.5, crs = "EPSG:2154")
  xy <- terra::xyFromCell(mnt, seq_len(terra::ncell(mnt)))
  terra::values(mnt) <- 100 + profil_accotement(xy[, 2] - 30, W = 4, epaule = 1)
  lig <- sf::st_sfc(sf::st_linestring(cbind(c(5, 55), c(30, 30))), crs = 2154)
  tr <- sf::st_sf(geometry = lig)
  ref <- sf::st_sf(largeur_m = 4, geometry = lig)

  r <- dsr_calibrer_largeur(tr, mnt, ref, "largeur_m",
    grille = expand.grid(methode_largeur = c("chaussee", "planeite"),
      tol_planeite = 0.10, stringsAsFactors = FALSE),
    long_min = 30, pas_travers = 0.25)

  expect_equal(nrow(r), 2L)
  expect_true(all(c("n", "biais", "mae", "rmse") %in% names(r)))
  # Le tableau est trie par MAE croissante : "chaussee" doit sortir devant.
  expect_equal(r$methode_largeur[1], "chaussee")
  expect_lt(r$mae[1], r$mae[2])
})


test_that("dsr_calibrer_largeur stratifie par confiance du MNT", {
  skip_if_not_installed("terra")
  skip_if_not_installed("sf")
  # La stratification repond a « la largeur se degrade-t-elle la ou le sol est
  # mal vu ? ». Elle exige une couche de confiance ; sans elle, une seule ligne
  # par jeu de parametres.
  mnt <- terra::rast(nrows = 120, ncols = 120, xmin = 0, xmax = 60, ymin = 0,
    ymax = 60, resolution = 0.5, crs = "EPSG:2154")
  xy <- terra::xyFromCell(mnt, seq_len(terra::ncell(mnt)))
  terra::values(mnt) <- 100 + profil_accotement(xy[, 2] - 30, W = 4, epaule = 1)

  # Densite de points sol : faible sur la premiere moitie, forte sur la seconde.
  conf <- terra::rast(mnt)
  terra::values(conf) <- ifelse(xy[, 1] < 30, 1, 8)

  lig <- sf::st_sfc(sf::st_linestring(cbind(c(5, 55), c(30, 30))), crs = 2154)
  r <- dsr_calibrer_largeur(sf::st_sf(geometry = lig), mnt,
    sf::st_sf(largeur_m = 4, geometry = lig), "largeur_m",
    grille = data.frame(tol_planeite = 0.10),
    long_min = 30, pas_travers = 0.25, confiance = conf,
    seuils_confiance = c(0, 2, 5, Inf))

  # Deux strates peuplees (1 pt/m2 et 8 pt/m2), la troisieme vide est omise.
  expect_equal(nrow(r), 2L)
  expect_false(any(is.na(r$strate)))
  expect_equal(sum(r$n), 26L)
})

test_that("dsr_calibrer_largeur refuse un jeu sans largeur de reference", {
  skip_if_not_installed("terra")
  skip_if_not_installed("sf")
  # Cas tres concret : LARGEUR_DE_CHAUSSEE de la BD TOPO est frequemment vide
  # ou nulle sur Chemin et Sentier. Il n y a alors rien a quoi se comparer, et
  # mieux vaut le dire que rendre un tableau vide.
  mnt <- terra::rast(nrows = 40, ncols = 40, xmin = 0, xmax = 20, ymin = 0,
    ymax = 20, resolution = 0.5, crs = "EPSG:2154")
  terra::values(mnt) <- 100
  lig <- sf::st_sfc(sf::st_linestring(cbind(c(2, 18), c(10, 10))), crs = 2154)
  expect_error(
    dsr_calibrer_largeur(sf::st_sf(geometry = lig), mnt,
      sf::st_sf(largeur_m = 0, geometry = lig), "largeur_m",
      grille = data.frame(tol_planeite = 0.10), long_min = 5),
    "Aucune station appariee"
  )
})

test_that("dsr_measure ne rale pas sur un MNT sans valeur sous le trace", {
  skip_if_not_installed("terra")
  skip_if_not_installed("sf")
  mnt <- terra::rast(nrows = 40, ncols = 40, xmin = 0, xmax = 20, ymin = 0,
    ymax = 20, resolution = 0.5, crs = "EPSG:2154")
  terra::values(mnt) <- NA_real_
  tr <- sf::st_sf(geometry = sf::st_sfc(
    sf::st_linestring(cbind(c(2, 18), c(10, 10))), crs = 2154))
  expect_silent(m <- dsr_measure(tr, mnt, pas = 2))
  expect_true(is.na(m$resume$PENTE_LONG_MAX))
  expect_true(is.na(m$resume$PENTE_LONG_MOY))
})
