# Classement des lineaires detectes. On verifie la CASCADE et les garde-fous,
# pas la justesse forestiere des classes -- celle-la se valide sur le terrain.

ligne <- function(y, x = c(0, 100)) sf::st_linestring(cbind(x, c(y, y)))
peigne4 <- function(pas = 20) sf::st_sf(
  geometry = sf::st_sfc(lapply(seq(0, 3 * pas, by = pas), ligne), crs = 2154))

test_that("dsr_peignes repere un faisceau regulier et estime son espacement", {
  skip_if_not_installed("sf")
  p <- dsr_peignes(peigne4(20))
  expect_true(all(p$PEIGNE == 1L))
  expect_true(all(p$PEIGNE_N == 4L))
  expect_equal(unique(p$PEIGNE_ESPACEMENT), 20)
})

test_that("dsr_peignes laisse hors peigne ce qui n'en est pas un", {
  skip_if_not_installed("sf")
  # Une trace isolee.
  iso <- sf::st_sf(geometry = sf::st_sfc(ligne(0), crs = 2154))
  expect_true(all(is.na(dsr_peignes(iso)$PEIGNE)))

  # Trop peu de dents : deux paralleles ne font pas un peigne.
  deux <- sf::st_sf(geometry = sf::st_sfc(list(ligne(0), ligne(20)), crs = 2154))
  expect_true(all(is.na(dsr_peignes(deux)$PEIGNE)))

  # Espacement 20, 20 puis 5 m : la trace intruse perd sa place, le peigne des
  # trois premieres tient.
  irr <- sf::st_sf(geometry = sf::st_sfc(
    list(ligne(0), ligne(20), ligne(40), ligne(45)), crs = 2154))
  p <- dsr_peignes(irr)
  expect_equal(which(!is.na(p$PEIGNE)), 1:3)
  expect_equal(unique(p$PEIGNE_ESPACEMENT[1:3]), 20)

  # Au-dela d'espacement_max, plus de peigne du tout.
  loin <- sf::st_sf(geometry = sf::st_sfc(
    lapply(seq(0, 3 * 200, by = 200), ligne), crs = 2154))
  expect_true(all(is.na(dsr_peignes(loin)$PEIGNE)))
})

test_that("dsr_peignes ne confond pas 179 et 1 degre", {
  skip_if_not_installed("sf")
  # Memes lignes, une sur deux tracee en sens inverse : meme direction
  # geometrique, angles bruts opposes. Le regroupement doit tenir.
  g <- list(ligne(0), sf::st_linestring(cbind(c(100, 0), c(20, 20))),
    ligne(40), sf::st_linestring(cbind(c(100, 0), c(60, 60))))
  p <- dsr_peignes(sf::st_sf(geometry = sf::st_sfc(g, crs = 2154)))
  expect_true(all(p$PEIGNE == 1L))
})

test_that("la cascade : peigne -> cloisonnement, reference -> desserte", {
  skip_if_not_installed("sf")
  tr <- peigne4(20)
  r <- dsr_classer(tr)
  expect_true(all(r$CLASSE == "cloisonnement_exploitation"))
  expect_true(all(r$OSM_TAGS == "man_made=cutline;cutline=loggingmachine"))

  # La reference fait autorite pour l'existence : la dent qu'elle porte est une
  # desserte, meme alignee sur le peigne.
  ref <- sf::st_sfc(ligne(0), crs = 2154)
  r2 <- dsr_classer(tr, reference = ref)
  expect_equal(r2$CLASSE[1], "desserte")
  expect_equal(r2$OSM_TAGS[1], "highway=track")  # pas de surface sans NDVI
  expect_true(all(r2$CLASSE[-1] == "cloisonnement_exploitation"))
})

test_that("les fosses suffisent a faire une desserte hors reference", {
  skip_if_not_installed("sf")
  tr <- sf::st_sf(troncon = 1L, geometry = sf::st_sfc(ligne(0), crs = 2154))
  st <- data.frame(troncon = 1L, FOSSES = c(1, 1, 0, 1, 1))
  r <- dsr_classer(tr, stations = st)
  expect_equal(r$CLASSE, "desserte")
  expect_match(r$CLASSE_MOTIF, "fosses")
})

test_that("faute de critere, la classe reste indeterminee et la confiance basse", {
  skip_if_not_installed("sf")
  tr <- sf::st_sf(geometry = sf::st_sfc(ligne(0), crs = 2154))
  r <- dsr_classer(tr)
  expect_equal(r$CLASSE, "indetermine")
  # seul le peigne est evaluable sur une trace nue : 1 critere sur 7.
  expect_equal(r$CLASSE_CONF, 1 / 7)
  expect_true(is.na(r$OSM_TAGS))              # aucune proposition de balisage
  expect_match(r$CLASSE_MOTIF, "!peigne")     # negatif etabli
  expect_match(r$CLASSE_MOTIF, "minerale\\?") # inconnu, et dit comme tel
})

