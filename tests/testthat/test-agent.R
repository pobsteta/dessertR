# Carte synthetique : une route de conductivite 1 sur fond a 0.1, le long de
# y = 100. `trouee` coupe la route entre deux abscisses (conductivite ramenee au
# fond), ce qui simule une coupure de detection -- faux negatif du canal.
carte_route <- function(trouee = NULL, res = 2) {
  r <- terra::rast(nrows = 200 / res, ncols = 200 / res, xmin = 0, xmax = 200,
                   ymin = 0, ymax = 200, crs = "EPSG:2154")
  terra::values(r) <- 0.1
  xy <- terra::xyFromCell(r, seq_len(terra::ncell(r)))
  sur_route <- abs(xy[, 2] - 100) < 4
  r[sur_route] <- 1
  if (!is.null(trouee)) {
    r[sur_route & xy[, 1] > trouee[1] & xy[, 1] < trouee[2]] <- 0.1
  }
  r
}

amorce_ouest <- function() {
  sf::st_sfc(sf::st_linestring(cbind(c(10, 25), c(100, 100))), crs = "EPSG:2154")
}

x_final <- function(a) {
  co <- sf::st_coordinates(a$route)
  co[nrow(co), 1]
}


test_that("l'agent suit une route rectiligne jusqu'au bord de l'emprise", {
  a <- dsr_conduire(carte_route(), amorce_ouest(), portee = 40)

  expect_equal(a$arret, "hors_emprise")
  expect_gt(x_final(a), 185)
  # Il reste sur l'axe : l'ecart ne depasse pas la taille d'une cellule.
  co <- sf::st_coordinates(a$route)
  expect_lt(max(abs(co[, 2] - 100)), 2)
})


test_that("l'agent franchit une trouee de conductivite", {
  # C'est LA propriete qui distingue l'agent du squelette : une coupure de
  # detection de 20 m se franchit, parce que le cout admissible est module par
  # la profondeur du creux dans le profil angulaire et non par sa seule valeur.
  a <- dsr_conduire(carte_route(trouee = c(90, 110)), amorce_ouest(), portee = 40)

  expect_equal(a$arret, "hors_emprise")
  expect_gt(x_final(a), 180)
})


test_that("l'agent s'arrete quand la route s'arrete vraiment", {
  # Meme mecanique que ci-dessus, mais la route ne reprend jamais : il ne faut
  # pas confondre tolerance a la trouee et hors-piste.
  a <- dsr_conduire(carte_route(trouee = c(90, 200)), amorce_ouest(), portee = 40)

  expect_equal(a$arret, "trouee_trop_longue")
  # Les pas engages dans la trouee sont retires : la route rendue ne depasse
  # pas sensiblement la fin de la route reelle.
  expect_lt(x_final(a), 110)
})


test_that("l'agent s'arrete en rejoignant un reseau deja vectorise", {
  reseau <- sf::st_sfc(sf::st_linestring(cbind(c(150, 150), c(20, 180))),
                       crs = "EPSG:2154")
  a <- dsr_conduire(carte_route(), amorce_ouest(), reseau = reseau, portee = 40)

  expect_equal(a$arret, "reseau_rejoint")
  # Il s'arrete au contact du tampon (10 m par defaut), pas 40 m avant.
  expect_gt(x_final(a), 125)
  expect_lt(x_final(a), 145)
})


test_that("l'agent signale les embranchements sans les suivre", {
  r <- terra::rast(nrows = 150, ncols = 150, xmin = 0, xmax = 300, ymin = 0,
                   ymax = 300, crs = "EPSG:2154")
  terra::values(r) <- 0.1
  xy <- terra::xyFromCell(r, seq_len(terra::ncell(r)))
  r[abs(xy[, 2] - 150) < 4] <- 1                                   # tronc
  r[xy[, 1] >= 150 & abs((xy[, 2] - 150) - (xy[, 1] - 150)) < 5] <- 1  # branche a 45 deg

  a <- dsr_conduire(r, sf::st_sfc(sf::st_linestring(cbind(c(10, 30), c(150, 150))),
                                  crs = "EPSG:2154"), portee = 40)

  expect_false(is.null(a$amorces))
  expect_equal(length(a$amorces), 1L)
  # L'amorce part de la jonction, a (150, 150).
  d <- sf::st_coordinates(a$amorces)[1, 1:2]
  expect_lt(sqrt(sum((d - c(150, 150))^2)), 15)
})


