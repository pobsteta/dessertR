# Jeu de validation --- bloc wsfi (4 dalles Lidar HD, projet nemeton)
# ------------------------------------------------------------------------------
# Chaine complete de dessertR sur un bloc reel de 4 dalles (2x2 km) DISPOSANT du
# MNT/MNH 50 cm, du reseau BD TOPO (roads.gpkg) et d'une desserte de reference
# (desserte_corrigee.gpkg, produite par foretaccess). On mesure la geometrie le
# long du reseau, on repositionne par pathfinder, et on COMPARE a la reference
# (BRIEF section 4).
#
# Les donnees ne sont pas redistribuees : le script pointe le cache local du
# projet. Adapter DSR_WSFI au besoin.

suppressMessages({library(terra); library(sf); library(dessertR)})

P <- Sys.getenv("DSR_WSFI",
  "/home/pascal/.local/share/nemeton/projects/20260717_101641_wsfi/cache")
OUT <- Sys.getenv("DSR_WSFI_OUT", file.path(tempdir(), "validation_wsfi"))
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)

# --- 1. Catalogage et controle d'homogeneite ---------------------------------
cat_dalles <- dsr_catalog(
  laz = file.path(P, "layers/lidar_nuage"),
  mnt = file.path(P, "layers/lidar_mnt"),
  mnh = file.path(P, "layers/lidar_mnh")
)
dessertR:::dsr_verifier_homogeneite(cat_dalles)
message(sprintf("Catalogue : %d dalles, LAS %s, annee(s) %s.",
  nrow(cat_dalles), paste(unique(cat_dalles$version_las), collapse = "/"),
  paste(unique(cat_dalles$annee), collapse = "/")))

# --- 2. Donnees de reference (dans l'emprise du bloc) ------------------------
mnt50 <- terra::rast(file.path(P, "layers/lidar_mnt_mosaic.tif"))
emp <- sf::st_as_sfc(sf::st_bbox(mnt50))
lire_clip <- function(f, couche = NULL) {
  args <- list(file.path(P, f), quiet = TRUE)
  if (!is.null(couche)) args$layer <- couche
  x <- sf::st_zm(do.call(sf::st_read, args))
  x[sf::st_intersects(x, emp, sparse = FALSE)[, 1], ]
}
roads <- lire_clip("layers/roads.gpkg")
ref   <- lire_clip("accessibility/desserte_corrigee.gpkg", "desserte_corrigee")
eau   <- lire_clip("layers/water_network.gpkg")
message(sprintf("Reference : %d routes BD TOPO (%.1f km), %d troncons desserte de reference.",
  nrow(roads), sum(as.numeric(sf::st_length(roads))) / 1000, nrow(ref)))

# --- 3. Canal geomorphologique + sigma_geo sur le bloc (grille 1 m) -----------
grille <- dsr_grille_reference(mnt50, res = 1)
message("Construction du canal geomorphologique (peut prendre 1-2 min)...")
pile <- dsr_layers_dtm(mnt50, grille = grille)
sigma_geo <- dsr_conductivite(pile)

# --- 4. Mesure le long de chaque route : brute vs repositionnee ---------------
# Repositionnement : pathfinder sur sigma_geo dans un corridor autour de la route.
repositionner <- function(route, buffer = 25) {
  bb <- sf::st_bbox(sf::st_buffer(sf::st_geometry(route), buffer))
  sg <- terra::crop(sigma_geo, terra::ext(bb["xmin"], bb["xmax"], bb["ymin"], bb["ymax"]))
  th <- terra::crop(pile[["theta"]], sg); ve <- terra::crop(pile[["vesselness"]], sg)
  co <- sf::st_coordinates(sf::st_geometry(route))[, 1:2]
  tryCatch(
    dsr_pathfinder(sg, co[1, ], co[nrow(co), ], theta = th, poids = ve, lambda = 6)$trace,
    error = function(e) NULL
  )
}