test_that("le parcellaire fait sortir un layon", {
  skip_if_not_installed("sf")
  tr <- sf::st_sf(geometry = sf::st_sfc(ligne(0), crs = 2154))
  limite <- sf::st_sfc(ligne(0.5), crs = 2154)   # a 0,5 m de la trace
  r <- dsr_classer(tr, parcellaire = limite)
  expect_equal(r$CLASSE, "layon_parcellaire")
  expect_equal(r$OSM_TAGS, "man_made=cutline;cutline=section")

  # Parcellaire cadastral : limite de PROPRIETE, pas de parcelle de gestion.
  # La geometrie est la meme, seul l'appelant sait ce qu'il a charge.
  r2 <- dsr_classer(tr, parcellaire = limite, sous_type_parcelle = "border")
  expect_equal(r2$OSM_TAGS, "man_made=cutline;cutline=border")

  expect_error(dsr_classer(tr, parcellaire = limite,
    sous_type_parcelle = "cadastre"), "should be one of")
})

test_that("aucun tag d'acces sans attestation, et provenance quand il y en a une", {
  skip_if_not_installed("sf")
  tr <- peigne4(20)

  # Par defaut : rien. Un panneau ne se lit pas dans un MNT.
  expect_false(any(grepl("access=", dsr_classer(tr)$OSM_TAGS)))

  pan <- sf::st_sf(access = "private", source = "photo:jn-2026-0142",
    geometry = sf::st_sfc(sf::st_point(c(50, 0)), crs = 2154))
  r <- dsr_classer(tr, panneaux = pan)
  expect_match(r$OSM_TAGS[1], "access=private")
  expect_match(r$OSM_TAGS[1], "source:access=photo:jn-2026-0142")
  expect_match(r$CLASSE_MOTIF[1], "acces_atteste")
  expect_false(grepl("access=", r$OSM_TAGS[4]))   # panneau trop loin

  # Sans colonne `source`, la provenance retombe sur `survey`.
  pan2 <- pan; pan2$source <- NULL
  expect_match(dsr_classer(tr, panneaux = pan2)$OSM_TAGS[1], "source:access=survey")
})

test_that("deux panneaux contradictoires n'emettent aucun acces", {
  skip_if_not_installed("sf")
  tr <- peigne4(20)
  pan <- sf::st_sf(access = c("private", "yes"),
    geometry = sf::st_sfc(sf::st_point(c(40, 0)), sf::st_point(c(60, 0)),
      crs = 2154))
  r <- dsr_classer(tr, panneaux = pan)
  expect_false(grepl("access=", r$OSM_TAGS[1]))
  expect_match(r$CLASSE_MOTIF[1], "acces_contradictoire")
})

test_that("garde-fous de dsr_classer", {
  skip_if_not_installed("sf")
  expect_error(dsr_classer("pas un sf"), "sf")
  tr <- sf::st_sf(geometry = sf::st_sfc(ligne(0), crs = 2154))
  expect_error(dsr_classer(tr[0, ]), "vide")
  expect_error(dsr_classer(tr, stations = data.frame(x = 1)), "troncon")
  pan <- sf::st_sf(x = 1, geometry = sf::st_sfc(sf::st_point(c(50, 0)), crs = 2154))
  expect_error(dsr_classer(tr, panneaux = pan), "access")
  expect_error(dsr_peignes(tr, espacement_min = 50, espacement_max = 10),
    "espacement_min")
})

test_that("le sous-type de parcellaire n'est pas suppose en silence", {
  skip_if_not_installed("sf")
  tr <- sf::st_sf(geometry = sf::st_sfc(ligne(0), crs = 2154))
  limite <- sf::st_sfc(ligne(0.5), crs = 2154)

  # Parcellaire fourni sans dire ce qu'il est : la supposition est annoncee.
  expect_message(r <- dsr_classer(tr, parcellaire = limite), "section")
  expect_equal(r$OSM_TAGS, "man_made=cutline;cutline=section")

  # Declare : rien a dire.
  expect_no_message(dsr_classer(tr, parcellaire = limite,
                                sous_type_parcelle = "border"))
  # Sans parcellaire, l'argument ne sert a rien : pas de message parasite.
  expect_no_message(dsr_classer(tr))
})

# --- Pare-feu : le relief seul ne suffit pas ---------------------------------
# Le critere de crete vient d'un TPI, que dsr_slrm() rend deja. Le piege est
# qu'une route forestiere suit souvent une crete : sans le canal optique, le
# relief seul classerait toutes ces routes en pare-feu.

