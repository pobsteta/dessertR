# Emprise normative Certu (fiche 1.7). On verifie la transcription de la table
# et la detection de schema -- pas la justesse de la fiche, qui est une norme.

test_that("la table Certu est transcrite integralement et sans doublon", {
  tab <- .dsr_certu_table()
  expect_equal(nrow(tab), 97)
  cle <- paste(tab$cl_admin, tab$nature, tab$franchissement, tab$nb_voies)
  expect_equal(anyDuplicated(cle), 0)
  expect_true(all(tab$largeur_corrigee >= 0))
  expect_true(all(tab$largeur_buffer > 0))
})

test_that("les classes forestieres valent bien 2 m de chaussee", {
  tab <- .dsr_certu_table()
  # comparaison sur libelles normalises : l'encodage des accents varie selon la
  # chaine de lecture, et ce test ne doit pas dependre de cela.
  forest <- tab[.dsr_normaliser(tab$cl_admin) == "autre" &
    tab$franchissement == "NC" &
    .dsr_normaliser(tab$nature) %in%
      c("chemin", "sentier", "route empierree"), ]
  expect_equal(nrow(forest), 3)
  # c'est LE point : la fiche rend une constante, donc ne peut pas calibrer
  expect_equal(unique(forest$largeur_corrigee), 2)
  expect_equal(unique(forest$largeur_buffer), 1)
})

bdtopo_v2 <- function() {
  sf::st_sf(
    cl_admin = c("Autre", "Autre", "Départementale"),
    nature = c("Chemin", "Route empierrée", "Route à 1 chaussée"),
    franchisst = c("NC", "NC", "NC"),
    nb_voies = c(0L, 0L, 1L),
    geometry = sf::st_sfc(
      sf::st_linestring(cbind(c(0, 100), c(0, 0))),
      sf::st_linestring(cbind(c(0, 100), c(20, 20))),
      sf::st_linestring(cbind(c(0, 100), c(40, 40))), crs = 2154)
  )
}

test_that("schema v2 : detection automatique et largeurs attendues", {
  skip_if_not_installed("sf")
  r <- dsr_emprise_certu(bdtopo_v2())
  expect_equal(attr(r, "certu")$schema, "v2")
  expect_equal(r$LARGEUR_CHAUSSEE_CERTU, c(2, 2, 3))
  expect_equal(r$LARGEUR_EMPRISE_CERTU, c(2, 2, 6))   # 2 x largeur_buffer
  expect_length(attr(r, "certu")$non_apparies, 0)
})

test_that("schema v3 : pos_sol tient lieu de franchissement", {
  skip_if_not_installed("sf")
  v3 <- bdtopo_v2()
  v3$franchisst <- NULL
  names(v3)[names(v3) == "nature"] <- "NATURE"
  v3$POS_SOL <- c(0L, 1L, 0L)    # sol, pont, sol
  names(v3)[names(v3) == "cl_admin"] <- "CL_ADMIN"
  names(v3)[names(v3) == "nb_voies"] <- "NB_VOIES"

  r <- dsr_emprise_certu(v3)
  expect_equal(attr(r, "certu")$schema, "v3")
  expect_equal(r$LARGEUR_CHAUSSEE_CERTU, c(2, 2, 3))  # Chemin/empierree/RD
  expect_length(attr(r, "certu")$non_apparies, 0)
  # le pont annule la berme, conformement a la fiche
  expect_equal(r$BERME_CERTU[2], 0)
})

test_that("la table de la fiche est creuse : les trous sont signales", {
  skip_if_not_installed("sf")
  # « Departementale / Route a 1 chaussee / Tunnel » n'existe qu'a 2 voies
  x <- sf::st_sf(
    cl_admin = "Départementale", nature = "Route à 1 chaussée",
    franchisst = "Tunnel", nb_voies = 1L,
    geometry = sf::st_sfc(sf::st_linestring(cbind(c(0, 10), c(0, 0))),
      crs = 2154))
  expect_message(r <- dsr_emprise_certu(x), "correspondance")
  expect_true(is.na(r$LARGEUR_CHAUSSEE_CERTU))

  x$nb_voies <- 2L
  expect_silent(r2 <- dsr_emprise_certu(x))
  expect_equal(r2$LARGEUR_CHAUSSEE_CERTU, 6)
})

test_that("schema v3 : la nature 'Type autoroutier' est ramenee a la fiche", {
  skip_if_not_installed("sf")
  v3 <- sf::st_sf(
    CL_ADMIN = "Autoroute", NATURE = "Type autoroutier",
    NB_VOIES = 2L, POS_SOL = 0L,
    geometry = sf::st_sfc(sf::st_linestring(cbind(c(0, 100), c(0, 0))),
      crs = 2154))
  r <- dsr_emprise_certu(v3)
  expect_equal(r$LARGEUR_CHAUSSEE_CERTU, 7)
  expect_equal(r$LARGEUR_EMPRISE_CERTU, 24)
})

test_that("les combinaisons inconnues sont signalees, pas defautees", {
  skip_if_not_installed("sf")
  x <- bdtopo_v2()
  x$nature[1] <- "Nature inventee"
  expect_message(r <- dsr_emprise_certu(x), "correspondance")
  expect_true(is.na(r$LARGEUR_CHAUSSEE_CERTU[1]))
  expect_length(attr(r, "certu")$non_apparies, 1)
  expect_equal(attr(r, "certu")$n_apparies, 2)
})

test_that("emprise = TRUE renvoie des polygones de largeur coherente", {
  skip_if_not_installed("sf")
  res <- dsr_emprise_certu(bdtopo_v2(), emprise = TRUE)
  expect_named(res, c("troncons", "emprise"))
  expect_s3_class(res$emprise, "sf")
  # tampon plat de 1 m de part et d'autre sur 100 m -> ~200 m2 pour un chemin
  a <- as.numeric(sf::st_area(res$emprise))
  expect_equal(a[1], 200, tolerance = 0.05)
})

test_that("l'appariement est insensible aux accents et a la casse", {
  skip_if_not_installed("sf")
  # sous une locale C, un accent mal lu se scinde en deux octets et
  # l'appariement echouerait en silence sur nos classes forestieres.
  mk <- function(nat) sf::st_sf(cl_admin = "Autre", nature = nat,
    franchisst = "NC", nb_voies = 0L,
    geometry = sf::st_sfc(sf::st_linestring(cbind(c(0, 100), c(0, 0))),
      crs = 2154))
  for (nat in c("Route empierr\u00e9e", "Route empierree", "ROUTE EMPIERREE")) {
    r <- dsr_emprise_certu(mk(nat))
    expect_equal(r$LARGEUR_CHAUSSEE_CERTU, 2)
    expect_length(attr(r, "certu")$non_apparies, 0)
  }
  expect_identical(
    .dsr_normaliser("D\u00e9partementale"), .dsr_normaliser("Departementale"))
})

test_that("garde-fous d'entree", {
  skip_if_not_installed("sf")
  expect_error(dsr_emprise_certu("pas un sf"), "sf")
  nu <- sf::st_sf(x = 1, geometry = sf::st_sfc(
    sf::st_linestring(cbind(c(0, 1), c(0, 1))), crs = 2154))
  expect_error(dsr_emprise_certu(nu), "introuvables")
})
