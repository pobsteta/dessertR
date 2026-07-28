test_that(".dsr_run_centre trouve la plage contenant le centre", {
  offsets <- seq(-4, 4, by = 1)      # 9 echantillons, centre en 5
  v <- c(10, 10, 0, 0, 0, 0, 0, 10, 10)
  r <- dessertR:::.dsr_run_centre(v, offsets, 5L, 2, sens = "sous")
  expect_equal(r$il, 3L)
  expect_equal(r$ir, 7L)
  expect_false(r$tronque)
})

test_that(".dsr_run_centre interpole le bord entre deux echantillons", {
  # Bord franc : 0 puis 10 sur 1 m, seuil 2 -> croisement a 20 % du pas.
  offsets <- seq(-4, 4, by = 1)
  v <- c(10, 10, 0, 0, 0, 0, 0, 10, 10)
  r <- dessertR:::.dsr_run_centre(v, offsets, 5L, 2, sens = "sous")
  expect_equal(r$g, -2 - 0.2, tolerance = 1e-8)
  expect_equal(r$d, 2 + 0.2, tolerance = 1e-8)
  expect_equal(r$largeur, 4.4, tolerance = 1e-8)
})

test_that(".dsr_run_centre rend une largeur nulle si le centre est ferme", {
  offsets <- seq(-4, 4, by = 1)
  v <- rep(10, 9)
  r <- dessertR:::.dsr_run_centre(v, offsets, 5L, 2, sens = "sous")
  expect_equal(r$largeur, 0)
  expect_false(r$tronque)
})

test_that(".dsr_run_centre signale une plage qui sort du profil", {
  offsets <- seq(-4, 4, by = 1)
  r <- dessertR:::.dsr_run_centre(rep(0, 9), offsets, 5L, 2, sens = "sous")
  expect_true(r$tronque)
})

test_that(".dsr_run_centre gere le sens inverse", {
  offsets <- seq(-4, 4, by = 1)
  v <- c(0, 0, 10, 10, 10, 10, 10, 0, 0)
  r <- dessertR:::.dsr_run_centre(v, offsets, 5L, 2, sens = "sur")
  expect_equal(r$il, 3L)
  expect_equal(r$ir, 7L)
})

test_that(".dsr_run_centre ignore les NA", {
  offsets <- seq(-4, 4, by = 1)
  v <- c(NA, 0, 0, 0, 0, 0, NA, 0, 0)
  r <- dessertR:::.dsr_run_centre(v, offsets, 5L, 2, sens = "sous")
  # La plage s'arrete au NA de part et d'autre : 2..6
  expect_equal(r$il, 2L)
  expect_equal(r$ir, 6L)
  expect_false(r$tronque)
})


test_that(".dsr_run_centre ne fabrique pas un bord depuis une valeur infinie", {
  # Une cellule a Inf passe le test de NA mais rend un ecart non fini : on doit
  # retomber sur l'echantillon, pas produire un bord aberrant.
  offsets <- seq(-4, 4, by = 1)
  v <- c(10, 10, 0, 0, 0, 0, 0, Inf, 10)
  r <- dessertR:::.dsr_run_centre(v, offsets, 5L, 2, sens = "sous")
  expect_equal(r$d, offsets[7])
  expect_true(is.finite(r$largeur))
})


test_that(".dsr_otsu separe deux modes", {
  set.seed(1)
  bas <- rnorm(500, 0.05, 0.01)
  haut <- rnorm(500, 0.75, 0.05)
  s <- dessertR:::.dsr_otsu(c(bas, haut))
  # Ce qui compte n'est pas ou tombe le seuil (Otsu penche vers le mode le plus
  # resserre quand les variances different) mais qu'il classe correctement. Une
  # queue de distribution du mode bas passe de l'autre cote : c'est attendu.
  expect_true(s > mean(bas) && s < mean(haut))
  expect_gt(mean(c(bas < s, haut >= s)), 0.99)
})

test_that(".dsr_otsu supporte les cas degeneres", {
  expect_equal(dessertR:::.dsr_otsu(rep(0.4, 100)), 0.4)
  expect_true(is.na(dessertR:::.dsr_otsu(numeric(0))))
  expect_true(is.na(dessertR:::.dsr_otsu(c(NA_real_, Inf))))
})

