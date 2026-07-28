# Lissage et raccordement des centre-lignes (post-traitement du vectoriseur).
# La reference est un arc de cercle de rayon connu : on peut donc mesurer si le
# lissage rapproche ou non la geometrie de la verite, au lieu de constater
# seulement qu'il « lisse ».

arc_vrai <- function(rayon = 60, n = 400) {
  th <- seq(-pi / 4, pi / 4, length.out = n)
  cbind(rayon * sin(th), rayon * cos(th))
}
# ce que produit un squelette : les memes points rabattus au centre de cellule
arc_escalier <- function(...) unique(round(arc_vrai(...)))

longueur <- function(co) sum(sqrt(rowSums(diff(co)^2)))
sinuosite <- function(co) longueur(co) / sqrt(sum((co[nrow(co), ] - co[1, ])^2))
ecart_median <- function(a, b) {
  stats::median(apply(a, 1, function(p) min(sqrt(colSums((t(b) - p)^2)))))
}

test_that("Savitzky-Golay rapproche l'escalier de la courbe vraie", {
  vrai <- arc_vrai(); esc <- arc_escalier()
  sg <- .dsr_lisser_sg(esc, demi = 3L)

  # l'escalier gonfle la longueur de ~25 % ; le lissage la ramene a ~2 %
  expect_gt(longueur(esc) / longueur(vrai), 1.2)
  expect_lt(abs(longueur(sg) - longueur(vrai)) / longueur(vrai), 0.03)
  # et il se rapproche geometriquement de la verite
  expect_lt(ecart_median(sg, vrai), ecart_median(esc, vrai))
  # sinuosite : l'escalier la surestime, le lissage la corrige
  expect_lt(abs(sinuosite(sg) - sinuosite(vrai)),
    abs(sinuosite(esc) - sinuosite(vrai)))
})

test_that("les lissages figent les extremites (la topologie en depend)", {
  esc <- arc_escalier()
  for (co in list(.dsr_lisser_sg(esc, demi = 3L),
                  .dsr_lisser_bezier(esc, tol = 2, pas = 1))) {
    expect_equal(co[1, ], esc[1, ])
    expect_equal(co[nrow(co), ], esc[nrow(esc), ])
  }
})

test_that("Savitzky-Golay laisse droit ce qui est droit", {
  droit <- cbind(0:20, 0)
  expect_lt(max(abs(.dsr_lisser_sg(droit, demi = 3L)[, 2])), 1e-9)
})

test_that("le lissage ne rabote pas un virage franc", {
  coude <- rbind(cbind(0:40, 0), cbind(40, 1:40))
  sg <- .dsr_lisser_sg(coude, demi = 3L)
  bz <- .dsr_lisser_bezier(coude, tol = 2, pas = 1)
  # le sommet du coude reste a moins de 3 m de sa position d'origine
  expect_lt(ecart_median(sg, coude), 1)
  expect_lt(ecart_median(bz, coude), 1)
})

test_that("les lissages laissent passer les lignes trop courtes", {
  court <- rbind(c(0, 0), c(1, 1))
  expect_identical(.dsr_lisser_sg(court, demi = 3L), court)
  expect_identical(.dsr_lisser_bezier(court, tol = 2, pas = 1), court)
})

test_that("Bezier : la tolerance controle le nombre de courbes", {
  esc <- arc_escalier()
  n_courbes <- function(tol) {
    length(.dsr_bezier_rec(esc, .dsr_unitaire(esc[2, ] - esc[1, ]),
      .dsr_unitaire(esc[nrow(esc) - 1, ] - esc[nrow(esc), ]), tol, 0L, 8L))
  }
  # une tolerance au niveau du bruit de quantification fait sur-decouper
  expect_gt(n_courbes(0.5), n_courbes(2))
  bz <- .dsr_lisser_bezier(esc, tol = 2, pas = 1)
  expect_lt(nrow(bz), nrow(esc))          # representation plus compacte
  expect_lt(abs(longueur(bz) - longueur(arc_vrai())) / longueur(arc_vrai()), 0.05)
})

test_that("raccordement : distance ET alignement", {
  a <- cbind(0:30, 0)
  b <- cbind(40:70, 0)                      # aligne, trouee de 10 m
  perp <- cbind(40, 0:30)                   # perpendiculaire, bout aussi proche

  expect_length(.dsr_raccorder(list(a, b), dmax = 15), 1)
  expect_length(.dsr_raccorder(list(a, b), dmax = 5), 2)   # trouee trop large
  expect_length(.dsr_raccorder(list(a, perp), dmax = 15), 2) # non aligne
  expect_length(.dsr_raccorder(list(a, b), dmax = 0), 2)   # desactive
  expect_length(.dsr_raccorder(list(a), dmax = 15), 1)     # rien a raccorder
})

test_that("dsr_vectoriser : le lissage est branche et selectionnable", {
  skip_if_not_installed("terra"); skip_if_not_installed("sf")
  n <- 80
  r <- terra::rast(nrows = n, ncols = n, xmin = 0, xmax = n, ymin = 0, ymax = n,
    crs = "EPSG:2154")
  terra::values(r) <- 0.1
  xy <- terra::xyFromCell(r, seq_len(terra::ncell(r)))
  # arc de cercle rasterise : la geometrie de reference est connue
  d <- sqrt((xy[, 1] - 10)^2 + (xy[, 2] - 10)^2)
  r[abs(d - 55) < 1.2] <- 0.9

  brut <- dsr_vectoriser(r, methode = "squelette", long_min = 20,
    lissage = "aucun", simplifier = 0)
  sg <- dsr_vectoriser(r, methode = "squelette", long_min = 20,
    lissage = "savitzky-golay", simplifier = 0)
  bz <- dsr_vectoriser(r, methode = "squelette", long_min = 20,
    lissage = "bezier", simplifier = 0)

  expect_equal(nrow(brut), 1); expect_equal(nrow(sg), 1); expect_equal(nrow(bz), 1)
  # l'escalier gonfle la longueur : les deux lissages la reduisent
  expect_lt(sg$longueur[1], brut$longueur[1])
  expect_lt(bz$longueur[1], brut$longueur[1])
  # la sortie Bezier est REECHANTILLONNEE : sa compacite est dans les points de
  # controle, que le LINESTRING de sf ne peut pas porter. On ne promet donc rien
  # sur le nombre de sommets rendus, seulement sur la geometrie.
  expect_lt(abs(bz$longueur[1] - sg$longueur[1]), 5)
})

test_that("dsr_detecter : raccorder recolle une piste coupee par une trouee", {
  skip_if_not_installed("terra"); skip_if_not_installed("sf")
  n <- 60; m <- 120
  r <- terra::rast(nrows = n, ncols = m, xmin = 0, xmax = m, ymin = 0, ymax = n,
    crs = "EPSG:2154")
  terra::values(r) <- 0.1
  xy <- terra::xyFromCell(r, seq_len(terra::ncell(r)))
  sur_axe <- abs(xy[, 2] - 30) < 1.5
  r[sur_axe & xy[, 1] > 10 & xy[, 1] < 50] <- 0.9
  r[sur_axe & xy[, 1] > 62 & xy[, 1] < 105] <- 0.9   # trouee de 12 m

  sans <- dsr_detecter(r, long_min = 20, raccorder = 0)
  avec <- dsr_detecter(r, long_min = 20, raccorder = 20)
  expect_equal(nrow(sans), 2)
  expect_equal(nrow(avec), 1)
  expect_gt(avec$longueur[1], sum(sans$longueur))
})
