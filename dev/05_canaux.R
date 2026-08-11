# Quels canaux marquent reellement une route ? --- et OSM est-il une reference ?
# ------------------------------------------------------------------------------
# Ce script repond a la question qui commande toutes les autres : sur ce bloc,
# quelle grandeur distingue une route d'une foret ? Tant qu'aucune ne le fait,
# comparer des vectoriseurs (dev/04) ne mesure que la carte.
#
# Constat qui l'a motive, mesure sur wsfi : sigma_geo AUC 0,50 -- le hasard.
# sigma_surf 0,58. Le BRIEF (section 3.9) ponderait deja la surface a 2 contre 1
# sur ce raisonnement ; la mesure lui donne raison et permet d'aller plus loin :
# `dsr_indice_detection()` avec les poids par defaut sort a 0,57, DESSOUS
# sigma_surf seul. Melanger un canal de bruit degrade. Les poids devraient
# dependre du pouvoir discriminant mesure, pas d'une constante.
#
# MESURE : AUC de Mann-Whitney, cellules a moins de 3 m d'une route BD TOPO
# contre cellules a plus de 20 m. 0,5 = aucun pouvoir discriminant. On teste les
# deux sens (un canal peut marquer les routes par le BAS, comme l'openness
# negatif ou le NDVI) et on retient l'ecart au hasard.
#
# OSM N'EST PAS UN CANAL. C'est de la donnee vectorielle : elle n'entre pas dans
# une moyenne geometrique de conductivites. Sa place est ailleurs, et ce script
# la quantifie -- voir la derniere section.
#
# Usage :  Rscript dev/05_canaux.R
#   DSR_WSFI / DSR_OUT / DSR_COTE  comme dev/04
#   DSR_OSM=0                      pour sauter l'interrogation d'Overpass

suppressMessages({library(terra); library(sf)})
if (file.exists("DESCRIPTION") && requireNamespace("pkgload", quietly = TRUE)) {
  suppressMessages(pkgload::load_all(".", quiet = TRUE))
} else {
  library(dessertR)
}

cache <- Sys.getenv("DSR_WSFI",
  "/home/pascal/.local/share/nemeton/projects/20260717_101641_wsfi/cache")
out <- Sys.getenv("DSR_OUT", "dev/out/canaux")
cote <- as.numeric(Sys.getenv("DSR_COTE", "1000"))
dir.create(out, recursive = TRUE, showWarnings = FALSE)

mnt_full <- terra::rast(file.path(cache, "layers", "lidar_mnt_mosaic.tif"))
roads_full <- sf::st_zm(sf::st_geometry(
  sf::st_read(file.path(cache, "layers", "roads.gpkg"), quiet = TRUE)), drop = TRUE)

centre <- sf::st_coordinates(sf::st_centroid(sf::st_union(roads_full)))[1, 1:2]
fen <- terra::intersect(
  terra::ext(centre[1] - cote / 2, centre[1] + cote / 2,
             centre[2] - cote / 2, centre[2] + cote / 2), terra::ext(mnt_full))
mnt <- terra::crop(mnt_full, fen)
emprise <- sf::st_as_sfc(sf::st_bbox(fen))
sf::st_crs(emprise) <- sf::st_crs(roads_full)
roads <- suppressWarnings(sf::st_cast(sf::st_intersection(roads_full, emprise), "LINESTRING"))
roads <- roads[!sf::st_is_empty(roads)]
cat(sprintf("Fenetre %.0f m | BD TOPO : %d troncons, %.2f km\n", cote,
  length(roads), sum(as.numeric(sf::st_length(roads))) / 1000))


# --- AUC d'un canal -----------------------------------------------------------
# Symetrique : un canal qui marque les routes par le bas (creux, NDVI faible)
# est aussi informatif qu'un canal qui les marque par le haut. On rend l'AUC
# orientee « plus grand = plus route » et le sens retenu.
auc_canal <- function(r, roads, pres = 3, abs = 20, n = 2500) {
  u <- sf::st_union(roads)
  vin <- terra::values(terra::mask(r, terra::vect(sf::st_buffer(u, pres))))
  vout <- terra::values(terra::mask(r, terra::vect(sf::st_buffer(u, abs)), inverse = TRUE))
  vin <- vin[is.finite(vin)]; vout <- vout[is.finite(vout)]
  if (length(vin) < 100 || length(vout) < 100) return(c(auc = NA_real_, sens = NA_real_))
  a <- sample(vin, min(n, length(vin))); b <- sample(vout, min(n, length(vout)))
  auc <- mean(outer(a, b, ">")) + 0.5 * mean(outer(a, b, "=="))
  c(auc = max(auc, 1 - auc), sens = if (auc >= 0.5) 1 else -1)
}