test_that(".dsr_otsu ignore les valeurs non finies", {
  x <- c(rnorm(300, 0, 0.01), rnorm(300, 1, 0.01), NA, Inf, -Inf)
  expect_true(is.finite(dessertR:::.dsr_otsu(x)))
})


test_that("dsr_ndvi calcule le rapport attendu", {
  skip_if_not_installed("terra")
  irc <- terra::rast(xmin = 0, xmax = 10, ymin = 0, ymax = 10,
    resolution = 1, nlyrs = 3, crs = "EPSG:2154")
  terra::values(irc) <- cbind(rep(200, 100), rep(50, 100), rep(60, 100))
  nd <- dsr_ndvi(irc)
  expect_equal(names(nd), "ndvi")
  expect_equal(unname(terra::global(nd, "mean")[1, 1]), 150 / 250, tolerance = 1e-9)
})

test_that("dsr_ndvi est insensible a l'echelle radiometrique", {
  skip_if_not_installed("terra")
  faire <- function(k) {
    r <- terra::rast(xmin = 0, xmax = 4, ymin = 0, ymax = 4,
      resolution = 1, nlyrs = 2, crs = "EPSG:2154")
    terra::values(r) <- cbind(rep(200 * k, 16), rep(50 * k, 16))
    unname(terra::global(dsr_ndvi(r), "mean")[1, 1])
  }
  expect_equal(faire(1), faire(37), tolerance = 1e-9)
})

test_that("dsr_ndvi met NA la ou PIR + Rouge s'annule", {
  skip_if_not_installed("terra")
  irc <- terra::rast(xmin = 0, xmax = 2, ymin = 0, ymax = 2,
    resolution = 1, nlyrs = 2, crs = "EPSG:2154")
  terra::values(irc) <- cbind(c(0, 10, 10, 10), c(0, 5, 5, 5))
  expect_equal(sum(is.na(terra::values(dsr_ndvi(irc)))), 1L)
})

test_that("dsr_ndvi refuse une entree a une seule bande", {
  skip_if_not_installed("terra")
  r <- terra::rast(xmin = 0, xmax = 2, ymin = 0, ymax = 2, resolution = 1)
  terra::values(r) <- 1
  expect_error(dsr_ndvi(r), "au moins deux bandes")
  expect_error(dsr_ndvi("pas un raster"), "SpatRaster")
})

test_that("dsr_ndvi refuse un choix de bandes qui n'en designe pas deux", {
  skip_if_not_installed("terra")
  irc <- terra::rast(xmin = 0, xmax = 2, ymin = 0, ymax = 2,
    resolution = 1, nlyrs = 3, crs = "EPSG:2154")
  terra::values(irc) <- cbind(rep(200, 4), rep(50, 4), rep(60, 4))
  expect_error(dsr_ndvi(irc, bandes = 1), "exactement deux bandes")
  expect_error(dsr_ndvi(irc, bandes = 1:3), "exactement deux bandes")
})


# Corridor de synthese : trouee de 6 m de large centree sur y = 30.
couloir_chm <- function(res = 0.5, demi_trouee = 3, h = 20) {
  r <- terra::rast(xmin = 0, xmax = 60, ymin = 0, ymax = 60,
    resolution = res, crs = "EPSG:2154")
  xy <- terra::xyFromCell(r, seq_len(terra::ncell(r)))
  terra::values(r) <- ifelse(abs(xy[, 2] - 30) <= demi_trouee, 0, h)
  r
}

trace_droit <- function() {
  sf::st_sf(geometry = sf::st_sfc(
    sf::st_linestring(cbind(c(5, 55), c(30, 30))), crs = 2154))
}

test_that("dsr_gabarit_lateral retrouve la largeur de trouee", {
  skip_if_not_installed("terra")
  skip_if_not_installed("sf")
  g <- dsr_gabarit_lateral(trace_droit(), couloir_chm(), pas_travers = 0.25)
  # La maille arrondit le bord : on tolere un demi-pixel de chaque cote.
  expect_equal(stats::median(g$LARGEUR_DEGAGEE), 6, tolerance = 0.15)
  expect_false(any(g$TRONQUE))
})

