# Aucun test de ce fichier ne doit taper le reseau : le transport est mocke.
# Les deux seuls qui le font sont explicitement gardes par `skip_si_hors_ligne()`
# et sautent sous R CMD check.
skip_si_hors_ligne <- function(url = "https://overpass-api.de/api/status") {
  testthat::skip_on_cran()
  # On teste la JOIGNABILITE, pas le code de retour : la Geoplateforme repond
  # 400 a un HEAD, ce qui prouve justement qu'elle repond. Seule l'absence de
  # reponse fait sauter le test.
  ok <- tryCatch({
    h <- curl::new_handle(timeout = 10, connecttimeout = 5)
    is.numeric(curl::curl_fetch_memory(url, handle = h)$status_code)
  }, error = function(e) FALSE)
  if (!isTRUE(ok)) testthat::skip("reseau indisponible")
}

# XML Overpass de synthese. Le driver OSM de GDAL lit un fichier `.osm` reel :
# c'est bien la lecture qu'on teste, pas une imitation.
osm_avec_way <- paste0(
  '<?xml version="1.0" encoding="UTF-8"?>\n',
  '<osm version="0.6" generator="test">\n',
  '  <node id="1" lat="44.550" lon="3.460"/>\n',
  '  <node id="2" lat="44.560" lon="3.470"/>\n',
  '  <way id="10">\n',
  '    <nd ref="1"/><nd ref="2"/>\n',
  '    <tag k="highway" v="track"/>\n',
  '  </way>\n',
  "</osm>\n")

osm_vide <- paste0(
  '<?xml version="1.0" encoding="UTF-8"?>\n',
  '<osm version="0.6" generator="test">\n',
  '  <note>The data included in this document is from www.openstreetmap.org.</note>\n',
  "</osm>\n")

osm_remark <- paste0(
  '<?xml version="1.0" encoding="UTF-8"?>\n',
  '<osm version="0.6" generator="test">\n',
  '  <note>The data included in this document is from www.openstreetmap.org.</note>\n',
  '  <remark> runtime error: Query timed out in "recurse" at line 3 </remark>\n',
  "</osm>\n")

osm_remark_quota <- paste0(
  '<?xml version="1.0" encoding="UTF-8"?>\n',
  '<osm version="0.6" generator="test">\n',
  '  <note>The data included in this document is from www.openstreetmap.org.</note>\n',
  '  <remark> runtime error: Dispatcher_Client rate_limited, slot available after 42 s </remark>\n',
  "</osm>\n")

reponse <- function(txt, code = 200L, entetes = "") {
  list(status_code = code, content = charToRaw(txt),
       headers = charToRaw(entetes))
}

# Un `sf` OSM de synthese, en WGS84 comme le rend le driver.
faux_osm <- function(ids) {
  g <- sf::st_sfc(lapply(seq_along(ids), function(i) {
    sf::st_linestring(matrix(c(3.462, 44.552, 3.468, 44.558), ncol = 2,
                             byrow = TRUE))
  }), crs = 4326)
  sf::st_sf(osm_id = as.character(ids), highway = "track", geometry = g)
}

emprise_test <- function() {
  sf::st_transform(sf::st_as_sfc(sf::st_bbox(
    c(xmin = 3.45, ymin = 44.54, xmax = 3.50, ymax = 44.58), crs = 4326)), 2154)
}


test_that("dsr_valider_dalles accepte plusieurs dalles et nomme les manquantes", {
  f1 <- tempfile(fileext = ".laz"); file.create(f1)
  f2 <- tempfile(fileext = ".laz"); file.create(f2)
  on.exit(unlink(c(f1, f2)), add = TRUE)

  # Le point du correctif : un VECTEUR passe. L'ancienne garde testait
  # `!file.exists(dalle)` dans un `if`, ce qui erre des le second element -- et
  # la branche `concurrent_files` de dsr_strategie_lasr() etait donc morte.
  expect_equal(dsr_valider_dalles(c(f1, f2)), c(f1, f2))
  expect_equal(dsr_valider_dalles(f1), f1)

  expect_error(dsr_valider_dalles(c(f1, "/introuvable.laz")), "1 fichier introuvable")
  expect_error(dsr_valider_dalles(c("/a.laz", "/b.laz")), "2 fichiers introuvables")
  expect_error(dsr_valider_dalles(42), "chemins de fichiers")
  expect_error(dsr_valider_dalles(character(0)), "chemins de fichiers")
})