canaux <- list()
ajouter <- function(nom, r, note = "") {
  if (is.null(r)) return(invisible(NULL))
  a <- auc_canal(r, roads)
  canaux[[length(canaux) + 1L]] <<- data.frame(canal = nom, auc = unname(a["auc"]),
    sens = ifelse(is.na(a["sens"]), NA, ifelse(a["sens"] > 0, "haut", "bas")),
    note = note)
}


# --- Canaux geomorphologiques (MNT) -------------------------------------------
cat("Canaux MNT...\n")
couches <- dsr_layers_dtm(mnt, res = 1)
for (nm in names(couches)) {
  if (nm == "theta") next # orientation, pas une intensite
  ajouter(nm, couches[[nm]])
}
sigma_geo <- dsr_conductivite(couches)
ajouter("sigma_geo", sigma_geo, "conductivite geomorphologique")


# --- Canal de surface (nuage) -------------------------------------------------
nuage <- list.files(file.path(cache, "layers", "lidar_nuage"),
  pattern = "\\.(copc\\.laz|laz|las)$", full.names = TRUE)
sigma_surf <- NULL
if (length(nuage)) {
  cat(sprintf("Canaux nuage (%d dalles)...\n", length(nuage)))
  grille <- dsr_grille_reference(mnt, res = 1)
  pc <- tryCatch(dsr_layers_pc(nuage, res = 1, grille = grille, emprise = emprise),
    error = function(e) {cat("  echec :", conditionMessage(e), "\n"); NULL})
  if (!is.null(pc)) {
    for (nm in c("densite_sol", "taux_penetration", "densite_sousetage", "h_couvert")) {
      if (nm %in% names(pc)) ajouter(nm, pc[[nm]])
    }
    sigma_surf <- dsr_sigma_surf(pc)
    ajouter("sigma_surf", sigma_surf, "conductivite de surface")
  }
}


# --- Canal optique : BD ORTHO IRC 20 cm --------------------------------------
# Le `ndvi.tif` du cache est un produit ~5 m en WGS84 : une chaussee de 4 m y
# occupe moins d'un pixel, et sa mesure (AUC 0,537) ne dit rien du canal optique
# du paquet. dsr_ndvi() suppose l'ortho a 20 cm -- la seule resolution a
# l'echelle d'une chaussee forestiere. On va donc la chercher a la source.
#
# L'acquisition passe par dsr_ortho_ign(), la fonction DU PAQUET. Ce script
# portait jusqu'ici sa propre copie de la requete WMS ; elle a ete retiree.
#
# Un banc qui reimplemente ce qu'il est cense exercer ne le valide pas, et il se
# desynchronise au premier changement amont. La copie locale avait d'ailleurs
# deja diverge : elle ne reparait pas le CRS absent -- piege documente du service,
# qui fait sortir des « CRS do not match » a chaque croisement ulterieur -- et
# elle ne nommait pas les bandes, obligeant a designer PIR et Rouge par leur
# indice.

if (!identical(Sys.getenv("DSR_ORTHO"), "0")) {
  cat("Canal optique : BD ORTHO IRC 20 cm (Geoplateforme)...\n")
  t0 <- Sys.time()
  irc <- tryCatch(dsr_ortho_ign(emprise), error = function(e) NULL)
  if (is.null(irc)) {
    cat("  indisponible.\n")
  } else {
    cat(sprintf("  %.0f s | %s px a %.2f m\n",
      as.numeric(difftime(Sys.time(), t0, units = "secs")),
      paste(dim(irc)[1:2], collapse = "x"), terra::res(irc)[1]))
    # NDVI sur les pixels NATIFS (20 cm), puis agrege a 1 m pour l'AUC : c'est
    # l'ordre impose par le paquet -- calculer le NDVI apres reechantillonnage
    # melangerait chaussee et vegetation dans le meme pixel avant l'indice.
    # Bandes designees par leur NOM : dsr_ortho_ign() les nomme, ce que la
    # copie locale ne faisait pas.
    ndvi20 <- dsr_ndvi(irc, bandes = c(pir = "pir", rouge = "rouge"))
    ajouter("ndvi_ortho20", ndvi20, "BD ORTHO IRC, pixels natifs 20 cm")
    ndvi1 <- terra::resample(ndvi20, sigma_geo, method = "average")
    ajouter("ndvi_ortho_1m", ndvi1, "meme NDVI, agrege a 1 m")
    terra::writeRaster(ndvi1, file.path(out, "ndvi_ortho.tif"), overwrite = TRUE)
  }
}

# Le NDVI grossier du cache, pour comparaison.
f_ndvi <- file.path(cache, "layers", "ndvi.tif")
if (file.exists(f_ndvi)) {
  nd <- tryCatch({
    r <- terra::rast(f_ndvi)
    terra::resample(terra::project(r, terra::crs(sigma_geo)), sigma_geo, method = "bilinear")
  }, error = function(e) NULL)
  ajouter("ndvi_s2", nd, "produit ~5 m du cache : hors echelle")
}