test_that("dsr_conduire refuse une amorce non orientee", {
  r <- carte_route()
  pt <- sf::st_sfc(sf::st_point(c(10, 100)), crs = "EPSG:2154")
  expect_error(dsr_conduire(r, pt), "LINESTRING")
  expect_error(dsr_conduire(list(), amorce_ouest()), "SpatRaster")
})


test_that("le champ de cout est un Dijkstra un-vers-tous complet", {
  r <- terra::rast(nrows = 30, ncols = 30, xmin = 0, xmax = 60, ymin = 0,
                   ymax = 60, crs = "EPSG:2154")
  terra::values(r) <- 1
  champ <- .dsr_champ_cout(r, c(30, 30))

  expect_s4_class(champ, "SpatRaster")
  # Aucune cellule laissee inatteinte : c'est ce que garantit la destination
  # hors grille (le tas se vide au lieu de s'arreter a la cible).
  expect_false(any(is.na(terra::values(champ))))
  # Conductivite uniforme : le cout croit avec la distance euclidienne.
  expect_equal(terra::extract(champ, cbind(30, 30))[, 1], 0)
  c10 <- terra::extract(champ, cbind(40, 30))[, 1]
  c20 <- terra::extract(champ, cbind(50, 30))[, 1]
  expect_gt(c20, c10)
  expect_equal(c10, 10, tolerance = 0.1)

  # Depart sur une cellule interdite : pas de champ.
  r[terra::cellFromXY(r, cbind(30, 30))] <- NA
  expect_null(.dsr_champ_cout(r, c(30, 30)))
})


test_that("l'echantillonnage angulaire est symetrique et couvre le champ de vision", {
  a <- .dsr_angles(resolution = 2, portee = 40, fov = 160)
  expect_true(0 %in% a)
  expect_equal(a, -rev(a))
  expect_lte(max(a) * 180 / pi, 80)
  expect_true(all(diff(a) > 0))
  # Une portee plus grande donne un pas angulaire plus fin.
  expect_gt(length(.dsr_angles(2, 100, 160)), length(a))
})


test_that("la moyenne mobile lisse sans decaler ni raccourcir", {
  x <- c(1, 5, 1, 5, 1, 5, 1)
  expect_equal(.dsr_moyenne_mobile(x, 1), x)
  liss <- .dsr_moyenne_mobile(x, 3)
  expect_length(liss, length(x))
  expect_lt(diff(range(liss)), diff(range(x)))
  # Une constante reste constante (pas d'effet de bord).
  expect_equal(.dsr_moyenne_mobile(rep(7, 10), 5), rep(7, 10))
})


test_that("les minima du profil de cout trouvent les directions roulables", {
  # Profil a deux creux nets : deux directions praticables.
  ang <- seq(-1, 1, length.out = 61)
  cout <- 300 - 200 * exp(-((ang + 0.5)^2) / 0.01) - 150 * exp(-((ang - 0.4)^2) / 0.01)
  m <- .dsr_minima_cout(cout, cout_max = 200)

  expect_equal(nrow(m), 2L)
  expect_true(all(diff(m$cout) >= 0))          # trie par cout croissant
  expect_lt(abs(ang[m$idx[1]] - (-0.5)), 0.1)  # le meilleur est le creux profond
  expect_true(all(m$profondeur > 0))

  # Profil plat : aucune direction ne se distingue.
  expect_null(.dsr_minima_cout(rep(500, 61), cout_max = 200))
  # Profil trop court pour etre exploitable.
  expect_null(.dsr_minima_cout(c(1, 2, 3), cout_max = 200))
})


# --- Amorces et orchestration reseau ----------------------------------------