test_that("la requete Overpass est bien formee et en ordre (S, W, N, E)", {
  # bbox_wgs est donne en (xmin, ymin, xmax, ymax) ; Overpass attend
  # (sud, ouest, nord, est). Inverser rend une reponse vide sans erreur.
  q <- .dsr_requete_overpass(c(3.46, 44.55, 3.49, 44.57), cle = "highway",
    valeur = c("track", "path"), timeout = 30)

  expect_match(q, "^\\[out:xml\\]\\[timeout:30\\];")
  expect_match(q, '\\["highway"~"track\\|path"\\]', perl = TRUE)
  expect_match(q, "\\(44\\.550000,3\\.460000,44\\.570000,3\\.490000\\)")

  # Sans valeur : la cle seule, sans operateur de regex.
  q2 <- .dsr_requete_overpass(c(3.46, 44.55, 3.49, 44.57), cle = "highway")
  expect_match(q2, '\\["highway"\\]', perl = TRUE)
  expect_false(grepl("~", q2, fixed = TRUE))
})


test_that("une emprise est acceptee sous toutes ses formes", {
  r <- terra::rast(nrows = 10, ncols = 10, xmin = 0, xmax = 100, ymin = 0,
                   ymax = 100, crs = "EPSG:2154")
  attendu <- c(xmin = 0, ymin = 0, xmax = 100, ymax = 100)

  for (x in list(r, sf::st_as_sfc(sf::st_bbox(r)),
                 sf::st_sf(geometry = sf::st_as_sfc(sf::st_bbox(r))))) {
    g <- .dsr_emprise_sfc(x)
    expect_s3_class(g, "sfc")
    expect_equal(as.numeric(sf::st_bbox(g))[c(1, 2, 3, 4)],
                 unname(attendu[c("xmin", "ymin", "xmax", "ymax")]))
  }
  expect_error(.dsr_emprise_sfc("pas une emprise"), "non reconnu")

  # dsr_osm exige un CRS et le dit : sans lui, la bbox n'est pas reprojetable
  # en WGS84 et il n'y a rien a demander a Overpass.
  sans_crs <- sf::st_as_sfc(sf::st_bbox(c(xmin = 0, ymin = 0, xmax = 2000, ymax = 2000)))
  expect_error(dsr_osm(sans_crs), "CRS")
})


# --- Le contrat des trois issues (une ligne du tableau par bloc) -------------

test_that("un XML porteur de donnees est lu comme des donnees", {
  local_mocked_bindings(.dsr_overpass_curl = function(url, ql, timeout) {
    reponse(osm_avec_way)
  })
  rep <- .dsr_transport_overpass("req", timeout = 5)
  expect_equal(rep$instance, DSR_SERVEURS_OVERPASS[1])
  expect_match(rep$date, "^\\d{4}-\\d{2}-\\d{2}T")

  g <- .dsr_lire_osm(rep$corps)
  skip_if(!nrow(g), "driver OSM de GDAL indisponible")
  expect_s3_class(g, "sf")
  expect_equal(names(g), c("osm_id", "highway", "geometry"))
  expect_equal(g$highway[1], "track")
})


test_that("un vide legitime est un resultat, pas une erreur", {
  # XML valide, aucune voie, AUCUN remark : OSM ne porte rien ici. Le
  # distinguer d'un refus est tout l'objet de ce fichier.
  local_mocked_bindings(.dsr_overpass_curl = function(url, ql, timeout) {
    reponse(osm_vide)
  })
  expect_no_error(rep <- .dsr_transport_overpass("req", timeout = 5))
  g <- .dsr_lire_osm(rep$corps)
  expect_s3_class(g, "sf")
  expect_equal(nrow(g), 0L)
  # Les colonnes sont posees meme sans donnee : sinon le rbind des quadrants
  # echouerait sur le premier quadrant vide.
  expect_equal(names(g), c("osm_id", "highway", "geometry"))
})


test_that("un remark est un REFUS, jamais une couche vide", {
  local_mocked_bindings(.dsr_overpass_curl = function(url, ql, timeout) {
    reponse(osm_remark)
  })
  # Le message doit porter le texte du remark : c'est lui qui dit pourquoi.
  expect_error(.dsr_transport_overpass("req", timeout = 5, serveurs = "u"),
    "Query timed out", class = "dsr_overpass_refus")
  cnd <- tryCatch(.dsr_transport_overpass("req", 5, serveurs = "u"),
    error = function(e) e)
  # « timed out » se traite en decoupant l'emprise, pas en changeant d'instance.
  expect_equal(cnd$statut, "volume")
})


