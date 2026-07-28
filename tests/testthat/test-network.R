L <- function(x1, y1, x2, y2) sf::st_linestring(rbind(c(x1, y1), c(x2, y2)))

test_that("dsr_coller_noeuds ramene les extremites proches sur un noeud commun", {
  skip_if_not_installed("sf")
  tr <- sf::st_sf(geometry = sf::st_sfc(L(0, 0, 10, 0), L(10.3, 0.2, 20, 0), crs = 2154))
  cl <- dsr_coller_noeuds(tr, tol = 1)
  e1 <- sf::st_coordinates(sf::st_geometry(cl)[1])
  e2 <- sf::st_coordinates(sf::st_geometry(cl)[2])
  # fin de la 1re ligne == debut de la 2e (exactement, apres collage)
  expect_equal(unname(e1[nrow(e1), 1:2]), unname(e2[1, 1:2]), tolerance = 1e-9)
})

test_that("dsr_dedupe_paralleles retire un doublon parallele", {
  skip_if_not_installed("sf")
  tr <- sf::st_sf(geometry = sf::st_sfc(
    L(0, 0, 20, 0), L(0, 1, 19, 1.1), L(0, 50, 20, 50), crs = 2154))
  d <- dsr_dedupe_paralleles(tr, largeur = 3, recouvrement = 0.7)
  expect_equal(nrow(d), 2) # le doublon a 1 m est retire, la ligne eloignee reste
})

test_that("dsr_reseau : composantes et rattachement au public", {
  skip_if_not_installed("sf")
  skip_if_not_installed("igraph")
  tr <- sf::st_sf(geometry = sf::st_sfc(
    L(0, 0, 10, 0), L(10.3, 0.2, 20, 0),  # composante reliee au public
    L(50, 50, 60, 60), L(60, 60, 70, 50), # composante deconnectee
    crs = 2154))
  r <- dsr_reseau(tr, reseau_public = sf::st_sfc(L(-5, 0, 0, 0), crs = 2154))
  expect_equal(r$resume$n_composants, 2)
  expect_equal(sum(r$aretes$connecte_public), 2)
  expect_equal(sum(!r$aretes$connecte_public), 2)
  expect_gt(r$resume$longueur_deconnectee, 0)
})

test_that("dsr_sfnetwork exige sfnetworks", {
  skip_if_not_installed("sf")
  tr <- sf::st_sf(geometry = sf::st_sfc(L(0, 0, 10, 0), crs = 2154))
  if (!requireNamespace("sfnetworks", quietly = TRUE)) {
    expect_error(dsr_sfnetwork(tr), "sfnetworks")
  } else {
    expect_s3_class(dsr_sfnetwork(tr), "sfnetwork")
  }
})
