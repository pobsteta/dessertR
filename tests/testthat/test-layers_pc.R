test_that("dsr_lecteur_lasr rejette une emprise mal formee", {
  # L'erreur est levee avant tout appel a lasR (pas de dependance ici).
  expect_error(dsr_lecteur_lasr(c(1, 2, 3)), "xmin")
  expect_error(dsr_lecteur_lasr("nawak"), "xmin")
})

test_that("dsr_lecteur_lasr construit un lecteur pour NULL / numeric / sf", {
  skip_if_not_installed("lasR")
  skip_if_not_installed("sf")

  expect_no_error(dsr_lecteur_lasr(NULL))
  expect_no_error(dsr_lecteur_lasr(c(0, 0, 10, 10)))

  poly <- sf::st_as_sf(sf::st_sfc(
    sf::st_polygon(list(rbind(
      c(0, 0), c(10, 0), c(10, 10), c(0, 10), c(0, 0)
    ))),
    crs = 2154
  ))
  expect_no_error(dsr_lecteur_lasr(poly))
})

test_that("dsr_layers_pc refuse une dalle inexistante", {
  skip_if_not_installed("lasR")
  expect_error(dsr_layers_pc("/introuvable/dalle.laz"), "existant")
})

# L'integration complete exige lasR ET une vraie dalle classee (non versionnee
# dans le paquet a ce stade) : le test s'execute si une dalle d'exemple est
# presente, sinon il est saute proprement.
test_that("dsr_layers_pc produit les canaux attendus (si donnees disponibles)", {
  skip_if_not_installed("lasR")
  dalle <- Sys.getenv("DSR_DALLE_TEST", "")
  skip_if(dalle == "" || !file.exists(dalle), "Aucune dalle de test (DSR_DALLE_TEST).")

  pc <- dsr_layers_pc(dalle, res = 2,
    emprise = NULL, sousetage = c(0.3, 3))
  expect_true(all(c("densite_sol", "taux_penetration", "densite_sousetage",
    "h_couvert", "masque_exclusion", "masque_pont") %in% names(pc)))
  # Les ratios restent dans [0, 1].
  expect_lte(terra::global(pc[["taux_penetration"]], "max", na.rm = TRUE)[1, 1], 1)
  expect_gte(terra::global(pc[["taux_penetration"]], "min", na.rm = TRUE)[1, 1], 0)
})
