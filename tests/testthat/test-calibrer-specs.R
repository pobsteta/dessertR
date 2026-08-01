# Pile synthetique : un canal porte le signal (fort SUR la route), un autre est
# du bruit pur. `sens` permet d'inverser le canal utile pour tester la detection
# du signe.
pile_synth <- function(sens = 1, graine = 1) {
  set.seed(graine)
  r <- terra::rast(nrows = 120, ncols = 120, xmin = 0, xmax = 120, ymin = 0,
                   ymax = 120, crs = "EPSG:2154")
  xy <- terra::xyFromCell(r, seq_len(terra::ncell(r)))
  sur_route <- abs(xy[, 2] - 60) < 3

  utile <- terra::rast(r)
  terra::values(utile) <- ifelse(sur_route, 0.8, 0.2) + stats::rnorm(terra::ncell(r), 0, 0.05)
  if (sens < 0) utile <- 1 - utile

  bruit <- terra::rast(r)
  terra::values(bruit) <- stats::runif(terra::ncell(r))

  # `theta` doit etre ignore : c'est une orientation, pas une intensite.
  theta <- terra::rast(r)
  terra::values(theta) <- stats::runif(terra::ncell(r), 0, 180)

  out <- c(utile, bruit, theta)
  names(out) <- c("rugosite", "bruit", "theta")
  out
}

axe_synth <- function() {
  sf::st_sfc(sf::st_linestring(cbind(c(5, 115), c(60, 60))), crs = 2154)
}


test_that("le canal porteur est retenu avec le bon sens, le bruit est ecarte", {
  cal <- dsr_calibrer_specs(pile_synth(), axe_synth())

  expect_true("rugosite" %in% names(cal$specs))
  expect_equal(cal$specs$rugosite$type, "croissante")
  expect_false("bruit" %in% names(cal$specs))
  # `theta` n'est meme pas mesure.
  expect_false("theta" %in% cal$diagnostic$canal)

  d <- cal$diagnostic
  expect_gt(d$auc[d$canal == "rugosite"], 0.9)
  expect_lt(d$auc[d$canal == "bruit"], 0.6)
  # Le plus discriminant porte le poids maximal.
  expect_equal(max(cal$diagnostic$poids), 3)
})


test_that("un canal inverse est detecte comme decroissant", {
  cal <- dsr_calibrer_specs(pile_synth(sens = -1), axe_synth())
  expect_equal(cal$specs$rugosite$type, "decroissante")
})


test_that("un canal dont le sens s'inverse entre massifs est ecarte", {
  # C'est la raison d'etre du mode multi-massifs, et le cas s'est produit sur
  # donnee reelle : la pente marque les routes par le bas sur un massif et par
  # le haut sur l'autre. Calibree sur un seul, elle entrait dans les regles.
  seul <- dsr_calibrer_specs(pile_synth(sens = 1), axe_synth())
  expect_true("rugosite" %in% names(seul$specs))

  deux <- dsr_calibrer_specs(
    list(pile_synth(sens = 1), pile_synth(sens = -1, graine = 2)),
    list(axe_synth(), axe_synth()))

  expect_false("rugosite" %in% names(deux$specs))
  d <- deux$diagnostic
  expect_false(d$stable[d$canal == "rugosite"])
  expect_true(is.na(d$sens[d$canal == "rugosite"]))
})


test_that("les regles calibrees s'utilisent telles quelles dans dsr_conductivite", {
  pile <- pile_synth()
  cal <- dsr_calibrer_specs(pile, axe_synth())
  sigma <- dsr_conductivite(pile, specs = cal$specs)

  expect_s4_class(sigma, "SpatRaster")
  expect_equal(names(sigma), "sigma_geo")
  # La conductivite calibree doit etre plus forte sur la route qu'ailleurs.
  xy <- terra::xyFromCell(sigma, seq_len(terra::ncell(sigma)))
  v <- terra::values(sigma)[, 1]
  expect_gt(stats::median(v[abs(xy[, 2] - 60) < 3], na.rm = TRUE),
            stats::median(v[abs(xy[, 2] - 60) > 20], na.rm = TRUE))
})


test_that("les echelles d'un meme canal sont regroupees par base", {
  # dsr_conductivite() moyenne les echelles d'une base avant appartenance ; le
  # calibrage doit mesurer la meme grandeur, sinon il calibre autre chose.
  p <- pile_synth()
  multi <- c(p[["rugosite"]], p[["rugosite"]], p[["bruit"]])
  names(multi) <- c("openness_neg_2", "openness_neg_10", "bruit")

  cal <- dsr_calibrer_specs(multi, axe_synth())
  expect_true("openness_neg" %in% cal$diagnostic$canal)
  expect_false(any(grepl("_[0-9]+$", cal$diagnostic$canal)))
})


test_that("dsr_calibrer_specs refuse les entrees incoherentes", {
  p <- pile_synth(); a <- axe_synth()

  expect_error(dsr_calibrer_specs(p, a, pres = 20, absent = 5), "inferieur")
  expect_error(dsr_calibrer_specs(list(p, p), a), "meme longueur")
  expect_error(dsr_calibrer_specs(list("pas un raster"), list(a)), "SpatRaster")

  # Un massif ou RIEN ne discrimine : aucune regle n'est produite, on le dit,
  # et le diagnostic reste exploitable pour comprendre pourquoi.
  set.seed(3)
  bruit <- terra::rast(nrows = 120, ncols = 120, xmin = 0, xmax = 120, ymin = 0,
                       ymax = 120, crs = "EPSG:2154")
  terra::values(bruit) <- stats::runif(terra::ncell(bruit))
  b2 <- terra::rast(bruit); terra::values(b2) <- stats::runif(terra::ncell(bruit))
  pile_bruit <- c(bruit, b2); names(pile_bruit) <- c("rugosite", "svf")

  expect_message(cal <- dsr_calibrer_specs(pile_bruit, a), "auc_min")
  expect_length(cal$specs, 0L)
  expect_equal(nrow(cal$diagnostic), 2L)
  expect_true(all(!cal$diagnostic$retenu))
  # Sur du bruit, l'AUC doit rester au voisinage du hasard.
  expect_lt(max(cal$diagnostic$auc), 0.62)
})


