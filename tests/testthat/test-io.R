un_trace <- function() sf::st_sf(id = 1, geometry = sf::st_sfc(
  sf::st_linestring(cbind(c(0, 10), c(0, 0))), crs = 2154))

test_that("dsr_export_gpkg ecrit une couche par element nomme", {
  skip_if_not_installed("sf")
  f <- tempfile(fileext = ".gpkg")
  dsr_export_gpkg(list(trace = un_trace(), stations = un_trace()), f, styles = FALSE)
  expect_setequal(sf::st_layers(f)$name, c("trace", "stations"))
})

test_that("dsr_export_gpkg rejette une couche non sf et une liste non nommee", {
  skip_if_not_installed("sf")
  f <- tempfile(fileext = ".gpkg")
  expect_error(dsr_export_gpkg(list(x = 1L), f), "non vectorielles")
  expect_error(dsr_export_gpkg(list(un_trace()), f), "nommee")
})

test_that("dsr_export_gpkg ecrit le style QML de l'etat", {
  skip_if_not_installed("sf")
  et <- sf::st_sf(etat = factor("en_service"), geometry = sf::st_sfc(
    sf::st_linestring(cbind(c(0, 5), c(0, 0))), crs = 2154))
  f <- tempfile(fileext = ".gpkg")
  dsr_export_gpkg(list(etat = et), f, styles = TRUE)
  expect_true(file.exists(sub("\\.gpkg$", "_etat.qml", f)))
})

test_that("dsr_qml_categorise ecrit un QML XML valide et categorise", {
  skip_if_not_installed("sf")
  skip_if_not_installed("xml2")
  f <- tempfile(fileext = ".qml")
  dsr_qml_categorise(f, champ = "etat", valeurs = c("a", "b"),
    couleurs = c("34,139,34", "220,20,20"))
  doc <- xml2::read_xml(f)
  expect_length(xml2::xml_find_all(doc, "//category"), 2)
  expect_equal(xml2::xml_attr(xml2::xml_find_first(doc, "//renderer-v2"), "attr"), "etat")
})

test_that("dsr_qml_categorise : couleurs et valeurs de tailles differentes -> erreur", {
  f <- tempfile(fileext = ".qml")
  expect_error(dsr_qml_categorise(f, "x", c("a", "b"), couleurs = "1,2,3"), "autant")
})

test_that("dsr_rapport assemble les metriques et ecrit un .md", {
  m <- list(resume = list(LARGEUR_ROULABLE_MED = 3.2, PENTE_LONG_MOY = 0.05,
    PENTE_LONG_MAX = 0.12, RAYON_COURBURE_MIN = 15, SINUOSITE = 1.2))
  txt <- dsr_rapport(mesure = m)
  expect_true(grepl("Largeur roulable mediane : 3.2 m", txt))
  f <- tempfile(fileext = ".md")
  dsr_rapport(mesure = m, fichier = f)
  expect_true(file.exists(f))
})
