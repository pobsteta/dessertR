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


# --- Indice de detection (lot 7) ---------------------------------------------

test_that("dsr_indice_detection : sigma_geo seul est rendu tel quel", {
  skip_if_not_installed("terra")
  sg <- terra::rast(nrows = 10, ncols = 10, xmin = 0, xmax = 10, ymin = 0,
    ymax = 10, crs = "EPSG:2154")
  terra::values(sg) <- seq(0.05, 0.95, length.out = terra::ncell(sg))
  p <- dsr_indice_detection(sg)
  expect_equal(names(p), "p_desserte")
  expect_equal(terra::values(p, mat = FALSE), terra::values(sg, mat = FALSE),
    tolerance = 1e-6)
})

test_that("dsr_indice_detection : le canal de surface fait basculer la decision", {
  skip_if_not_installed("terra")
  sg <- terra::rast(nrows = 10, ncols = 10, xmin = 0, xmax = 10, ymin = 0,
    ymax = 10, crs = "EPSG:2154")
  terra::values(sg) <- 0.9              # empreinte forte partout
  ss <- terra::rast(sg); terra::values(ss) <- 0.1 # mais emprise refermee

  p <- dsr_indice_detection(sg, sigma_surf = ss)
  # A poids surf = 0,5 (defaut mesure), la moyenne geometrique ponderee rend
  # exp((log(0.9) + 0.5 * log(0.1)) / 1.5) = 0,433 : la trace fossile reste
  # ramenee sous le seuil de detection, sans que le canal ecrase le terrain.
  expect_equal(max(terra::values(p, mat = FALSE)), 0.433, tolerance = 1e-3)
  expect_lt(max(terra::values(p, mat = FALSE)), 0.6)
  expect_equal(nrow(dsr_vectoriser(p, seuil = 0.6, methode = "squelette")), 0)
})

test_that("dsr_indice_detection : la reference est masquee, l'emprise restreint", {
  skip_if_not_installed("terra"); skip_if_not_installed("sf")
  sg <- sigma_avec_piste()
  p <- dsr_indice_detection(sg, reference = ref_ew(), buffer_ref = 8)
  xy <- terra::xyFromCell(p, seq_len(terra::ncell(p)))
  expect_true(all(is.na(terra::values(p, mat = FALSE)[abs(xy[, 2] - 20) < 5])))

  emp <- sf::st_sf(geometry = sf::st_sfc(sf::st_polygon(list(cbind(
    c(0, 40, 40, 0, 0), c(0, 0, 40, 40, 0)))), crs = 2154))
  pc <- dsr_indice_detection(sg, emprise = emp)
  expect_true(all(is.na(terra::values(pc, mat = FALSE)[xy[, 1] > 45])))
})

test_that("dsr_indice_detection : aucun poids positif -> erreur", {
  skip_if_not_installed("terra")
  sg <- terra::rast(nrows = 5, ncols = 5, xmin = 0, xmax = 5, ymin = 0, ymax = 5,
    crs = "EPSG:2154")
  terra::values(sg) <- 0.5
  expect_error(dsr_indice_detection(sg, poids = c(geo = 0)), "Aucun canal")
})


# --- Vectoriseur enfichable (lot 7) ------------------------------------------

reseau_en_te <- function(n = 80) {
  r <- terra::rast(nrows = n, ncols = n, xmin = 0, xmax = n, ymin = 0, ymax = n,
    crs = "EPSG:2154")
  terra::values(r) <- 0.1
  xy <- terra::xyFromCell(r, seq_len(terra::ncell(r)))
  r[abs(xy[, 2] - 40) < 1.5 & xy[, 1] > 10 & xy[, 1] < 70] <- 0.9 # barre
  r[abs(xy[, 1] - 40) < 1.5 & xy[, 2] > 40 & xy[, 2] < 70] <- 0.9 # embranchement
  r
}

