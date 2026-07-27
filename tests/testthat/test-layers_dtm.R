test_that("la grille de reference est calee a 1 m sur des multiples de la resolution", {
  skip_if_not_installed("terra")

  mnt <- terra::rast(
    xmin = 1000.5, xmax = 1020.5, ymin = 2000.5, ymax = 2020.5,
    resolution = 0.5, crs = "EPSG:2154"
  )
  grille <- dsr_grille_reference(mnt, res = 1)

  expect_equal(terra::res(grille), c(1, 1))
  # Emprise calee sur des entiers (floor/ceil) -> grilles jointives entre dalles.
  expect_equal(terra::origin(grille), c(0, 0))
  expect_false(terra::hasValues(grille))
})

test_that("un canal a 0.5 m est aligne exactement sur la grille 1 m", {
  skip_if_not_installed("terra")

  mnt <- terra::rast(
    xmin = 1000, xmax = 1020, ymin = 2000, ymax = 2020,
    resolution = 0.5, crs = "EPSG:2154"
  )
  terra::values(mnt) <- stats::runif(terra::ncell(mnt))
  grille <- dsr_grille_reference(mnt, res = 1)

  opns <- terra::rast(mnt)
  terra::values(opns) <- stats::runif(terra::ncell(opns), 60, 90)

  pile <- dsr_canaux_externes(list(openness_neg = opns), reference = grille)

  expect_equal(names(pile), "openness_neg")
  expect_equal(terra::res(pile), terra::res(grille))
  expect_equal(terra::origin(pile), terra::origin(grille))
  expect_equal(as.vector(terra::ext(pile)), as.vector(terra::ext(grille)))
})

test_that("un composite 8 bits (CVAT/VAT) est refuse par defaut mais forcable", {
  skip_if_not_installed("terra")

  grille <- terra::rast(
    xmin = 0, xmax = 10, ymin = 0, ymax = 10, resolution = 1, crs = "EPSG:2154"
  )
  cvat <- terra::rast(grille)
  terra::values(cvat) <- sample(0:255, terra::ncell(grille), replace = TRUE)
  tmp <- tempfile(fileext = ".tif")
  terra::writeRaster(cvat, tmp, datatype = "INT1U", overwrite = TRUE)

  expect_error(
    dsr_canaux_externes(list(openness_pos = tmp), reference = grille),
    "8 bits"
  )
  expect_silent(
    p <- dsr_canaux_externes(
      list(openness_pos = tmp), reference = grille, refuser_composite = FALSE
    )
  )
  expect_equal(names(p), "openness_pos")
})

test_that("une liste non nommee est rejetee", {
  skip_if_not_installed("terra")
  grille <- terra::rast(
    xmin = 0, xmax = 10, ymin = 0, ymax = 10, resolution = 1, crs = "EPSG:2154"
  )
  r <- terra::rast(grille)
  terra::values(r) <- 1
  expect_error(dsr_canaux_externes(list(r), reference = grille), "liste nommee")
})

test_that("un canal angulaire reechantillonne en continu est signale", {
  skip_if_not_installed("terra")

  mnt <- terra::rast(
    xmin = 0, xmax = 20, ymin = 0, ymax = 20, resolution = 0.5, crs = "EPSG:2154"
  )
  terra::values(mnt) <- stats::runif(terra::ncell(mnt))
  grille <- dsr_grille_reference(mnt, res = 1)
  th <- terra::rast(mnt)
  terra::values(th) <- stats::runif(terra::ncell(th), 0, 180)

  expect_message(
    dsr_canaux_externes(list(theta = th), reference = grille),
    "angulaire"
  )
  # Au plus proche voisin : plus d'avertissement angulaire.
  expect_no_message(
    dsr_canaux_externes(
      list(theta = th), reference = grille, methodes = list(theta = "near")
    ),
    message = "angulaire"
  )
})

test_that("dsr_micro_relief : terrain plat -> svf = 1 et openness = 90", {
  skip_if_not_installed("terra")

  mnt <- terra::rast(
    nrows = 30, ncols = 30, xmin = 0, xmax = 30, ymin = 0, ymax = 30,
    crs = "EPSG:2154"
  )
  terra::values(mnt) <- 100 # parfaitement plat

  mr <- dsr_micro_relief(mnt, radius_m = 5)
  expect_setequal(names(mr), c("svf", "openness_pos", "openness_neg"))

  # Invariant analytique du noyau RVT (aucun horizon ne masque le ciel).
  expect_equal(
    unname(terra::global(mr[["svf"]], "mean")[1, 1]), 1, tolerance = 1e-9
  )
  expect_equal(
    unname(terra::global(mr[["openness_pos"]], "mean")[1, 1]), 90, tolerance = 1e-9
  )
})

