# La detection depend-elle encore de l'emprise qu'on lui passe ?
# ------------------------------------------------------------------------------
# Audit ForetAccess du 2026-07-31 (commit cb9376c) : dsr_detecter() rendait des
# resultats DIFFERENTS pour le meme terrain selon l'etendue soumise. Sur le bloc
# wsfi, une fenetre centrale de 0,25 km2 rendait 116 m de desserte analysee
# seule, et 0 m analysee au sein de 4 km2.
#
# Deux causes, independantes :
#
#   1. dsr_appartenance() derive ses bornes des quantiles de la donnee recue
#      quand `a`/`b` ne sont pas fournis -- et dsr_specs_geomorpho() ne les
#      fournit jamais. Le `seuil` n'est alors pas une quantite absolue mais un
#      RANG dans la population de l'emprise.
#
#   2. dsr_frangi() derive `c` du maximum de la norme du Hessien de l'image.
#      Celui-ci agit EN AMONT des appartenances : aucune borne ne le rattrape.
#
# Ce script mesure les deux, separement et ensemble, sur donnee reelle. Il ne
# demande pas le nuage de points : la dependance a l'emprise est entierement
# dans le canal geomorphologique.
#
# Usage :  Rscript dev/08_ancrage_emprise.R
#
#   DSR_WSFI   cache du projet
#   DSR_COTE   cote du bloc englobant, en metres (defaut 2000)
#   DSR_FEN    cote de la fenetre d'analyse, en metres (defaut 500)

suppressMessages({library(terra); library(sf)})

if (file.exists("DESCRIPTION") && requireNamespace("pkgload", quietly = TRUE)) {
  suppressMessages(pkgload::load_all(".", quiet = TRUE))
} else {
  library(dessertR)
}
set.seed(20260731)

cache <- Sys.getenv("DSR_WSFI",
  "/home/pascal/.local/share/nemeton/projects/20260717_101641_wsfi/cache")
cote <- as.numeric(Sys.getenv("DSR_COTE", "2000"))
fen_m <- as.numeric(Sys.getenv("DSR_FEN", "500"))

mnt_full <- terra::rast(file.path(cache, "layers", "lidar_mnt_mosaic.tif"))
roads_full <- sf::st_zm(sf::st_geometry(sf::st_read(
  file.path(cache, "layers", "roads.gpkg"), quiet = TRUE)), drop = TRUE)
ctr <- unname(sf::st_coordinates(sf::st_centroid(sf::st_union(roads_full)))[1, 1:2])

ext_carre <- function(demi) terra::intersect(
  terra::ext(ctr[1] - demi, ctr[1] + demi, ctr[2] - demi, ctr[2] + demi),
  terra::ext(mnt_full))

e_bloc <- ext_carre(cote / 2)
e_fen <- ext_carre(fen_m / 2)
mnt_bloc <- terra::crop(mnt_full, e_bloc)
mnt_fen <- terra::crop(mnt_full, e_fen)
cat(sprintf("Bloc %.2f km2 | fenetre %.2f km2\n",
  (terra::xmax(e_bloc) - terra::xmin(e_bloc)) *
    (terra::ymax(e_bloc) - terra::ymin(e_bloc)) / 1e6,
  (terra::xmax(e_fen) - terra::xmin(e_fen)) *
    (terra::ymax(e_fen) - terra::ymin(e_fen)) / 1e6))

emp_fen <- sf::st_as_sfc(sf::st_bbox(e_fen)); sf::st_crs(emp_fen) <- sf::st_crs(roads_full)
roads_fen <- suppressWarnings(sf::st_cast(
  sf::st_intersection(roads_full, emp_fen), "LINESTRING"))
roads_fen <- roads_fen[!sf::st_is_empty(roads_fen)]

# Marge de bord : les fenetres focales (openness, slrm, hessien) different sur
# le pourtour d'un recadrage. On compare l'INTERIEUR, sinon on mesure un effet
# de bord et non la dependance a l'emprise.
MARGE <- 25
e_cmp <- terra::ext(terra::xmin(e_fen) + MARGE, terra::xmax(e_fen) - MARGE,
  terra::ymin(e_fen) + MARGE, terra::ymax(e_fen) - MARGE)


# --- 1. Le `c` de Frangi, mesure ----------------------------------------------
ECH <- c(1, 2, 4)
g_bloc <- dsr_grille_reference(mnt_bloc, res = 1)
g_fen <- dsr_grille_reference(mnt_fen, res = 1)
c_bloc <- dsr_c_vessel(terra::resample(mnt_bloc, g_bloc, method = "bilinear"), ECH)
c_fen <- dsr_c_vessel(terra::resample(mnt_fen, g_fen, method = "bilinear"), ECH)
cat("\n== Le c de Frangi depend de l'emprise ==\n")
print(data.frame(echelle = ECH, c_fenetre = as.numeric(c_fen),
  c_bloc = as.numeric(c_bloc), rapport = as.numeric(c_bloc / c_fen)),
  row.names = FALSE, digits = 4)
