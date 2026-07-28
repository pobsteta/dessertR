test_that("dsr_divergence = sigma_geo - sigma_surf", {
  skip_if_not_installed("terra")
  sg <- terra::rast(nrows = 4, ncols = 4, xmin = 0, xmax = 4, ymin = 0, ymax = 4,
    crs = "EPSG:2154")
  ss <- terra::rast(sg)
  terra::values(sg) <- 0.8; terra::values(ss) <- 0.3
  d <- dsr_divergence(sg, ss)
  expect_equal(names(d), "divergence")
  expect_equal(unname(terra::global(d, "mean")[1, 1]), 0.5, tolerance = 1e-9)
})

test_that("dsr_etat : les quatre croisements sont classes correctement", {
  skip_if_not_installed("terra")
  sg <- terra::rast(nrows = 2, ncols = 2, xmin = 0, xmax = 2, ymin = 0, ymax = 2,
    crs = "EPSG:2154")
  ss <- terra::rast(sg)
  # cellules : (geo,surf) = (0.9,0.9),(0.9,0.1),(0.1,0.9),(0.1,0.1)
  terra::values(sg) <- c(0.9, 0.9, 0.1, 0.1)
  terra::values(ss) <- c(0.9, 0.1, 0.9, 0.1)
  et <- dsr_etat(sg, ss)
  expect_equal(as.integer(terra::values(et, mat = FALSE)), c(1L, 2L, 3L, 4L))
  lv <- terra::levels(et)[[1]]
  expect_equal(lv$etat[lv$value == 2], "abandonnee")
})

test_that("dsr_etat : refuse des rasters non alignes", {
  skip_if_not_installed("terra")
  sg <- terra::rast(nrows = 4, ncols = 4, xmin = 0, xmax = 4, ymin = 0, ymax = 4,
    crs = "EPSG:2154")
  ss <- terra::rast(nrows = 5, ncols = 5, xmin = 0, xmax = 5, ymin = 0, ymax = 5,
    crs = "EPSG:2154")
  terra::values(sg) <- 0.5; terra::values(ss) <- 0.5
  expect_error(dsr_etat(sg, ss), "aligne")
})

test_that("dsr_etat_trace : segmente le trace et resume par etat", {
  skip_if_not_installed("terra")
  skip_if_not_installed("sf")
  n <- 60
  sg <- terra::rast(nrows = n, ncols = n, xmin = 0, xmax = n, ymin = 0, ymax = n,
    crs = "EPSG:2154")
  ss <- terra::rast(sg)
  terra::values(sg) <- 0.1; terra::values(ss) <- 0.1
  sg[30, ] <- 0.9              # empreinte continue
  ss[30, 1:30] <- 0.9          # 1re moitie degagee -> en_service
  ss[30, 31:60] <- 0.1         # 2e moitie recolonisee -> abandonnee

  trace <- sf::st_sf(geometry = sf::st_sfc(
    sf::st_linestring(cbind(c(1, 59), c(30.5, 30.5))), crs = 2154))
  et <- dsr_etat_trace(trace, sg, ss, pas = 2)

  expect_named(et, c("troncons", "profil", "resume"))
  expect_s3_class(et$troncons, "sf")
  expect_equal(as.character(et$troncons$etat), c("en_service", "abandonnee"))
  expect_equal(sum(et$resume$pourcentage), 100, tolerance = 0.5)
  # chainage strictement croissant sur le profil
  expect_true(all(diff(et$profil$chainage) > 0))
})

test_that("dsr_etat_trace : accepte la sortie de dsr_pathfinder", {
  skip_if_not_installed("terra")
  skip_if_not_installed("sf")
  sg <- terra::rast(nrows = 40, ncols = 40, xmin = 0, xmax = 40, ymin = 0,
    ymax = 40, crs = "EPSG:2154")
  terra::values(sg) <- 0.1; sg[20, ] <- 0.9
  ss <- terra::rast(sg); terra::values(ss) <- 0.9
  tr <- dsr_pathfinder(sg, c(1, 20.5), c(39, 20.5))
  et <- dsr_etat_trace(tr, sg, ss) # passe la liste directement
  expect_s3_class(et$troncons, "sf")
  expect_true(nrow(et$profil) >= 2)
})

test_that("dsr_etat_trace : refuse une geometrie non lineaire", {
  skip_if_not_installed("terra")
  skip_if_not_installed("sf")
  sg <- terra::rast(nrows = 10, ncols = 10, xmin = 0, xmax = 10, ymin = 0,
    ymax = 10, crs = "EPSG:2154")
  terra::values(sg) <- 0.5; ss <- terra::rast(sg); terra::values(ss) <- 0.5
  pt <- sf::st_sf(geometry = sf::st_sfc(sf::st_point(c(5, 5)), crs = 2154))
  expect_error(dsr_etat_trace(pt, sg, ss), "LINESTRING")
})