test_that("dsr_vectoriser : le squelette conserve les embranchements, l'ACP les ecrase", {
  skip_if_not_installed("terra"); skip_if_not_installed("sf")
  p <- reseau_en_te()
  sq <- dsr_vectoriser(p, methode = "squelette", long_min = 10, simplifier = 0)
  acp <- dsr_vectoriser(p, methode = "acp", long_min = 10, simplifier = 0)

  expect_s3_class(sq, "sf")
  expect_gte(nrow(sq), 3)                 # les trois branches du T
  expect_lt(nrow(acp), nrow(sq))          # une composante -> au plus une ligne
  expect_identical(attr(sq, "methode"), "squelette")
})

test_that("dsr_vectoriser : les aretes du squelette partagent le noeud d'embranchement", {
  skip_if_not_installed("terra"); skip_if_not_installed("sf")
  skip_if_not_installed("igraph")
  sq <- dsr_vectoriser(reseau_en_te(), methode = "squelette", long_min = 10,
    simplifier = 0)
  # la contraction des grappes laisse les extremites a un pixel les unes des
  # autres : c'est dsr_coller_noeuds() qui les ramene sur un noeud commun.
  res <- dsr_reseau(sq, tol_noeud = 3, largeur_dedupe = 1)
  expect_equal(res$resume$n_composants, 1) # un seul reseau, pas trois morceaux
})

test_that("dsr_vectoriser : une piste aux bords bruites reste d'un seul tenant", {
  skip_if_not_installed("terra"); skip_if_not_installed("sf")
  set.seed(7)
  n <- 60; m <- 200
  r <- terra::rast(nrows = n, ncols = m, xmin = 0, xmax = m, ymin = 0, ymax = n,
    crs = "EPSG:2154")
  v <- matrix(0, n, m)
  for (j in 6:195) {
    centre <- 30 + round(3 * sin(j / 25))
    demi <- 2 + sample(0:1, 1)
    v[(centre - demi):(centre + demi), j] <- 1
    # bavures de bord : ce que donne une binarisation reelle
    if (stats::runif(1) < 0.18) v[centre - demi - 1L, j] <- 1
    if (stats::runif(1) < 0.18) v[centre + demi + 1L, j] <- 1
  }
  terra::values(r) <- as.vector(t(v))

  det <- dsr_vectoriser(r, seuil = 0.5, methode = "squelette", long_min = 30,
    elaguer = 5, simplifier = 0)
  expect_equal(nrow(det), 1)      # une piste, pas des dizaines de troncons
  expect_gt(det$longueur[1], 150)

  # sans nettoyage du graphe, la meme piste part en morceaux
  brut <- dsr_vectoriser(r, seuil = 0.5, methode = "squelette", long_min = 30,
    elaguer = 0, simplifier = 0)
  expect_gt(nrow(brut), nrow(det))
})

test_that("dsr_vectoriser : long_min filtre, simplifier allege la geometrie", {
  skip_if_not_installed("terra"); skip_if_not_installed("sf")
  p <- reseau_en_te()
  expect_equal(nrow(dsr_vectoriser(p, methode = "squelette", long_min = 1000)), 0)

  brut <- dsr_vectoriser(p, methode = "squelette", long_min = 10, simplifier = 0)
  lisse <- dsr_vectoriser(p, methode = "squelette", long_min = 10, simplifier = 2)
  expect_lte(nrow(sf::st_coordinates(lisse)), nrow(sf::st_coordinates(brut)))
})

test_that("dsr_vectoriser : \"vecnet\" est devenu un synonyme de \"agent\"", {
  skip_if_not_installed("terra")
  # Le paquet externe `vecnet` a ete remplace par l'agent conducteur natif. Le
  # nom reste accepte pour ne pas casser le code existant, mais il ne charge
  # plus rien : il ne doit ni echouer, ni dependre de la presence du paquet.
  p <- reseau_en_te(20)
  expect_message(v <- dsr_vectoriser(p, methode = "vecnet", long_min = 10),
                 "agent")
  expect_identical(attr(v, "methode"), "agent")
})


# --- Regimes (lot 7) ---------------------------------------------------------

test_that("dsr_detecter : regime corridor sans emprise -> erreur", {
  skip_if_not_installed("terra")
  expect_error(dsr_detecter(sigma_avec_piste(), regime = "corridor"), "emprise")
})