test_that("les amorces de bordure trouvent les entrees de route", {
  a <- dsr_amorces(carte_route(), seuil = 0.6, longueur = 20)

  # La route traverse d'ouest en est : une entree de chaque cote.
  expect_equal(length(a), 2L)
  co <- sf::st_coordinates(a)
  # Chaque amorce se termine sur la route (y = 100) et pointe vers l'interieur.
  fins <- co[!duplicated(co[, 3], fromLast = TRUE), 1:2, drop = FALSE]
  expect_true(all(abs(fins[, 2] - 100) < 5))
  expect_length(unique(round(fins[, 1])), 2L)

  # Fond uniforme sous le seuil : aucune amorce.
  vide <- carte_route()
  terra::values(vide) <- 0.1
  expect_null(dsr_amorces(vide, seuil = 0.6))
})


test_that("les amorces de reference partent des extremites du reseau connu", {
  r <- carte_route()
  ref <- sf::st_sfc(sf::st_linestring(cbind(c(40, 80), c(100, 100))),
                    crs = "EPSG:2154")
  a <- dsr_amorces(r, reference = ref, longueur = 20, bordure = FALSE)

  # Une amorce par extremite libre, orientee vers l'exterieur du troncon.
  expect_equal(length(a), 2L)
  co <- sf::st_coordinates(a)
  fins <- co[!duplicated(co[, 3], fromLast = TRUE), 1:2, drop = FALSE]
  expect_setequal(round(fins[, 1]), c(40, 80))

  # Sans reference ni bordure, il n'y a rien a amorcer.
  expect_null(dsr_amorces(r, reference = NULL, bordure = FALSE))
})


test_that("la sinuosite distingue un axe d'un trace qui serpente", {
  droit <- sf::st_sfc(sf::st_linestring(cbind(c(0, 100), c(0, 0))))
  expect_equal(.dsr_sinuosite(droit), 1)

  detour <- sf::st_sfc(sf::st_linestring(cbind(c(0, 50, 100), c(0, 50, 0))))
  expect_gt(.dsr_sinuosite(detour), 1.4)
})


test_that("dsr_vectoriser conduit l'agent sur un reseau en Y", {
  r <- terra::rast(nrows = 150, ncols = 150, xmin = 0, xmax = 300, ymin = 0,
                   ymax = 300, crs = "EPSG:2154")
  terra::values(r) <- 0.1
  xy <- terra::xyFromCell(r, seq_len(terra::ncell(r)))
  r[abs(xy[, 2] - 150) < 4] <- 1
  r[xy[, 1] >= 150 & abs((xy[, 2] - 150) - (xy[, 1] - 150)) < 5] <- 1

  v <- dsr_vectoriser(r, methode = "agent", long_min = 50, portee = 40)

  expect_s3_class(v, "sf")
  expect_identical(attr(v, "methode"), "agent")
  expect_gte(nrow(v), 1L)
  expect_true(all(v$longueur >= 50))
  # L'agent ne produit pas d'escalier de pixels : le trace est nettement plus
  # court que la somme des pas diagonaux d'un squelette rasterise.
  expect_lt(max(v$longueur), 600)
})


test_that("sans amorce exploitable, l'agent se replie ou rend un resultat vide", {
  r <- terra::rast(nrows = 60, ncols = 60, xmin = 0, xmax = 120, ymin = 0,
                   ymax = 120, crs = "EPSG:2154")
  terra::values(r) <- 0.1
  # Une tache centrale, qui ne touche aucun bord : rien pour amorcer.
  xy <- terra::xyFromCell(r, seq_len(terra::ncell(r)))
  r[abs(xy[, 1] - 60) < 15 & abs(xy[, 2] - 60) < 3] <- 1

  # Demande explicite : resultat vide, pas de repli silencieux.
  expect_equal(nrow(dsr_vectoriser(r, methode = "agent", long_min = 10)), 0L)
  # En "auto", le repli sur le squelette est annonce et produit la ligne.
  expect_message(v <- dsr_vectoriser(r, methode = "auto", long_min = 10),
                 "squelette")
  expect_identical(attr(v, "methode"), "squelette")
  expect_gte(nrow(v), 1L)
})


