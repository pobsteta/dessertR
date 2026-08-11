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
  # seul le peigne est evaluable sur une trace nue : 1 critere sur 6.
  expect_equal(r$CLASSE_CONF, 1 / 6)
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
