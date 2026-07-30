# Les deux fonctions d'acquisition s'appuient sur le BINAIRE curl, pas sur le
# paquet R du meme nom. `skip_if_offline()` exige ce dernier et echoue sous
# R CMD check, ou il n'est pas installe : on teste donc ce dont le code depend
# reellement, puis la joignabilite.
skip_si_hors_ligne <- function(url = "https://overpass-api.de/api/status") {
  testthat::skip_on_cran()
  if (!nzchar(Sys.which("curl"))) testthat::skip("binaire curl absent")
  code <- tryCatch(
    system2("curl", c("-s", "--max-time", "10", "-o", "/dev/null",
      "-w", "%{http_code}", shQuote(url)), stdout = TRUE),
    error = function(e) character(0))
  if (!length(code) || !grepl("^2", code[1])) testthat::skip("reseau indisponible")
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


test_that("le decoupage suit la grille kilometrique Lidar HD", {
  emp <- sf::st_as_sfc(sf::st_bbox(
    c(xmin = 737230, ymin = 6384239, xmax = 739230, ymax = 6386239), crs = 2154))
  tu <- .dsr_tuiles(emp)

  # Emprise de 2 x 2 km a cheval : elle touche 3 x 3 dalles kilometriques.
  expect_equal(length(tu), 9L)
  # Chaque tuile est calee sur un multiple du kilometre, pas sur l'emprise.
  coins <- vapply(tu, function(b) as.numeric(b["xmin"]), numeric(1))
  expect_true(all(coins %% 1000 == 0))
  expect_true(all(vapply(tu, function(b) as.numeric(b["xmax"] - b["xmin"]), numeric(1)) == 1000))

  # Un cote different est respecte.
  expect_lt(length(.dsr_tuiles(emp, cote = 2000)), 9L)

  # Le decoupage ne depend pas du CRS : une emprise sans CRS se decoupe aussi.
  # (Le lier a l'appartenance faisait rendre zero tuile en silence.)
  sans_crs <- sf::st_as_sfc(sf::st_bbox(
    c(xmin = 0, ymin = 0, xmax = 2000, ymax = 2000)))
  expect_equal(length(.dsr_tuiles(sans_crs)), 9L)
  # Mais dsr_osm, lui, exige un CRS et le dit.
  expect_error(dsr_osm(sans_crs), "CRS")
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
})


test_that("dsr_osm rapporte le reseau OSM decoupe par dalle", {
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
  # Deduplication : une voie a cheval sur deux dalles n'est rendue qu'une fois.
  if ("osm_id" %in% names(osm)) expect_false(any(duplicated(osm$osm_id)))
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