test_that("les regles calibrees portent des bornes absolues", {
  skip_if_not_installed("terra"); skip_if_not_installed("sf")
  cal <- dsr_calibrer_specs(pile_synth(), axe_synth())
  expect_true(length(cal$specs) > 0)
  for (sp in cal$specs) {
    expect_true(all(c("a", "b") %in% names(sp)))
    expect_true(is.finite(sp$a) && is.finite(sp$b))
    expect_lt(sp$a, sp$b)   # une rampe degeneree ne decrit rien
  }
  expect_true(all(c("a", "b") %in% names(cal$diagnostic)))

  # bornes = FALSE rend le comportement historique : regles sans bornes.
  sans <- dsr_calibrer_specs(pile_synth(), axe_synth(), bornes = FALSE)
  expect_false(any(vapply(sans$specs, function(s) "a" %in% names(s), logical(1))))
})


test_that("les bornes rendent la conductivite independante de l'emprise", {
  skip_if_not_installed("terra"); skip_if_not_installed("sf")
  # C'est le defaut que ces bornes corrigent : sans elles, dsr_appartenance()
  # derive ses bornes des quantiles de la fenetre recue, donc la meme cellule
  # n'a pas la meme conductivite selon l'etendue qu'on soumet.
  pile <- pile_synth()
  cal <- dsr_calibrer_specs(pile, axe_synth())

  petite <- terra::crop(pile, terra::ext(20, 100, 40, 80))
  large <- pile

  ancre_p <- dsr_conductivite(petite, specs = cal$specs)
  ancre_l <- terra::crop(dsr_conductivite(large, specs = cal$specs),
    terra::ext(ancre_p))
  expect_equal(terra::values(ancre_p, mat = FALSE),
    terra::values(ancre_l, mat = FALSE), tolerance = 1e-8)

  # Sans bornes, les deux vues divergent.
  sans <- dsr_calibrer_specs(pile, axe_synth(), bornes = FALSE)$specs
  libre_p <- dsr_conductivite(petite, specs = sans)
  libre_l <- terra::crop(dsr_conductivite(large, specs = sans),
    terra::ext(libre_p))
  expect_false(isTRUE(all.equal(terra::values(libre_p, mat = FALSE),
    terra::values(libre_l, mat = FALSE), tolerance = 1e-8)))
})


test_that("la calibration rend le terrain et la mesure par massif", {
  skip_if_not_installed("terra"); skip_if_not_installed("sf")
  cal <- dsr_calibrer_specs(list(pile_synth(), pile_synth(graine = 2)),
    list(axe_synth(), axe_synth()))

  # Un descripteur par massif, meme quand la pile ne porte pas tous les canaux
  # attendus : les absents valent NA plutot que de faire echouer la mesure.
  expect_equal(nrow(cal$terrain), 2L)
  expect_true(all(c("pente_med", "pente_p90", "rugosite_med", "relief_iqr")
    %in% names(cal$terrain)))
  expect_true(is.finite(cal$terrain$rugosite_med[1]))
  expect_true(all(is.na(cal$terrain$pente_med)))  # `pente` absent de la pile

  # par_massif porte la mesure AVANT agregation : c'est la qu'on lit comment un
  # canal s'inverse, la ou diagnostic dit seulement qu'il le fait.
  expect_true(all(c("canal", "massif", "auc", "sens") %in% names(cal$par_massif)))
  expect_setequal(unique(cal$par_massif$massif), c(1, 2))
  expect_true(all(cal$par_massif$canal %in% cal$diagnostic$canal))
})


test_that("la calibration est reproductible, et rend le generateur intact", {
  skip_if_not_installed("terra"); skip_if_not_installed("sf")
  pile <- pile_synth(); axe <- axe_synth()

  # Deux appels identiques -> memes regles. Sans graine, l'AUC etant estimee sur
  # un echantillon, un canal pose au bord de auc_min entrait ou sortait du jeu
  # selon le tirage.
  a <- dsr_calibrer_specs(pile, axe)
  b <- dsr_calibrer_specs(pile, axe)
  expect_equal(a$specs, b$specs)
  expect_equal(a$diagnostic, b$diagnostic)

  # Deux graines differentes peuvent differer : la graine fige le tirage, elle
  # ne supprime pas l'incertitude d'echantillonnage.
  c1 <- dsr_calibrer_specs(pile, axe, graine = 7)
  expect_equal(names(c1$specs), names(a$specs))

  # L'etat du generateur de l'appelant doit ressortir INTACT : poser une graine
  # dans une fonction de paquet sans la rendre casserait la reproductibilite du
  # code appelant.
  set.seed(123)
  avant <- get(".Random.seed", envir = globalenv())
  invisible(dsr_calibrer_specs(pile, axe))
  expect_identical(get(".Random.seed", envir = globalenv()), avant)

  # graine = NULL laisse jouer l'aleatoire ambiant : le generateur avance.
  set.seed(123)
  invisible(dsr_calibrer_specs(pile, axe, graine = NULL))
  expect_false(identical(get(".Random.seed", envir = globalenv()), avant))
})