test_that("dsr_gabarit_lateral est monotone en largeur de trouee", {
  skip_if_not_installed("terra")
  skip_if_not_installed("sf")
  tr <- trace_droit()
  l <- vapply(c(1.5, 3, 5), function(d) {
    stats::median(dsr_gabarit_lateral(tr, couloir_chm(demi_trouee = d),
      pas_travers = 0.25)$LARGEUR_DEGAGEE)
  }, numeric(1))
  expect_true(all(diff(l) > 0))
})

test_that("dsr_gabarit_lateral rend les deux cotes separement", {
  skip_if_not_installed("terra")
  skip_if_not_installed("sf")
  # Trouee dissymetrique : degagee de y = 28 a y = 34, axe en y = 30.
  r <- terra::rast(xmin = 0, xmax = 60, ymin = 0, ymax = 60,
    resolution = 0.5, crs = "EPSG:2154")
  xy <- terra::xyFromCell(r, seq_len(terra::ncell(r)))
  terra::values(r) <- ifelse(xy[, 2] >= 28 & xy[, 2] <= 34, 0, 20)
  g <- dsr_gabarit_lateral(trace_droit(), r, pas_travers = 0.25)
  # Un cote est nettement plus ferme que l'autre ; la somme fait la largeur.
  expect_gt(abs(stats::median(g$DEGAGE_D) - stats::median(g$DEGAGE_G)), 1)
  expect_equal(stats::median(g$DEGAGE_G + g$DEGAGE_D),
    stats::median(g$LARGEUR_DEGAGEE), tolerance = 1e-6)
})

test_that("dsr_gabarit_lateral signale une trouee plus large que le profil", {
  skip_if_not_installed("terra")
  skip_if_not_installed("sf")
  r <- couloir_chm(demi_trouee = 30) # tout est degage
  g <- dsr_gabarit_lateral(trace_droit(), r, demi_largeur = 4)
  expect_true(all(g$TRONQUE))
})

test_that("dsr_gabarit_lateral chiffre le surplomb quand la trouee est etroite", {
  skip_if_not_installed("terra")
  skip_if_not_installed("sf")
  # Trouee de 3 m sous une chaussee de 5 m : 2 m d'emprise recouverte.
  g <- dsr_gabarit_lateral(trace_droit(), couloir_chm(demi_trouee = 1.5),
    largeur = 5, pas_travers = 0.25)
  expect_equal(stats::median(g$SURPLOMB), 2, tolerance = 0.2)
  expect_true(all(is.finite(g$HAUT_SURPLOMB)))
  expect_equal(stats::median(g$HAUT_SURPLOMB), 20, tolerance = 1e-6)
})

test_that("dsr_gabarit_lateral ne declare aucun surplomb si la trouee couvre la chaussee", {
  skip_if_not_installed("terra")
  skip_if_not_installed("sf")
  g <- dsr_gabarit_lateral(trace_droit(), couloir_chm(demi_trouee = 5),
    largeur = 3, pas_travers = 0.25)
  expect_true(all(g$SURPLOMB == 0))
  expect_true(all(is.infinite(g$HAUT_SURPLOMB)))
})

test_that("dsr_gabarit_lateral accepte les stations de dsr_measure", {
  skip_if_not_installed("terra")
  skip_if_not_installed("sf")
  tr <- trace_droit()
  chm <- couloir_chm(demi_trouee = 1.5)
  n <- nrow(dsr_gabarit_lateral(tr, chm)) # meme decoupage, meme `pas`
  st <- sf::st_sf(LARGEUR_ROULABLE = rep(5, n),
    geometry = sf::st_sfc(rep(list(sf::st_point(c(0, 0))), n), crs = 2154))
  g <- dsr_gabarit_lateral(tr, chm, largeur = st, pas_travers = 0.25)
  expect_equal(stats::median(g$SURPLOMB), 2, tolerance = 0.2)
})

test_that("dsr_gabarit_lateral refuse une largeur de longueur incoherente", {
  skip_if_not_installed("terra")
  skip_if_not_installed("sf")
  expect_error(
    dsr_gabarit_lateral(trace_droit(), couloir_chm(), largeur = c(4, 5)),
    "station"
  )
  expect_error(
    dsr_gabarit_lateral(trace_droit(), couloir_chm(), largeur = "large"),
    "numerique"
  )
  expect_error(dsr_gabarit_lateral(trace_droit(), "pas un raster"), "SpatRaster")
})