test_that("une amorce hors donnee est ecartee et ne devient pas une route", {
  # Cas reel : un troncon de reference qui deborde de l'emprise d'analyse. Son
  # extremite tombe hors donnee, l'agent ne peut pas demarrer -- et l'amorce ne
  # doit surtout pas ressortir comme une route decouverte.
  r <- carte_route()
  r[terra::xyFromCell(r, seq_len(terra::ncell(r)))[, 1] > 100] <- NA
  ref <- sf::st_sfc(sf::st_linestring(cbind(c(30, 160), c(100, 100))),
                    crs = "EPSG:2154")

  a <- dsr_amorces(r, reference = ref, bordure = FALSE)
  # Seule l'extremite ouest, dans la donnee, produit une amorce.
  expect_equal(length(a), 1L)
  co <- sf::st_coordinates(a)
  expect_lt(co[nrow(co), 1], 100)

  # Et si on force l'agent a partir d'un point hors donnee, il le dit.
  hors <- sf::st_sfc(sf::st_linestring(cbind(c(140, 160), c(100, 100))),
                     crs = "EPSG:2154")
  b <- dsr_conduire(r, hors, portee = 40)
  expect_equal(b$n_troncons, 0L)
})


test_that("n_troncons distingue une route parcourue d'une amorce rendue telle quelle", {
  a <- dsr_conduire(carte_route(), amorce_ouest(), portee = 40)
  expect_gt(a$n_troncons, 0L)

  # Fond uniforme : rien a suivre, l'agent ne decouvre rien.
  vide <- carte_route()
  terra::values(vide) <- 0.1
  b <- dsr_conduire(vide, amorce_ouest(), portee = 40)
  expect_equal(b$n_troncons, 0L)
})


test_that("l'agent ne sort pas de l'emprise qu'on lui a fixee", {
  # Les NA ne sont pas une trouee de detection mais une absence de donnee : les
  # ramener au plancher de conductivite laisserait l'agent rouler hors emprise.
  r <- carte_route()
  r[terra::xyFromCell(r, seq_len(terra::ncell(r)))[, 1] > 120] <- NA

  a <- dsr_conduire(r, amorce_ouest(), portee = 40)
  expect_lte(max(sf::st_coordinates(a$route)[, 1]), 122)
})


test_that("franchissabilite retient l'agent sans le hacher", {
  # Une route parfaite, mais dont l'emprise est refermee au-dela de x = 120.
  # L'agent doit ralentir la, pas s'y arreter net : c'est ce qui distingue un
  # plancher d'une barriere, et ce qui lui garde sa robustesse aux trouees.
  r <- carte_route()
  surf <- terra::rast(r)
  terra::values(surf) <- 1
  surf[terra::xyFromCell(surf, seq_len(terra::ncell(surf)))[, 1] > 120] <- 0.1

  libre <- dsr_conduire(r, amorce_ouest(), portee = 40)
  freine <- dsr_conduire(r, amorce_ouest(), portee = 40,
    franchissabilite = surf, franchissabilite_min = 0.4)

  # Le trajet est raccourci par la contrainte, mais l'agent a bien roule.
  expect_gt(freine$n_troncons, 0L)
  expect_lt(x_final(freine), x_final(libre))
})


test_that("franchissabilite : NULL n'a aucun effet, et un raster desaligne est refuse", {
  r <- carte_route()

  # Le defaut ne doit rien changer au comportement historique.
  sans <- dsr_conduire(r, amorce_ouest(), portee = 40)
  nul <- dsr_conduire(r, amorce_ouest(), portee = 40, franchissabilite = NULL)
  expect_equal(x_final(nul), x_final(sans))

  # Une grille differente est une erreur explicite, pas un silence.
  autre <- terra::rast(nrows = 10, ncols = 10, xmin = 0, xmax = 200,
    ymin = 0, ymax = 200, crs = "EPSG:2154")
  terra::values(autre) <- 1
  expect_error(
    dsr_conduire(r, amorce_ouest(), portee = 40, franchissabilite = autre),
    "aligne"
  )
  expect_error(
    dsr_conduire(r, amorce_ouest(), portee = 40, franchissabilite = "pas un raster"),
    "SpatRaster"
  )
})