test_that("dsr_detecter : regime corridor restreint la detection a l'emprise", {
  skip_if_not_installed("terra"); skip_if_not_installed("sf")
  emp <- sf::st_sf(geometry = sf::st_sfc(sf::st_polygon(list(cbind(
    c(0, 40, 40, 0, 0), c(0, 0, 80, 80, 0)))), crs = 2154))
  det <- dsr_detecter(sigma_avec_piste(), reference = ref_ew(), buffer_ref = 8,
    long_min = 10, regime = "corridor", emprise = emp)
  if (nrow(det) > 0) {
    expect_lte(max(sf::st_coordinates(det)[, 1]), 41)
  }
})



# --- Garde-fous et canaux secondaires (lot 7) --------------------------------

test_that("dsr_indice_detection : entrees invalides -> erreurs", {
  skip_if_not_installed("terra")
  expect_error(dsr_indice_detection("pas un raster"), "SpatRaster")

  sg <- terra::rast(nrows = 6, ncols = 6, xmin = 0, xmax = 6, ymin = 0, ymax = 6,
    crs = "EPSG:2154")
  terra::values(sg) <- 0.5
  expect_error(dsr_indice_detection(c(sg, sg)), "mono-couche")
  expect_error(dsr_indice_detection(sg, poids = NULL), "Aucun canal")
  expect_error(dsr_indice_detection(sg, poids = c(geo = NA)), "Aucun canal")
})

test_that("dsr_indice_detection : la linearite entre par une rampe, pas en dur", {
  skip_if_not_installed("terra")
  sg <- terra::rast(nrows = 10, ncols = 10, xmin = 0, xmax = 10, ymin = 0,
    ymax = 10, crs = "EPSG:2154")
  terra::values(sg) <- 0.9
  ves <- terra::rast(sg)
  terra::values(ves) <- rep(seq(0, 1, length.out = 10), each = 10)

  p <- dsr_indice_detection(sg, vesselness = ves, seuil_vessel = 0.3)
  v <- terra::values(p, mat = FALSE)
  vv <- terra::values(ves, mat = FALSE)
  # sous le seuil de linearite l'indice s'effondre, au-dessus il remonte
  expect_lt(mean(v[vv <= 0.3]), mean(v[vv >= 0.8]))
  # une cellule sans aucune linearite tombe bien en dessous de sigma_geo
  expect_lt(min(v), min(terra::values(sg, mat = FALSE)))

  # poids nul sur la linearite : le canal ne contribue plus
  p0 <- dsr_indice_detection(sg, vesselness = ves,
    poids = c(geo = 1, surf = 2, vessel = 0))
  expect_equal(terra::values(p0, mat = FALSE), terra::values(sg, mat = FALSE),
    tolerance = 1e-6)
})

test_that("dsr_vectoriser : entrees invalides -> erreurs", {
  skip_if_not_installed("terra")
  expect_error(dsr_vectoriser("pas un raster"), "SpatRaster")
  r <- terra::rast(nrows = 6, ncols = 6, xmin = 0, xmax = 6, ymin = 0, ymax = 6,
    crs = "EPSG:2154")
  terra::values(r) <- 0.5
  expect_error(dsr_vectoriser(c(r, r)), "mono-couche")
})

