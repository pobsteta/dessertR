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
