# Test d'integration bout-en-bout sur le jeu d'exemple versionne (inst/extdata).
ex <- function(f) system.file("extdata", f, package = "dessertR")

test_that("le catalogue lit la dalle d'exemple (COPC/LAZ)", {
  skip_if_not_installed("sf")
  laz <- ex("exemple_nuage.laz")
  skip_if(laz == "" || !file.exists(laz), "Exemple absent.")
  d <- dsr_parse_dalle(laz)
  expect_true(is.na(d$cle) || grepl("^[0-9]{4}_[0-9]{4}$", d$cle)) # nom ecrete
  h <- dessertR:::dsr_lire_entetes(laz)
  expect_gt(h$n_points, 1e5)          # ~327k points
  expect_equal(h$version_las, "1.4")
})

test_that("chaine geomorphologique sur le MNT d'exemple", {
  skip_if_not_installed("terra")
  mntf <- ex("exemple_mnt.tif")
  skip_if(mntf == "" || !file.exists(mntf), "Exemple absent.")
  mnt <- terra::rast(mntf)
  grille <- dsr_grille_reference(mnt, res = 1)
  pile <- dsr_layers_dtm(mnt, grille = grille,
    rayons_openness = c(2, 5), echelles_vessel = c(1, 2), fenetres_slrm = 5)
  expect_true(all(c("pente", "openness_neg_2", "vesselness", "theta") %in% names(pile)))
  sg <- dsr_conductivite(pile)
  expect_equal(names(sg), "sigma_geo")
})

test_that("layers_pc et mesure sur l'exemple", {
  skip_if_not_installed("lasR")
  skip_if_not_installed("sf")
  laz <- ex("exemple_nuage.laz"); mntf <- ex("exemple_mnt.tif"); bd <- ex("exemple_bdtopo.gpkg")
  skip_if(laz == "" || !file.exists(laz), "Exemple absent.")

  pc <- dsr_layers_pc(laz, res = 2)
  expect_true("densite_sol" %in% names(pc))
  expect_lte(terra::global(pc[["taux_penetration"]], "max", na.rm = TRUE)[1, 1], 1)

  roads <- sf::st_read(bd, "troncon_de_route", quiet = TRUE)
  r1 <- roads[which.max(as.numeric(sf::st_length(roads))), ]
  m <- dsr_measure(r1, terra::rast(mntf), pas = 2)
  expect_s3_class(m$stations, "sf")
  expect_true("LARGEUR_ROULABLE" %in% names(m$stations))
})