# --- Indices composes ---------------------------------------------------------
ajouter("indice_defaut", tryCatch(
  dsr_indice_detection(sigma_geo, sigma_surf = sigma_surf,
    vesselness = couches[["vesselness"]], reference = NULL),
  error = function(e) NULL), "poids BRIEF 1/2/1")

if (!is.null(sigma_surf)) {
  ajouter("indice_sans_geo", tryCatch(
    dsr_indice_detection(sigma_geo, sigma_surf = sigma_surf,
      vesselness = couches[["vesselness"]],
      poids = c(geo = 0, surf = 2, vessel = 1), reference = NULL),
    error = function(e) NULL), "geo mis a zero")
}

tab <- do.call(rbind, canaux)
tab <- tab[order(-tab$auc), ]
cat("\n== Pouvoir discriminant route / hors route ==\n")
cat("   AUC orientee (0.5 = hasard). `sens` : le canal marque la route par le\n")
cat("   haut ou par le bas.\n\n")
print(transform(tab, auc = round(auc, 3)), row.names = FALSE)
utils::write.csv(tab, file.path(out, "auc_canaux.csv"), row.names = FALSE)


# --- OSM : pas un canal, un complement de REFERENCE ---------------------------
# La question posee par dsr_detecter() est « quelle desserte la BD TOPO
# ignore-t-elle ? ». Elle est invalidable : par construction, il n'existe pas de
# verite pour ce que la reference ne porte pas. OSM est le seul jeu ouvert qui
# puisse en fournir une partie -- ses `highway=track` couvrent souvent les
# pistes forestieres que la BD TOPO neglige.
#
# Ce qu'OSM peut faire ici : mesurer le RAPPEL de la detection sur des routes
# absentes de la BD TOPO. Ce qu'il ne peut pas faire : servir de metre etalon
# pour une largeur (aucun attribut fiable), ni de verite de POSITION (precision
# heterogene, souvent tracee sur fond satellite). Meme regle que
# desserte_corrigee.gpkg : complement de comparaison, jamais de calibrage.
if (!identical(Sys.getenv("DSR_OSM"), "0")) {
  cat("\n== OSM comme reference complementaire ==\n")
  bb <- sf::st_bbox(sf::st_transform(emprise, 4326))
  req <- sprintf(paste0("[out:xml][timeout:90];(way[\"highway\"~\"track|path|",
    "unclassified|service|residential\"](%.6f,%.6f,%.6f,%.6f););(._;>;);out body;"),
    bb["ymin"], bb["xmin"], bb["ymax"], bb["xmax"])
  f <- file.path(tempdir(), "osm.osm")
  # Overpass exige un POST : `download.file()` ne sait faire qu'un GET, d'ou le
  # « 400 Bad Request » du premier essai. curl avec --data-urlencode est la
  # forme documentee par l'API.
  tryCatch(system2("curl", c("-s", "--max-time", "150", "-X", "POST",
    "--data-urlencode", shQuote(paste0("data=", req)),
    "https://overpass-api.de/api/interpreter", "-o", shQuote(f))),
    error = function(e) NULL)
  osm <- tryCatch(sf::st_read(f, layer = "lines", quiet = TRUE), error = function(e) NULL)
  if (is.null(osm) || !nrow(osm)) {
    cat("  Overpass n'a rien rendu d'exploitable.\n")
  } else {
    osm <- sf::st_transform(sf::st_geometry(osm), sf::st_crs(roads))
    osm <- suppressWarnings(sf::st_cast(sf::st_intersection(osm, emprise), "LINESTRING"))
    osm <- osm[!sf::st_is_empty(osm)]
    km_osm <- sum(as.numeric(sf::st_length(osm))) / 1000
    # Part d'OSM eloignee de toute route BD TOPO : la desserte que la reference
    # ne porte pas, donc la cible de dsr_detecter().
    pts <- sf::st_cast(do.call(c, lapply(seq_along(osm), function(i) {
      lg <- as.numeric(sf::st_length(osm[i]))
      sf::st_line_sample(osm[i], sample = seq(0, 1, length.out = max(2L, ceiling(lg / 5))))
    })), "POINT")
    d <- as.numeric(sf::st_distance(pts, sf::st_union(roads)))
    cat(sprintf("  OSM dans la fenetre : %.2f km (%d lignes)\n", km_osm, length(osm)))
    cat(sprintf("  Part a plus de 20 m de toute route BD TOPO : %.0f %%\n", 100 * mean(d > 20)))
    cat(sprintf("  Soit ~%.2f km de desserte hors reference, exploitable comme\n", km_osm * mean(d > 20)))
    cat("  verite PARTIELLE pour le rappel de dsr_detecter().\n")
    sf::st_write(sf::st_sf(geometry = osm), file.path(out, "osm.gpkg"),
      delete_dsn = TRUE, quiet = TRUE)
  }
}
cat(sprintf("\nEcrit dans %s\n", normalizePath(out)))