test_that("un 429 fait tourner l'instance, et la bascule se dit", {
  vus <- character(0)
  local_mocked_bindings(.dsr_overpass_curl = function(url, ql, timeout) {
    vus <<- c(vus, url)
    if (url == "s1") reponse("", 429L) else reponse(osm_avec_way)
  })
  expect_message(
    rep <- .dsr_transport_overpass("req", timeout = 5, serveurs = c("s1", "s2"),
      max_reprises = 0),
    "repli")
  expect_equal(rep$instance, "s2")
  expect_equal(vus, c("s1", "s2"))
})


test_that("toutes les instances en echec : l'erreur relaie la derniere cause", {
  local_mocked_bindings(.dsr_overpass_curl = function(url, ql, timeout) {
    if (url == "s1") reponse("", 429L) else reponse("court", 200L)
  })
  expect_error(
    .dsr_transport_overpass("req", timeout = 5, serveurs = c("s1", "s2"),
      max_reprises = 0),
    "corps de 5 octets", class = "dsr_overpass_refus")
})


test_that("le verdict distingue quota, duree et volume", {
  # 429 : quota -> on tourne. 504 : duree -> bissectable. Confondre les deux
  # ferait decouper sur un quota, ce qui multiplie les requetes refusees.
  expect_equal(.dsr_overpass_verdict(reponse("", 429L))$statut, "quota")
  expect_equal(.dsr_overpass_verdict(reponse("", 504L))$statut, "timeout")
  expect_equal(.dsr_overpass_verdict(reponse("", 500L))$statut, "http")
  expect_equal(.dsr_overpass_verdict(reponse("trop court"))$statut, "tronque")
  expect_equal(.dsr_overpass_verdict(
    list(status_code = -1L, content = raw(0), erreur = "Timeout was reached")
  )$statut, "timeout")
  # Un remark de quota n'est PAS un remark de volume : le premier appelle une
  # rotation, le second un decoupage.
  expect_equal(.dsr_overpass_verdict(reponse(osm_remark_quota))$statut, "quota")

  # `Retry-After` court : on patiente. Long : on change d'instance.
  h <- "HTTP/1.1 429\r\nRetry-After: 3\r\n\r\n"
  expect_equal(.dsr_overpass_verdict(reponse("", 429L, h))$retry, 3)
})


# --- Delegation au client canonique (ADR-010 de foretaccess) -----------------

test_that("le client canonique est prefere, et une seule requete en sort", {
  vu <- NULL
  faux_client <- function(bbox_wgs, cle, timeout, serveurs, max_reprises,
                          couches) {
    vu <<- list(cle = cle, couches = couches)
    out <- faux_osm(7:8)
    out$name <- "Route forestiere" # colonne en trop : la sortie reste a deux
    attr(out, "instance") <- "https://canonique/interpreter"
    attr(out, "requete") <- "[out:xml];..."
    attr(out, "date_requete") <- "2026-08-13T00:00:00Z"
    out
  }
  local_mocked_bindings(.dsr_osm_delegue = function() faux_client)

  g <- .dsr_fetch_osm(c(xmin = 3.4, ymin = 44.5, xmax = 3.5, ymax = 44.6),
    cle = "highway", valeur = c("track", "path"))

  # Le client canonique ne prend qu'UNE valeur par filtre : plusieurs valeurs
  # doivent devenir une UNION dans la meme requete, pas une requete par valeur.
  expect_length(vu$cle, 2L)
  expect_equal(vu$cle[[1]], list(cle = "highway", valeur = "track"))
  expect_equal(vu$couches, "lines")
  # Les deux chemins rendent la meme chose : memes colonnes, meme provenance.
  expect_equal(names(g), c("osm_id", "highway", "geometry"))
  expect_equal(attr(g, "instance"), "https://canonique/interpreter")
  expect_equal(attr(g, "date_requete"), "2026-08-13T00:00:00Z")
})


test_that("le repli interne reste joignable sans foretaccess", {
  withr::local_options(dessertR.osm_delegue = FALSE)
  expect_null(.dsr_osm_delegue())
})


# --- Strategie : une requete, bissection en repli ----------------------------

