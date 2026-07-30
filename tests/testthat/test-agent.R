# Carte synthetique : une route de conductivite 1 sur fond a 0.1, le long de
# y = 100. `trouee` coupe la route entre deux abscisses (conductivite ramenee au
# fond), ce qui simule une coupure de detection -- faux negatif du canal.
carte_route <- function(trouee = NULL, res = 2) {
  r <- terra::rast(nrows = 200 / res, ncols = 200 / res, xmin = 0, xmax = 200,
                   ymin = 0, ymax = 200, crs = "EPSG:2154")
  terra::values(r) <- 0.1
  xy <- terra::xyFromCell(r, seq_len(terra::ncell(r)))
  sur_route <- abs(xy[, 2] - 100) < 4
  r[sur_route] <- 1
  if (!is.null(trouee)) {
    r[sur_route & xy[, 1] > trouee[1] & xy[, 1] < trouee[2]] <- 0.1
  }
  r
}

amorce_ouest <- function() {
  sf::st_sfc(sf::st_linestring(cbind(c(10, 25), c(100, 100))), crs = "EPSG:2154")
}

x_final <- function(a) {
  co <- sf::st_coordinates(a$route)
  co[nrow(co), 1]
}


test_that("l'agent suit une route rectiligne jusqu'au bord de l'emprise", {
  a <- dsr_conduire(carte_route(), amorce_ouest(), portee = 40)

  expect_equal(a$arret, "hors_emprise")
  expect_gt(x_final(a), 185)
  # Il reste sur l'axe : l'ecart ne depasse pas la taille d'une cellule.
  co <- sf::st_coordinates(a$route)
  expect_lt(max(abs(co[, 2] - 100)), 2)
})


test_that("l'agent franchit une trouee de conductivite", {
  # C'est LA propriete qui distingue l'agent du squelette : une coupure de
  # detection de 20 m se franchit, parce que le cout admissible est module par
  # la profondeur du creux dans le profil angulaire et non par sa seule valeur.
  a <- dsr_conduire(carte_route(trouee = c(90, 110)), amorce_ouest(), portee = 40)

  expect_equal(a$arret, "hors_emprise")
  expect_gt(x_final(a), 180)
})


test_that("l'agent s'arrete quand la route s'arrete vraiment", {
  # Meme mecanique que ci-dessus, mais la route ne reprend jamais : il ne faut
  # pas confondre tolerance a la trouee et hors-piste.
  a <- dsr_conduire(carte_route(trouee = c(90, 200)), amorce_ouest(), portee = 40)

  expect_equal(a$arret, "trouee_trop_longue")
  # Les pas engages dans la trouee sont retires : la route rendue ne depasse
  # pas sensiblement la fin de la route reelle.
  expect_lt(x_final(a), 110)
})


test_that("l'agent s'arrete en rejoignant un reseau deja vectorise", {
  reseau <- sf::st_sfc(sf::st_linestring(cbind(c(150, 150), c(20, 180))),
                       crs = "EPSG:2154")
  a <- dsr_conduire(carte_route(), amorce_ouest(), reseau = reseau, portee = 40)

  expect_equal(a$arret, "reseau_rejoint")
  # Il s'arrete au contact du tampon (10 m par defaut), pas 40 m avant.
  expect_gt(x_final(a), 125)
  expect_lt(x_final(a), 145)
})


test_that("l'agent signale les embranchements sans les suivre", {
  r <- terra::rast(nrows = 150, ncols = 150, xmin = 0, xmax = 300, ymin = 0,
                   ymax = 300, crs = "EPSG:2154")
  terra::values(r) <- 0.1
  xy <- terra::xyFromCell(r, seq_len(terra::ncell(r)))
  r[abs(xy[, 2] - 150) < 4] <- 1                                   # tronc
  r[xy[, 1] >= 150 & abs((xy[, 2] - 150) - (xy[, 1] - 150)) < 5] <- 1  # branche a 45 deg

  a <- dsr_conduire(r, sf::st_sfc(sf::st_linestring(cbind(c(10, 30), c(150, 150))),
                                  crs = "EPSG:2154"), portee = 40)

  expect_false(is.null(a$amorces))
  expect_equal(length(a$amorces), 1L)
  # L'amorce part de la jonction, a (150, 150).
  d <- sf::st_coordinates(a$amorces)[1, 1:2]
  expect_lt(sqrt(sum((d - c(150, 150))^2)), 15)
})