test_that("dsr_gabarit_lateral exige LARGEUR_ROULABLE dans un sf de largeur", {
  skip_if_not_installed("terra")
  skip_if_not_installed("sf")
  st <- sf::st_sf(AUTRE = 4,
    geometry = sf::st_sfc(sf::st_point(c(0, 0)), crs = 2154))
  expect_error(
    dsr_gabarit_lateral(trace_droit(), couloir_chm(), largeur = st),
    "LARGEUR_ROULABLE"
  )
})

test_that("dsr_gabarit_lateral ne retient que la premiere bande", {
  skip_if_not_installed("terra")
  skip_if_not_installed("sf")
  chm <- couloir_chm()
  deux <- c(chm, chm * 0) # la seconde bande est vide : elle doit etre ignoree
  expect_equal(
    dsr_gabarit_lateral(trace_droit(), deux, pas_travers = 0.25)$LARGEUR_DEGAGEE,
    dsr_gabarit_lateral(trace_droit(), chm, pas_travers = 0.25)$LARGEUR_DEGAGEE
  )
})

test_that("dsr_gabarit_lateral signale une maille grossiere", {
  skip_if_not_installed("terra")
  skip_if_not_installed("sf")
  expect_message(
    dsr_gabarit_lateral(trace_droit(), couloir_chm(res = 2)),
    "cellule"
  )
  expect_silent(dsr_gabarit_lateral(trace_droit(), couloir_chm(res = 0.5)))
})


# Bande minerale de synthese : NDVI bas sur 4 m de large, eleve autour.
bande_ndvi <- function(demi = 2, bas = 0.05, haut = 0.75, res = 0.25) {
  r <- terra::rast(xmin = 0, xmax = 60, ymin = 0, ymax = 60,
    resolution = res, crs = "EPSG:2154")
  xy <- terra::xyFromCell(r, seq_len(terra::ncell(r)))
  terra::values(r) <- ifelse(abs(xy[, 2] - 30) <= demi, bas, haut)
  r
}

test_that("dsr_largeur_ndvi retrouve la largeur de la bande minerale", {
  skip_if_not_installed("terra")
  skip_if_not_installed("sf")
  l <- dsr_largeur_ndvi(trace_droit(), bande_ndvi(), liss_travers = 1)
  expect_equal(stats::median(l$LARGEUR_NDVI), 4, tolerance = 0.3)
  expect_true(all(l$NDVI_AXE < 0.2))
})

test_that("dsr_largeur_ndvi expose le seuil retenu", {
  skip_if_not_installed("terra")
  skip_if_not_installed("sf")
  l <- dsr_largeur_ndvi(trace_droit(), bande_ndvi(), liss_travers = 1)
  s <- attr(l, "seuil")
  expect_true(is.finite(s))
  expect_gt(s, 0.05)
  expect_lt(s, 0.75)
})

test_that("dsr_largeur_ndvi accepte un seuil impose", {
  skip_if_not_installed("terra")
  skip_if_not_installed("sf")
  l <- dsr_largeur_ndvi(trace_droit(), bande_ndvi(), seuil = 0.4,
    liss_travers = 1)
  expect_equal(attr(l, "seuil"), 0.4)
  expect_equal(stats::median(l$LARGEUR_NDVI), 4, tolerance = 0.3)
})

test_that("dsr_largeur_ndvi censure plutot que de tronquer", {
  skip_if_not_installed("terra")
  skip_if_not_installed("sf")
  # Bande plus large que le profil : la valeur serait la demi-largeur, pas une
  # mesure. On veut NA, pas un chiffre plausible et faux.
  l <- dsr_largeur_ndvi(trace_droit(), bande_ndvi(demi = 30), demi_largeur = 3,
    seuil = 0.4, liss_travers = 1)
  expect_true(all(l$TRONQUE))
  expect_true(all(is.na(l$LARGEUR_NDVI)))
})