test_that("le cas nominal ne fait qu'UNE requete", {
  n <- 0L
  local_mocked_bindings(.dsr_fetch_osm = function(bbox_wgs, cle, valeur = NULL,
                                                  timeout = 90, ...) {
    n <<- n + 1L
    faux_osm(1:3)
  })
  out <- dsr_osm(emprise_test(), pause = 0)
  # Le tuilage kilometrique en faisait 100 sur une emprise de 10 x 10 km.
  expect_equal(n, 1L)
  expect_s3_class(out, "sf")
  expect_equal(nrow(out), 3L)
  expect_equal(sf::st_crs(out), sf::st_crs(2154))
})


test_that("un refus de volume bissecte, un refus de quota non", {
  appels <- 0L
  local_mocked_bindings(.dsr_fetch_osm = function(bbox_wgs, cle, valeur = NULL,
                                                  timeout = 90, ...) {
    appels <<- appels + 1L
    if (appels == 1L) {
      cli::cli_abort("Query run out of memory", class = "dsr_overpass_refus",
        statut = "volume")
    }
    # Chaque quadrant reprend une voie de son voisin : le dedoublonnage sur
    # `osm_id` doit la rendre une seule fois.
    faux_osm(c(appels - 1L, appels))
  })
  expect_message(out <- dsr_osm(emprise_test(), pause = 0), "bissection")
  expect_equal(appels, 5L) # 1 emprise refusee + 4 quadrants
  # 4 quadrants x 2 voies, dont 3 partagees : 5 voies distinctes, pas 8.
  expect_equal(sort(out$osm_id), as.character(1:5))
  expect_false(any(duplicated(out$osm_id)))

  # Un quota ne se decoupe pas : decouper multiplierait les requetes refusees.
  appels <- 0L
  local_mocked_bindings(.dsr_fetch_osm = function(bbox_wgs, cle, valeur = NULL,
                                                  timeout = 90, ...) {
    appels <<- appels + 1L
    cli::cli_abort("HTTP 429", class = "dsr_overpass_refus", statut = "quota")
  })
  expect_error(dsr_osm(emprise_test(), pause = 0), "429")
  expect_equal(appels, 1L)
})


test_that("la bissection est bornee en profondeur et par `cote`", {
  appels <- 0L
  niveaux <- character(0)
  local_mocked_bindings(.dsr_fetch_osm = function(bbox_wgs, cle, valeur = NULL,
                                                  timeout = 90, ...) {
    appels <<- appels + 1L
    cli::cli_abort("Query run out of memory", class = "dsr_overpass_refus",
      statut = "volume")
  })
  # Un quadrant qui refuse jusqu'au bout emporte l'appel : PAS de resultat
  # partiel silencieux, c'est la meme regle qu'au transport -- un refus n'est
  # pas un vide. On descend donc 3 niveaux, puis l'erreur remonte.
  niveaux <- testthat::capture_messages(
    expect_error(dsr_osm(emprise_test(), pause = 0), "memory"))
  expect_equal(appels, 4L)
  expect_length(grep("bissection", niveaux), 3L)
  expect_match(paste(niveaux, collapse = " "), "niveau 3")

  # `cote` arrete plus tot : l'emprise fait ~4 km, un plancher a 2 km
  # n'autorise qu'un seul niveau de decoupage.
  appels <- 0L
  n2 <- testthat::capture_messages(
    expect_error(dsr_osm(emprise_test(), cote = 2000, pause = 0), "memory"))
  expect_equal(appels, 2L)
  expect_length(grep("bissection", n2), 1L)
})


# --- Cache et provenance -----------------------------------------------------

test_that("le cache evite la seconde requete, et la provenance date le resultat", {
  n <- 0L
  local_mocked_bindings(.dsr_fetch_osm = function(bbox_wgs, cle, valeur = NULL,
                                                  timeout = 90, ...) {
    n <<- n + 1L
    out <- faux_osm(1:2)
    attr(out, "instance") <- "https://exemple/interpreter"
    attr(out, "requete") <- "[out:xml];..."
    attr(out, "date_requete") <- "2026-08-13T10:00:00Z"
    out
  })
  d <- withr::local_tempdir()
  emp <- emprise_test()

  a <- dsr_osm(emp, pause = 0, cache_dir = d)
  b <- dsr_osm(emp, pause = 0, cache_dir = d)
  expect_equal(n, 1L)
  expect_equal(nrow(b), nrow(a))
  expect_equal(sort(b$osm_id), sort(a$osm_id))

  # OSM change tous les jours : sans date, deux executions a un mois d'ecart
  # different sans aucune trace.
  prov <- jsonlite::read_json(file.path(d, "osm.gpkg.provenance.json"),
    simplifyVector = TRUE)
  expect_equal(prov$acquisition$date_requete, "2026-08-13T10:00:00Z")
  expect_equal(prov$acquisition$instance, "https://exemple/interpreter")
  expect_equal(prov$acquisition$nb_entites, 2L)
  expect_equal(prov$acquisition$nb_requetes, 1L)
  expect_true(prov$acquisition$lineaire_km > 0)

  # Des parametres divergents invalident le cache : servir un reseau `track`
  # pour une demande `path` serait un faux silencieux.
  expect_message(dsr_osm(emp, valeurs = "path", pause = 0, cache_dir = d),
    "autres parametres")
  expect_equal(n, 2L)
})