test_that("dsr_vectoriser : methode acp sur un axe isole et allonge", {
  skip_if_not_installed("terra"); skip_if_not_installed("sf")
  n <- 80
  r <- terra::rast(nrows = n, ncols = n, xmin = 0, xmax = n, ymin = 0, ymax = n,
    crs = "EPSG:2154")
  terra::values(r) <- 0.1
  xy <- terra::xyFromCell(r, seq_len(terra::ncell(r)))
  r[abs((xy[, 2] - xy[, 1])) / sqrt(2) < 1.5] <- 0.9   # unique diagonale

  acp <- dsr_vectoriser(r, methode = "acp", long_min = 30, pas_bin = 5,
    ratio_min = 3, simplifier = 0)
  expect_equal(nrow(acp), 1)
  expect_identical(attr(acp, "methode"), "acp")
  co <- sf::st_coordinates(acp)[, 1:2]
  ang <- (atan2(co[nrow(co), 2] - co[1, 2], co[nrow(co), 1] - co[1, 1]) * 180 / pi) %% 180
  expect_lt(abs(ang - 45), 10)

  # une composante trop courte pour pas_bin ne donne aucune centre-ligne
  petit <- terra::rast(nrows = 20, ncols = 20, xmin = 0, xmax = 20, ymin = 0,
    ymax = 20, crs = "EPSG:2154")
  terra::values(petit) <- 0.1
  pxy <- terra::xyFromCell(petit, seq_len(terra::ncell(petit)))
  petit[abs(pxy[, 2] - 10) < 1 & pxy[, 1] > 8 & pxy[, 1] < 13] <- 0.9
  expect_equal(nrow(dsr_vectoriser(petit, methode = "acp", long_min = 3,
    pas_bin = 20, ratio_min = 2)), 0)
})

test_that("dsr_vectoriser : une boucle fermee sort en une arete unique", {
  skip_if_not_installed("terra"); skip_if_not_installed("sf")
  n <- 60
  r <- terra::rast(nrows = n, ncols = n, xmin = 0, xmax = n, ymin = 0, ymax = n,
    crs = "EPSG:2154")
  terra::values(r) <- 0.1
  xy <- terra::xyFromCell(r, seq_len(terra::ncell(r)))
  dedans <- xy[, 1] > 15 & xy[, 1] < 45 & xy[, 2] > 15 & xy[, 2] < 45
  trou   <- xy[, 1] > 20 & xy[, 1] < 40 & xy[, 2] > 20 & xy[, 2] < 40
  r[dedans & !trou] <- 0.9                             # anneau ferme

  # aucun pixel de degre != 2 : le tracage doit s'amorcer sur une arete libre
  boucle <- dsr_vectoriser(r, methode = "squelette", long_min = 20,
    simplifier = 0)
  expect_equal(nrow(boucle), 1)
  expect_gt(boucle$longueur[1], 80)
  co <- sf::st_coordinates(boucle)[, 1:2]
  expect_lt(sqrt(sum((co[1, ] - co[nrow(co), ])^2)), 2) # la boucle se referme
})


test_that("dsr_detecter transmet sigma_surf a l'agent comme franchissabilite", {
  skip_if_not_installed("terra")
  # Le canal de surface joue deux roles : preuve dans l'indice, contrainte pour
  # l'agent. Sans la transmission, le poids mesure de 0,5 laisserait l'agent
  # divaguer -- c'est le defaut que ce test verrouille.
  sg <- terra::rast(nrows = 100, ncols = 100, xmin = 0, xmax = 200, ymin = 0,
    ymax = 200, crs = "EPSG:2154")
  terra::values(sg) <- 0.2
  xy <- terra::xyFromCell(sg, seq_len(terra::ncell(sg)))
  sg[abs(xy[, 2] - 100) < 4] <- 0.95            # une route est-ouest
  ss <- terra::rast(sg); terra::values(ss) <- 0.9
  ss[xy[, 1] > 120] <- 0.05                      # emprise refermee a l'est
  ref <- sf::st_sfc(sf::st_linestring(cbind(c(10, 30), c(100, 100))),
    crs = "EPSG:2154")

  contraint <- dsr_detecter(sg, reference = ref, sigma_surf = ss,
    methode = "agent", seuil = 0.3, long_min = 10, buffer_ref = 0,
    regime = "complet")
  libre <- dsr_detecter(sg, reference = ref, sigma_surf = NULL,
    methode = "agent", seuil = 0.3, long_min = 10, buffer_ref = 0,
    regime = "complet")

  xmax <- function(d) if (nrow(d) == 0) NA_real_ else max(sf::st_coordinates(d)[, 1])
  # La contrainte retient l'agent a l'ouest de la zone refermee.
  expect_false(is.na(xmax(contraint)))
  expect_lt(xmax(contraint), xmax(libre))
})
