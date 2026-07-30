stations_test <- function() {
  sf::st_sf(
    chainage = c(0, 2, 4, 6, 8),
    LARGEUR_ROULABLE = c(4, 2.5, 4, 4, 4),
    PENTE_LONG       = c(0.02, 0.02, 0.20, 0.02, 0.02),
    RAYON_COURBURE   = c(Inf, Inf, Inf, 8, Inf),
    GABARIT_LIBRE    = c(6, 6, 6, 6, 3.0),
    geometry = sf::st_sfc(lapply(0:4, function(i) sf::st_point(c(i * 2, 0))), crs = 2154)
  )
}

test_that("dsr_seuils_grumier renvoie les quatre seuils", {
  s <- dsr_seuils_grumier()
  expect_setequal(names(s), c("largeur_min", "pente_max", "rayon_min", "gabarit_min"))
})

test_that("dsr_trafficability : chaque defaut donne le bon motif", {
  skip_if_not_installed("sf")
  tf <- dsr_trafficability(stations_test())
  expect_equal(tf$stations$APTE_GRUMIER, c(TRUE, FALSE, FALSE, FALSE, FALSE))
  expect_equal(tf$stations$MOTIF_INAPTITUDE,
    c("", "largeur", "pente", "rayon", "gabarit"))
  expect_equal(tf$resume$part_apte, 0.2, tolerance = 1e-9)
})

test_that("dsr_trafficability : sans gabarit, le critere gabarit est ignore", {
  skip_if_not_installed("sf")
  st <- stations_test(); st$GABARIT_LIBRE <- NULL
  tf <- dsr_trafficability(st)
  expect_false("gabarit" %in% names(tf$resume$par_motif))
  # la station 5 (gabarit bas) redevient apte faute de critere gabarit
  expect_true(tf$stations$APTE_GRUMIER[5])
})

test_that("dsr_trafficability : un critere NA ne declare pas d'inaptitude", {
  skip_if_not_installed("sf")
  st <- stations_test(); st$RAYON_COURBURE[1] <- NA
  tf <- dsr_trafficability(st)
  expect_true(tf$stations$APTE_GRUMIER[1])
})

test_that("dsr_places : detecte un elargissement, aucun si largeur uniforme", {
  skip_if_not_installed("sf")
  large <- sf::st_sf(chainage = seq(0, 40, 2),
    LARGEUR_ROULABLE = c(rep(3, 8), rep(7, 5), rep(3, 8)),
    geometry = sf::st_sfc(lapply(seq(0, 40, 2), function(x) sf::st_point(c(x, 0))), crs = 2154))
  pl <- dsr_places(large, marge = 2, long_min = 6)
  expect_equal(nrow(pl), 1)
  expect_gte(pl$largeur_max[1], 7)

  uni <- large; uni$LARGEUR_ROULABLE <- 3
  expect_equal(nrow(dsr_places(uni)), 0)
})

test_that("dsr_gabarit_libre : refuse une dalle inexistante", {
  skip_if_not_installed("lasR")
  tr <- sf::st_sf(geometry = sf::st_sfc(
    sf::st_linestring(cbind(c(0, 10), c(0, 0))), crs = 2154))
  expect_error(dsr_gabarit_libre(tr, "/introuvable.laz"), "introuvable")
})