test_that("politique_cache arbitre le cache divergent", {
  chemin <- file.path(withr::local_tempdir(), "osm.gpkg")
  file.create(chemin)
  .dsr_provenance_ecrire(chemin, "osm", "overpass", list(valeurs = "track"))

  expect_true(.dsr_cache_utilisable(chemin, "osm", "overpass",
    list(valeurs = "track")))
  expect_message(r <- .dsr_cache_utilisable(chemin, "osm", "overpass",
    list(valeurs = "path")), "Re-acquisition")
  expect_false(r)
  expect_warning(r <- .dsr_cache_utilisable(chemin, "osm", "overpass",
    list(valeurs = "path"), "avertir"), "tel quel")
  expect_true(r)
  expect_error(.dsr_cache_utilisable(chemin, "osm", "overpass",
    list(valeurs = "path"), "echouer"), "autres parametres")
  # « ignorer » ne controle rien : c'est le comportement anterieur au cache.
  expect_true(.dsr_cache_utilisable(chemin, "osm", "overpass",
    list(valeurs = "path"), "ignorer"))

  # Un cache SANS sidecar est traite comme divergent : on ne peut pas savoir,
  # donc on ne suppose pas.
  unlink(.dsr_chemin_provenance(chemin))
  expect_message(r <- .dsr_cache_utilisable(chemin, "osm", "overpass",
    list(valeurs = "track")), "sans provenance")
  expect_false(r)
})


# --- Reseau (sautes hors ligne) ----------------------------------------------

test_that("dsr_osm rapporte le reseau OSM en une requete", {
  skip_si_hors_ligne()
  emp <- sf::st_as_sfc(sf::st_bbox(
    c(xmin = 737500, ymin = 6385000, xmax = 738500, ymax = 6386000), crs = 2154))
  osm <- tryCatch(dsr_osm(emp, pause = 0), error = function(e) skip(conditionMessage(e)))
  skip_if(is.null(osm), "OSM ne porte rien sur cette emprise")

  expect_s3_class(osm, "sf")
  expect_true(all(sf::st_geometry_type(osm) == "LINESTRING"))
  expect_equal(sf::st_crs(osm), sf::st_crs(emp))
  # Decoupe sur l'emprise : rien ne depasse.
  bb <- sf::st_bbox(osm)
  expect_gte(as.numeric(bb["xmin"]), 737500 - 1)
  expect_lte(as.numeric(bb["xmax"]), 738500 + 1)
  expect_false(any(duplicated(osm$osm_id)))
})


test_that("dsr_ortho_ign rend une ortho IRC a la resolution demandee", {
  skip_si_hors_ligne(paste0("https://data.geopf.fr/wms-r/wms?SERVICE=WMS",
    "&REQUEST=GetCapabilities&VERSION=1.3.0"))
  emp <- sf::st_as_sfc(sf::st_bbox(
    c(xmin = 738100, ymin = 6385100, xmax = 738300, ymax = 6385300), crs = 2154))
  irc <- tryCatch(dsr_ortho_ign(emp, res = 0.2, pas = 200),
    error = function(e) NULL)
  skip_if(is.null(irc), "Geoplateforme indisponible")

  expect_s4_class(irc, "SpatRaster")
  expect_equal(terra::nlyr(irc), 3L)
  expect_equal(terra::res(irc)[1], 0.2, tolerance = 0.01)
  # Le CRS doit etre pose : le service l'omet parfois, et son absence fait
  # sortir des « CRS do not match » a chaque croisement ulterieur.
  expect_false(is.na(sf::st_crs(terra::crs(irc))))
  expect_equal(names(irc), c("pir", "rouge", "vert"))
  # Une image entierement NA signale un BBOX inverse (piege du WMS 1.3.0).
  expect_false(all(is.na(terra::values(irc[[1]]))))
})