cat(sprintf("  variation de c ENTRE echelles (bloc) : x%.2f\n",
  max(c_bloc) / min(c_bloc)))


# --- 2. Bornes calibrees, une fois, sur le bloc -------------------------------
couches_bloc <- dsr_layers_dtm(mnt_bloc, res = 1, echelles_vessel = ECH)
emp_bloc <- sf::st_as_sfc(sf::st_bbox(e_bloc)); sf::st_crs(emp_bloc) <- sf::st_crs(roads_full)
roads_bloc <- suppressWarnings(sf::st_cast(
  sf::st_intersection(roads_full, emp_bloc), "LINESTRING"))
cal <- dsr_calibrer_specs(couches_bloc, roads_bloc[!sf::st_is_empty(roads_bloc)])
cat("\n== Regles calibrees (bornes absolues) ==\n")
print(cal$diagnostic[cal$diagnostic$retenu, c("canal", "auc", "sens", "poids", "a", "b")],
  row.names = FALSE, digits = 3)


# --- 3. Les quatre combinaisons -----------------------------------------------
# Pour chaque reglage : sigma_geo calcule sur la FENETRE seule, et sur le BLOC
# puis recadre. Si le reglage ancre bien, les deux coincident.
sigma_de <- function(mnt, specs, c_vessel) {
  dsr_conductivite(dsr_layers_dtm(mnt, res = 1, echelles_vessel = ECH,
    c_vessel = c_vessel), specs = specs)
}

comparer <- function(nom, specs, c_vessel) {
  s_fen <- sigma_de(mnt_fen, specs, c_vessel)
  s_bloc <- sigma_de(mnt_bloc, specs, c_vessel)
  a <- terra::values(terra::crop(s_fen, e_cmp), mat = FALSE)
  b <- terra::values(terra::crop(s_bloc, e_cmp), mat = FALSE)
  ok <- is.finite(a) & is.finite(b)
  data.frame(reglage = nom,
    ecart_max = max(abs(a[ok] - b[ok])),
    ecart_median = stats::median(abs(a[ok] - b[ok])),
    part_sup_0.4_fenetre = 100 * mean(a[ok] >= 0.4),
    part_sup_0.4_bloc = 100 * mean(b[ok] >= 0.4))
}

specs_defaut <- dsr_specs_geomorpho()
lignes <- list(
  comparer("aucun ancrage (etat audite)", specs_defaut, NULL),
  comparer("bornes seules", cal$specs, NULL),
  comparer("c seul", specs_defaut, c_bloc),
  comparer("bornes + c", cal$specs, c_bloc))
tab <- do.call(rbind, lignes)
cat("\n== sigma_geo : fenetre seule contre bloc recadre ==\n")
print(tab, row.names = FALSE, digits = 4)


# --- 4. Ce que ca change sur la detection elle-meme ---------------------------
# La metrique du brief : le lineaire detecte, qui passait de 116 m a 0 m.
detecter_sur <- function(mnt, specs, c_vessel, emprise) {
  s <- sigma_de(mnt, specs, c_vessel)
  d <- dsr_detecter(s, reference = NULL, methode = "squelette", seuil = 0.4,
    long_min = 30, regime = "corridor", emprise = emprise)
  if (nrow(d) == 0L) 0 else sum(as.numeric(sf::st_length(d)))
}
emp_cmp <- sf::st_as_sfc(sf::st_bbox(e_cmp)); sf::st_crs(emp_cmp) <- sf::st_crs(roads_full)

cat("\n== Lineaire detecte dans la MEME fenetre (m) ==\n")
det <- list()
for (r in list(list("aucun ancrage (etat audite)", specs_defaut, NULL),
               list("bornes + c", cal$specs, c_bloc))) {
  det[[length(det) + 1L]] <- data.frame(reglage = r[[1]],
    depuis_fenetre = detecter_sur(mnt_fen, r[[2]], r[[3]], emp_cmp),
    depuis_bloc = detecter_sur(mnt_bloc, r[[2]], r[[3]], emp_cmp))
}
d <- do.call(rbind, det)
d$ecart_relatif <- ifelse(pmax(d$depuis_fenetre, d$depuis_bloc) > 0,
  abs(d$depuis_fenetre - d$depuis_bloc) / pmax(d$depuis_fenetre, d$depuis_bloc),
  0)
print(d, row.names = FALSE, digits = 4)
cat("\n")