test_that("dsr_largeur_ndvi valide ses arguments", {
  skip_if_not_installed("terra")
  skip_if_not_installed("sf")
  expect_error(dsr_largeur_ndvi(trace_droit(), "pas un raster"), "SpatRaster")
  expect_error(
    dsr_largeur_ndvi(trace_droit(), bande_ndvi(), seuil = "auto"),
    "otsu"
  )
})

test_that("dsr_largeur_ndvi ne retient que la premiere bande", {
  skip_if_not_installed("terra")
  skip_if_not_installed("sf")
  nd <- bande_ndvi()
  deux <- c(nd, nd * 0)
  expect_equal(
    dsr_largeur_ndvi(trace_droit(), deux, seuil = 0.4,
      liss_travers = 1)$LARGEUR_NDVI,
    dsr_largeur_ndvi(trace_droit(), nd, seuil = 0.4,
      liss_travers = 1)$LARGEUR_NDVI
  )
})

test_that("dsr_largeur_ndvi refuse de deviner un seuil sans donnee", {
  skip_if_not_installed("terra")
  skip_if_not_installed("sf")
  # Trace hors de l'emprise du raster : tous les profils sont NA. Sans garde,
  # Otsu rendrait NA et la largeur sortirait silencieusement fausse.
  vide <- bande_ndvi()
  terra::values(vide) <- NA_real_
  expect_error(
    dsr_largeur_ndvi(trace_droit(), vide),
    "indeterminable"
  )
})


test_that("dsr_trafficability ne bloque que sur un surplomb BAS", {
  skip_if_not_installed("sf")
  base <- sf::st_sf(
    LARGEUR_ROULABLE = c(4, 4, 4), PENTE_LONG = c(0, 0, 0),
    RAYON_COURBURE = c(50, 50, 50),
    SURPLOMB = c(0, 1.5, 1.5),
    HAUT_SURPLOMB = c(Inf, 25, 3),
    geometry = sf::st_sfc(rep(list(sf::st_point(c(0, 0))), 3), crs = 2154)
  )
  r <- dsr_trafficability(base)
  # 1 : pas d'empietement. 2 : empietement haut (couvert ferme) -> apte.
  # 3 : empietement bas -> inapte.
  expect_equal(r$stations$APTE_GRUMIER, c(TRUE, TRUE, FALSE))
  expect_equal(r$stations$MOTIF_INAPTITUDE, c("", "", "surplomb"))
})

test_that("dsr_trafficability ignore le surplomb si les colonnes manquent", {
  skip_if_not_installed("sf")
  base <- sf::st_sf(
    LARGEUR_ROULABLE = 4, PENTE_LONG = 0, RAYON_COURBURE = 50,
    SURPLOMB = 2,
    geometry = sf::st_sfc(sf::st_point(c(0, 0)), crs = 2154)
  )
  r <- dsr_trafficability(base)
  expect_false("surplomb" %in% names(r$resume$par_motif))
  expect_true(r$stations$APTE_GRUMIER)
})


test_that("dsr_canaux_externes accepte le vocabulaire optique sans le signaler", {
  skip_if_not_installed("terra")
  grille <- terra::rast(xmin = 0, xmax = 20, ymin = 0, ymax = 20,
    resolution = 1, crs = "EPSG:2154")
  nd <- terra::rast(grille)
  terra::values(nd) <- stats::runif(terra::ncell(nd))
  expect_silent(dsr_canaux_externes(list(ndvi = nd), reference = grille))
  expect_message(
    dsr_canaux_externes(list(ndvii = nd), reference = grille),
    "hors vocabulaire"
  )
})

test_that("dsr_canaux_externes signale un canal plus grossier que la grille", {
  skip_if_not_installed("terra")
  grille <- terra::rast(xmin = 0, xmax = 30, ymin = 0, ymax = 30,
    resolution = 1, crs = "EPSG:2154")
  chm <- terra::rast(xmin = 0, xmax = 30, ymin = 0, ymax = 30,
    resolution = 1.5, crs = "EPSG:2154")
  terra::values(chm) <- stats::runif(terra::ncell(chm), 0, 30)
  expect_message(
    dsr_canaux_externes(list(chm = chm), reference = grille),
    "maille source"
  )
})