test_that("dsr_micro_relief : un creux ferme le ciel (svf < 1, openness < 90)", {
  skip_if_not_installed("terra")

  mnt <- terra::rast(
    nrows = 21, ncols = 21, xmin = 0, xmax = 21, ymin = 0, ymax = 21,
    crs = "EPSG:2154"
  )
  terra::values(mnt) <- 100
  mnt[11, 11] <- 90 # creux central

  mr <- dsr_micro_relief(mnt, radius_m = 5, canaux = c("svf", "openness_pos"))
  centre <- terra::cellFromRowCol(mr, 11, 11)
  expect_lt(mr[["svf"]][centre][1, 1], 1)
  expect_lt(mr[["openness_pos"]][centre][1, 1], 90)
})

test_that("dsr_pente : terrain plat -> pente nulle", {
  skip_if_not_installed("terra")
  mnt <- terra::rast(nrows = 20, ncols = 20, xmin = 0, xmax = 20,
    ymin = 0, ymax = 20, crs = "EPSG:2154")
  terra::values(mnt) <- 100
  p <- dsr_pente(mnt)
  expect_equal(names(p), "pente")
  expect_equal(unname(terra::global(p, "max", na.rm = TRUE)[1, 1]), 0, tolerance = 1e-6)
})

test_that("dsr_rugosite : plat lisse ~ 0, bosse > 0", {
  skip_if_not_installed("terra")
  mnt <- terra::rast(nrows = 25, ncols = 25, xmin = 0, xmax = 25,
    ymin = 0, ymax = 25, crs = "EPSG:2154")
  terra::values(mnt) <- 100
  expect_lt(unname(terra::global(dsr_rugosite(mnt), "max", na.rm = TRUE)[1, 1]), 1e-6)
  mnt[13, 13] <- 105
  expect_gt(unname(terra::global(dsr_rugosite(mnt), "max", na.rm = TRUE)[1, 1]), 0)
})

test_that("dsr_slrm : une couche par fenetre", {
  skip_if_not_installed("terra")
  mnt <- terra::rast(nrows = 30, ncols = 30, xmin = 0, xmax = 30,
    ymin = 0, ymax = 30, crs = "EPSG:2154")
  terra::values(mnt) <- stats::runif(terra::ncell(mnt))
  s <- dsr_slrm(mnt, fenetres_m = c(3, 9))
  expect_equal(names(s), c("slrm_3", "slrm_9"))
})

test_that("dsr_vesselness : vallee diagonale -> reponse et theta ~ 45", {
  skip_if_not_installed("terra")
  n <- 70
  g <- terra::rast(nrows = n, ncols = n, xmin = 0, xmax = n, ymin = 0, ymax = n,
    crs = "EPSG:2154")
  xy <- terra::xyFromCell(g, seq_len(terra::ncell(g)))
  d <- (xy[, 2] - xy[, 1]) / sqrt(2)
  terra::values(g) <- 100 - 2 * exp(-(d^2) / (2 * 3^2))
  ves <- dsr_vesselness(g)
  expect_setequal(names(ves), c("vesselness", "theta"))
  vv <- terra::values(ves[["vesselness"]]); th <- terra::values(ves[["theta"]])
  ligne <- which(abs(d) < 1); dehors <- which(abs(d) > 8)
  expect_gt(median(vv[ligne], na.rm = TRUE), 0.5)
  expect_lt(median(vv[dehors], na.rm = TRUE), 0.05)
  expect_equal(median(th[ligne], na.rm = TRUE), 45, tolerance = 2)
})

test_that("dsr_layers_dtm : pile attendue alignee sur la grille", {
  skip_if_not_installed("terra")
  mnt <- terra::rast(nrows = 60, ncols = 60, xmin = 0, xmax = 30,
    ymin = 0, ymax = 30, resolution = 0.5, crs = "EPSG:2154")
  terra::values(mnt) <- 100 + stats::runif(terra::ncell(mnt))
  grille <- dsr_grille_reference(mnt, res = 1)
  pile <- dsr_layers_dtm(mnt, grille = grille, rayons_openness = c(2, 5),
    echelles_vessel = c(1, 2), fenetres_slrm = 5)
  expect_true(all(c("pente", "rugosite", "slrm_5", "openness_neg_2",
    "openness_neg_5", "svf", "openness_pos", "vesselness", "theta") %in% names(pile)))
  expect_equal(terra::res(pile), terra::res(grille))
  expect_equal(terra::origin(pile), terra::origin(grille))
})