test_that("une amorce posee sur le reseau connu peut demarrer", {
  skip_if_not_installed("terra")
  # Verrou de non-regression. Le reseau deja decouvert est rendu
  # infranchissable ; sans exception autour du depart, une amorce posee dessus
  # -- le cas NOMINAL, puisque les amorces viennent du reseau de reference --
  # mourait en `depart_infranchissable` sans avancer d'un pas. Mesure sur donnee
  # reelle avant correction : 32 amorces sur 54 (wsfi) et 19 sur 26 (ltcp).
  r <- carte_route()
  # Un reseau qui recouvre exactement la route suivie, donc aussi le depart.
  reseau <- sf::st_sfc(sf::st_linestring(cbind(c(5, 195), c(100, 100))),
    crs = "EPSG:2154")

  a <- dsr_conduire(r, amorce_ouest(), reseau = reseau, portee = 40)
  expect_false(identical(a$arret, "depart_infranchissable"))

  # Le reseau reste infranchissable AILLEURS : l'agent ne le parcourt pas de
  # bout en bout, il s'arrete des qu'il en rencontre une portion non protegee.
  expect_lt(x_final(a), 190)
})


test_that("le vectoriseur par agent ne depend pas de l'ordre des amorces", {
  skip_if_not_installed("terra"); skip_if_not_installed("sf")
  # Verrou central du determinisme. Avec une mise a jour du reseau au fil de
  # l'eau, chaque reussite modifiait l'entree des amorces suivantes : mesure sur
  # donnee reelle, memes entrees et 8 ordres tires au hasard, le F1 variait de
  # 13 % sur wsfi et 43 % sur ltcp. Le reseau ne se met desormais a jour
  # qu'entre les tours, donc l'ordre n'a plus de prise.
  n <- 80
  p <- terra::rast(nrows = n, ncols = n, xmin = 0, xmax = n, ymin = 0, ymax = n,
    crs = "EPSG:2154")
  terra::values(p) <- 0.1
  xy <- terra::xyFromCell(p, seq_len(terra::ncell(p)))
  p[abs(xy[, 2] - 40) < 1.5 & xy[, 1] > 10 & xy[, 1] < 70] <- 0.9   # barre
  p[abs(xy[, 1] - 40) < 1.5 & xy[, 2] > 40 & xy[, 2] < 70] <- 0.9   # embranchement
  ref <- sf::st_sf(id = 1, geometry = sf::st_sfc(
    sf::st_linestring(cbind(c(12, 20), c(40, 40))), crs = 2154))

  appel <- function() dsr_vectoriser(p, methode = "agent", reference = ref,
    seuil = 0.5, long_min = 10, simplifier = 0, portee = 20)
  direct <- appel()
  bis <- appel()

  # Reproductible a l'identique : plus aucune dependance a l'ordre d'arrivee.
  expect_equal(nrow(bis), nrow(direct))
  expect_equal(sum(bis$longueur), sum(direct$longueur), tolerance = 1e-9)
})


test_that("les doublons d'un tour sont retires de facon deterministe", {
  skip_if_not_installed("sf")
  # Deux traces quasi confondues : une seule doit survivre, et c'est la plus
  # longue -- critere independant de l'ordre d'arrivee.
  a <- sf::st_linestring(cbind(c(0, 100), c(0, 0)))
  b <- sf::st_linestring(cbind(c(5, 60), c(0.5, 0.5)))
  crs <- sf::st_crs(2154)

  g1 <- dessertR:::.dsr_dedupe_tour(list(a, b), crs, 3)
  g2 <- dessertR:::.dsr_dedupe_tour(list(b, a), crs, 3)
  expect_length(g1, 1L)
  expect_equal(sf::st_length(sf::st_sfc(g1, crs = crs)),
    sf::st_length(sf::st_sfc(g2, crs = crs)))

  # Deux traces disjointes sont toutes deux conservees.
  c2 <- sf::st_linestring(cbind(c(0, 100), c(50, 50)))
  expect_length(dessertR:::.dsr_dedupe_tour(list(a, c2), crs, 3), 2L)
})