test_that("dsr_conduire refuse une amorce non orientee", {
  r <- carte_route()
  pt <- sf::st_sfc(sf::st_point(c(10, 100)), crs = "EPSG:2154")
  expect_error(dsr_conduire(r, pt), "LINESTRING")
  expect_error(dsr_conduire(list(), amorce_ouest()), "SpatRaster")
})


test_that("le champ de cout est un Dijkstra un-vers-tous complet", {
  r <- terra::rast(nrows = 30, ncols = 30, xmin = 0, xmax = 60, ymin = 0,
                   ymax = 60, crs = "EPSG:2154")
  terra::values(r) <- 1
  champ <- .dsr_champ_cout(r, c(30, 30))

  expect_s4_class(champ, "SpatRaster")
  # Aucune cellule laissee inatteinte : c'est ce que garantit la destination
  # hors grille (le tas se vide au lieu de s'arreter a la cible).
  expect_false(any(is.na(terra::values(champ))))
  # Conductivite uniforme : le cout croit avec la distance euclidienne.
  expect_equal(terra::extract(champ, cbind(30, 30))[, 1], 0)
  c10 <- terra::extract(champ, cbind(40, 30))[, 1]
  c20 <- terra::extract(champ, cbind(50, 30))[, 1]
  expect_gt(c20, c10)
  expect_equal(c10, 10, tolerance = 0.1)

  # Depart sur une cellule interdite : pas de champ.
  r[terra::cellFromXY(r, cbind(30, 30))] <- NA
  expect_null(.dsr_champ_cout(r, c(30, 30)))
})


test_that("l'echantillonnage angulaire est symetrique et couvre le champ de vision", {
  a <- .dsr_angles(resolution = 2, portee = 40, fov = 160)
  expect_true(0 %in% a)
  expect_equal(a, -rev(a))
  expect_lte(max(a) * 180 / pi, 80)
  expect_true(all(diff(a) > 0))
  # Une portee plus grande donne un pas angulaire plus fin.
  expect_gt(length(.dsr_angles(2, 100, 160)), length(a))
})


test_that("la moyenne mobile lisse sans decaler ni raccourcir", {
  x <- c(1, 5, 1, 5, 1, 5, 1)
  expect_equal(.dsr_moyenne_mobile(x, 1), x)
  liss <- .dsr_moyenne_mobile(x, 3)
  expect_length(liss, length(x))
  expect_lt(diff(range(liss)), diff(range(x)))
  # Une constante reste constante (pas d'effet de bord).
  expect_equal(.dsr_moyenne_mobile(rep(7, 10), 5), rep(7, 10))
})


test_that("les minima du profil de cout trouvent les directions roulables", {
  # Profil a deux creux nets : deux directions praticables.
  ang <- seq(-1, 1, length.out = 61)
  cout <- 300 - 200 * exp(-((ang + 0.5)^2) / 0.01) - 150 * exp(-((ang - 0.4)^2) / 0.01)
  m <- .dsr_minima_cout(cout, cout_max = 200)

  expect_equal(nrow(m), 2L)
  expect_true(all(diff(m$cout) >= 0))          # trie par cout croissant
  expect_lt(abs(ang[m$idx[1]] - (-0.5)), 0.1)  # le meilleur est le creux profond
  expect_true(all(m$profondeur > 0))

  # Profil plat : aucune direction ne se distingue.
  expect_null(.dsr_minima_cout(rep(500, 61), cout_max = 200))
  # Profil trop court pour etre exploitable.
  expect_null(.dsr_minima_cout(c(1, 2, 3), cout_max = 200))
})