mesurer <- function(geom) {
  m <- tryCatch(dsr_measure(geom, mnt50, pas = 2, demi_largeur = 8,
    pas_travers = 0.25, liss_travers = 3, seuil_devers = 0.20, reference = geom),
    error = function(e) NULL)
  if (is.null(m)) return(NULL)
  m$stations
}

stations_brut <- list(); stations_repo <- list()
for (i in seq_len(nrow(roads))) {
  if (as.numeric(sf::st_length(roads[i, ])) < 30) next
  sb <- mesurer(roads[i, ])
  if (!is.null(sb)) { sb$route <- i; sb$origine <- "brut"; stations_brut[[length(stations_brut) + 1]] <- sb }
  rp <- repositionner(roads[i, ])
  if (!is.null(rp)) {
    sr <- mesurer(rp)
    if (!is.null(sr)) { sr$route <- i; sr$origine <- "repositionne"; stations_repo[[length(stations_repo) + 1]] <- sr }
  }
}
sta_brut <- do.call(rbind, stations_brut)
sta_repo <- do.call(rbind, stations_repo)

# --- 5. Comparaison de la largeur a la reference -----------------------------
compare <- function(sta) {
  near <- sf::st_nearest_feature(sta, ref)
  d <- data.frame(dsr = sta$LARGEUR_ROULABLE, ref = ref$largeur_carrossable_m[near])
  d <- d[is.finite(d$dsr) & is.finite(d$ref) & d$ref > 0, ]
  list(n = nrow(d), mae = mean(abs(d$dsr - d$ref)), biais = mean(d$dsr - d$ref),
    med_dsr = stats::median(d$dsr), med_ref = stats::median(d$ref))
}
cmp_brut <- compare(sta_brut)
cmp_repo <- compare(sta_repo)

# --- 6. Export GPKG + rapport ------------------------------------------------
gpkg <- file.path(OUT, "validation_wsfi.gpkg")
dsr_export_gpkg(list(
  routes_bdtopo = roads,
  desserte_reference = ref[, c("classe", "largeur_carrossable_m", "pente_pct", "etat_classe")],
  stations_brut = sta_brut, stations_repositionne = sta_repo
), gpkg, styles = FALSE)

rap <- c(
  "# Validation dessertR --- bloc wsfi (4 dalles, MNT 50 cm)", "",
  sprintf("- Dalles : %d, LAS %s, %s.", nrow(cat_dalles),
    paste(unique(cat_dalles$version_las), collapse = "/"), paste(unique(cat_dalles$annee), collapse = "/")),
  sprintf("- Reseau BD TOPO : %d routes, %.1f km.", nrow(roads), sum(as.numeric(sf::st_length(roads))) / 1000),
  "", "## Largeur roulable vs desserte de reference (largeur carrossable)",
  sprintf("- Sur axe BD TOPO brut : MAE %.2f m, biais %.2f m (dsr med %.1f / ref med %.1f, n=%d).",
    cmp_brut$mae, cmp_brut$biais, cmp_brut$med_dsr, cmp_brut$med_ref, cmp_brut$n),
  sprintf("- Apres repositionnement : MAE %.2f m, biais %.2f m (dsr med %.1f, n=%d).",
    cmp_repo$mae, cmp_repo$biais, cmp_repo$med_dsr, cmp_repo$n),
  "", "## Constats",
  "- La largeur roulable est sous-estimee par rapport a la largeur carrossable de",
  "  reference : la mesure retient la seule bande de tres faible devers, la",
  "  reference inclut les accotements ; seuils a caler avec le gestionnaire.",
  "- Le repositionnement sur sigma_geo SEUL ne reduit pas l'erreur (voire",
  "  l'augmente) : le pathfinder peut accrocher un lineaire parallele (fosse,",
  "  trace fossile) --- risque n.1 du BRIEF. Piste : contraindre le pathfinder",
  "  par la proximite a l'axe BD TOPO, ou ponderer par sigma_surf.",
  "", sprintf("GPKG : %s", gpkg)
)
writeLines(rap, file.path(OUT, "rapport_validation.md"))
cat(paste(rap, collapse = "\n"), "\n")