relief <- function(crete = TRUE) {
  r <- terra::rast(nrows = 120, ncols = 120, xmin = 0, xmax = 120,
                   ymin = 0, ymax = 120, crs = "EPSG:2154")
  y <- terra::yFromCell(r, seq_len(terra::ncell(r)))
  # Crete : une arete a y = 50, altitude decroissant de part et d'autre.
  # Versant : plan incline, aucune position dominante.
  terra::values(r) <- if (crete) 20 - 0.4 * abs(y - 50) else 0.3 * y
  r
}
tpi_de <- function(r) dsr_slrm(r, fenetres_m = 30)

test_that("dsr_slrm a large fenetre distingue une crete d'un versant", {
  skip_if_not_installed("terra")
  axe <- sf::st_sfc(sf::st_linestring(cbind(c(10, 110), c(50, 50))), crs = 2154)
  pts <- sf::st_cast(sf::st_line_sample(axe, sample = seq(0, 1, length.out = 20)),
                     "POINT")
  v_crete <- terra::extract(tpi_de(relief(TRUE)), sf::st_coordinates(pts))[, 1]
  v_versant <- terra::extract(tpi_de(relief(FALSE)), sf::st_coordinates(pts))[, 1]
  expect_gt(stats::median(v_crete, na.rm = TRUE), 0.5)
  expect_lt(abs(stats::median(v_versant, na.rm = TRUE)), 0.5)
})

test_that("crete + surface non minerale donne un pare-feu", {
  skip_if_not_installed("terra")
  tr <- sf::st_sf(troncon = 1L, geometry = sf::st_sfc(
    sf::st_linestring(cbind(c(10, 110), c(50, 50))), crs = 2154))
  st <- data.frame(troncon = 1L, LARGEUR_ROULABLE = rep(6, 5))
  # NDVI eleve partout : aucune plage minerale, la surface est vegetalisee.
  # Otsu exige un contraste : le couvert est a 0,8, une clairiere minerale a
  # 0,05 -- mais LOIN de l'axe, qui reste vegetalise.
  ndvi <- terra::rast(nrows = 120, ncols = 120, xmin = 0, xmax = 120,
                      ymin = 0, ymax = 120, crs = "EPSG:2154")
  yv <- terra::yFromCell(ndvi, seq_len(terra::ncell(ndvi)))
  terra::values(ndvi) <- ifelse(abs(yv - 95) <= 2, 0.05, 0.8)

  r <- dsr_classer(tr, stations = st, ndvi = ndvi, tpi = tpi_de(relief(TRUE)))
  expect_equal(r$CLASSE, "pare_feu")
  expect_equal(r$OSM_TAGS, "man_made=cutline;cutline=firebreak")
  expect_match(r$CLASSE_MOTIF, "crete")
})

test_that("une route en crete reste une desserte, pas un pare-feu", {
  skip_if_not_installed("terra")
  # LE piege : le trace de desserte suit volontiers les cretes. C'est la
  # conjonction avec la surface minerale qui tranche, pas le relief.
  tr <- sf::st_sf(troncon = 1L, geometry = sf::st_sfc(
    sf::st_linestring(cbind(c(10, 110), c(50, 50))), crs = 2154))
  st <- data.frame(troncon = 1L, LARGEUR_ROULABLE = rep(4, 5))
  ndvi <- terra::rast(nrows = 120, ncols = 120, xmin = 0, xmax = 120,
                      ymin = 0, ymax = 120, crs = "EPSG:2154")
  y <- terra::yFromCell(ndvi, seq_len(terra::ncell(ndvi)))
  terra::values(ndvi) <- ifelse(abs(y - 50) <= 2, 0.05, 0.8)  # chaussee minerale

  r <- dsr_classer(tr, stations = st, ndvi = ndvi, tpi = tpi_de(relief(TRUE)))
  expect_false(identical(r$CLASSE, "pare_feu"))
  expect_match(r$CLASSE_MOTIF, "crete")      # la crete EST vue
  expect_match(r$CLASSE_MOTIF, "\\+minerale") # mais la surface tranche
})

test_that("sans ndvi, le pare-feu n'est jamais pose", {
  skip_if_not_installed("terra")
  tr <- sf::st_sf(geometry = sf::st_sfc(
    sf::st_linestring(cbind(c(10, 110), c(50, 50))), crs = 2154))
  r <- dsr_classer(tr, tpi = tpi_de(relief(TRUE)))
  expect_equal(r$CLASSE, "indetermine")
  expect_match(r$CLASSE_MOTIF, "minerale\\?")
})

test_that("garde-fou sur tpi", {
  skip_if_not_installed("terra")
  tr <- sf::st_sf(geometry = sf::st_sfc(ligne(0), crs = 2154))
  expect_error(dsr_classer(tr, tpi = "pas un raster"), "SpatRaster")
})
