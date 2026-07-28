# Validation multi-massifs --- projets nemeton
# ------------------------------------------------------------------------------
# Chaine complete de dessertR sur les massifs disponibles dans nemeton, et
# COMPARAISON a la desserte de reference (BRIEF section 4). Le BRIEF demande
# 2 a 3 massifs contrastes : ce script les traite tous et publie un tableau
# comparatif, seul moyen de savoir si un reglage cale sur un massif tient sur
# les autres.
#
# Les donnees ne sont pas redistribuees : le script pointe le cache local des
# projets. Il DECOUVRE les projets presents plutot que d'en coder les noms en
# dur -- ajouter un massif dans nemeton suffit a l'inclure.
#
#   DSR_NEMETON   racine des projets (defaut : ~/.local/share/nemeton/projects)
#   DSR_PROJETS   sous-ensemble, noms separes par des virgules (defaut : tous)
#   DSR_OUT       repertoire de sortie
#
# Usage :  Rscript dev/03_validation.R

suppressMessages({library(terra); library(sf); library(dessertR)})

RACINE <- Sys.getenv("DSR_NEMETON",
  file.path(path.expand("~"), ".local/share/nemeton/projects"))
OUT <- Sys.getenv("DSR_OUT", file.path(tempdir(), "validation_dessertR"))
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)

# --- Decouverte des projets ---------------------------------------------------
# Un projet est retenu s'il porte les trois entrees indispensables : le MNT
# mosaique, le reseau BD TOPO et une desserte de reference a laquelle comparer.
projets_valides <- function(racine) {
  if (!dir.exists(racine)) {
    stop(sprintf("Racine nemeton introuvable : %s (definir DSR_NEMETON)", racine))
  }
  cand <- list.dirs(racine, recursive = FALSE)
  garde <- vapply(cand, function(p) {
    ca <- file.path(p, "cache")
    all(file.exists(
      file.path(ca, "layers/lidar_mnt_mosaic.tif"),
      file.path(ca, "layers/roads.gpkg"),
      file.path(ca, "accessibility/desserte_corrigee.gpkg")
    ))
  }, logical(1))
  stats::setNames(file.path(cand[garde], "cache"), basename(cand[garde]))
}

PROJETS <- projets_valides(RACINE)
choix <- Sys.getenv("DSR_PROJETS", "")
if (nzchar(choix)) {
  vus <- trimws(strsplit(choix, ",")[[1]])
  manquants <- setdiff(vus, names(PROJETS))
  if (length(manquants)) {
    stop(sprintf("Projets absents ou incomplets : %s", paste(manquants, collapse = ", ")))
  }
  PROJETS <- PROJETS[vus]
}
if (length(PROJETS) == 0L) {
  stop(sprintf("Aucun projet exploitable sous %s.", RACINE))
}
message(sprintf("Massifs retenus (%d) : %s", length(PROJETS),
  paste(names(PROJETS), collapse = ", ")))


# --- Traitement d'un massif ---------------------------------------------------
traiter <- function(nom, P) {
  message(sprintf("\n=== %s ===", nom))

  cat_dalles <- dsr_catalog(
    laz = file.path(P, "layers/lidar_nuage"),
    mnt = file.path(P, "layers/lidar_mnt"),
    mnh = file.path(P, "layers/lidar_mnh")
  )
  mnt50 <- terra::rast(file.path(P, "layers/lidar_mnt_mosaic.tif"))
  emp <- sf::st_as_sfc(sf::st_bbox(mnt50))
  lire_clip <- function(f, couche = NULL) {
    args <- list(file.path(P, f), quiet = TRUE)
    if (!is.null(couche)) args$layer <- couche
    x <- sf::st_zm(do.call(sf::st_read, args))
    x[sf::st_intersects(x, emp, sparse = FALSE)[, 1], ]
  }
  roads <- lire_clip("layers/roads.gpkg")
  ref <- lire_clip("accessibility/desserte_corrigee.gpkg", "desserte_corrigee")
  message(sprintf("  %d dalles | %d routes BD TOPO (%.1f km) | %d troncons de reference",
    nrow(cat_dalles), nrow(roads),
    sum(as.numeric(sf::st_length(roads))) / 1000, nrow(ref)))

  message("  canal geomorphologique + sigma_geo...")
  grille <- dsr_grille_reference(mnt50, res = 1)
  pile <- dsr_layers_dtm(mnt50, grille = grille)
  sigma_geo <- dsr_conductivite(pile)

  message("  repositionnement contraint (+/- 10 m)...")
  recale <- dsr_repositionner(roads, sigma_geo, theta = pile[["theta"]],
    poids = pile[["vesselness"]], deviation_max = 10, attraction = 1)

  # --- Calibrage de la largeur sur la reference du massif ---------------------
  # On balaie la methode et la tolerance de planeite. Le tableau renvoye dit,
  # massif par massif, quel reglage minimise l'ecart -- et surtout si le meme
  # reglage gagne partout.
  message("  calibrage de la largeur...")
  grille_cal <- expand.grid(
    methode_largeur = c("planeite", "gradient"),
    tol_planeite = c(0.05, 0.10, 0.20),
    stringsAsFactors = FALSE
  )
  cal <- dsr_calibrer_largeur(recale, mnt50, ref, "largeur_carrossable_m",
    grille = grille_cal, long_min = 30,
    pas = 2, demi_largeur = 8, pas_travers = 0.25, liss_travers = 3)
  cal$massif <- nom

  # --- Mesure au meilleur reglage --------------------------------------------
  best <- cal[1, ]
  message(sprintf("  meilleur reglage : %s, tol %.2f (MAE %.2f m, biais %+.2f m)",
    best$methode_largeur, best$tol_planeite, best$mae, best$biais))

  stations <- do.call(rbind, lapply(seq_len(nrow(recale)), function(i) {
    if (as.numeric(sf::st_length(recale[i, ])) < 30) return(NULL)
    m <- tryCatch(dsr_measure(recale[i, ], mnt50, pas = 2, demi_largeur = 8,
      pas_travers = 0.25, liss_travers = 3,
      methode_largeur = best$methode_largeur,
      tol_planeite = best$tol_planeite, base_courbure = 30),
      error = function(e) NULL)
    if (is.null(m)) return(NULL)
    m$stations$troncon <- i
    m$stations
  }))

  gpkg <- file.path(OUT, sprintf("validation_%s.gpkg", nom))
  dsr_export_gpkg(list(
    routes_bdtopo = roads, routes_recalees = recale,
    desserte_reference = ref, stations = stations
  ), gpkg, styles = FALSE)

  list(
    massif = nom, calibrage = cal, gpkg = gpkg,
    resume = data.frame(
      massif = nom,
      dalles = nrow(cat_dalles),
      km_bdtopo = sum(as.numeric(sf::st_length(roads))) / 1000,
      deplacement_med = stats::median(recale$DEPLACEMENT_MOY, na.rm = TRUE),
      methode = best$methode_largeur,
      tol = best$tol_planeite,
      n = best$n, biais = best$biais, mae = best$mae,
      rayon_p05 = stats::quantile(
        stations$RAYON_COURBURE[is.finite(stations$RAYON_COURBURE)], 0.05,
        names = FALSE)
    )
  )
}

res <- lapply(names(PROJETS), function(n) {
  tryCatch(traiter(n, PROJETS[[n]]), error = function(e) {
    message(sprintf("  ECHEC sur %s : %s", n, conditionMessage(e)))
    NULL
  })
})
res <- Filter(Negate(is.null), res)
if (length(res) == 0L) stop("Aucun massif n'a pu etre traite.")

resume <- do.call(rbind, lapply(res, `[[`, "resume"))
calibrage <- do.call(rbind, lapply(res, `[[`, "calibrage"))
utils::write.csv(calibrage, file.path(OUT, "calibrage_largeur.csv"), row.names = FALSE)


# --- Rapport ------------------------------------------------------------------
# Le tableau croise est la piece maitresse : un reglage qui gagne sur un massif
# et perd sur les autres n'est pas un reglage, c'est un surajustement.
croise <- stats::aggregate(
  mae ~ methode_largeur + tol_planeite + massif, data = calibrage, FUN = min)

rap <- c(
  "# Validation dessertR --- massifs nemeton", "",
  sprintf("Massifs : %s.", paste(resume$massif, collapse = ", ")), "",
  "## Synthese par massif", "",
  "| massif | dalles | km BD TOPO | deplacement med. | methode | tol | n | biais (m) | MAE (m) | rayon P05 (m) |",
  "|---|---|---|---|---|---|---|---|---|---|",
  apply(resume, 1, function(r) sprintf("| %s | %s | %.1f | %.1f | %s | %.2f | %s | %+.2f | %.2f | %.0f |",
    r[["massif"]], r[["dalles"]], as.numeric(r[["km_bdtopo"]]),
    as.numeric(r[["deplacement_med"]]), r[["methode"]], as.numeric(r[["tol"]]),
    r[["n"]], as.numeric(r[["biais"]]), as.numeric(r[["mae"]]),
    as.numeric(r[["rayon_p05"]]))),
  "", "## Calibrage croise (MAE en m, plus bas = mieux)", "",
  "Un reglage n'est retenu que s'il tient sur TOUS les massifs.", "",
  utils::capture.output(print(stats::reshape(croise,
    idvar = c("methode_largeur", "tol_planeite"), timevar = "massif",
    direction = "wide"), row.names = FALSE)),
  "", "## Lecture", "",
  "- Un biais a peu pres CONSTANT avec une MAE faible n'est pas une erreur de",
  "  mesure : c'est un ecart de definition. La largeur roulable retient la bande",
  "  de faible devers ; une largeur carrossable de gestionnaire inclut souvent",
  "  les accotements. A trancher avec le gestionnaire, pas a corriger au seuil.",
  "- Une MAE forte a biais faible est du bruit de mesure : regarder la densite",
  "  de points sol (BRIEF, risque n.3) avant de toucher aux seuils.",
  "- tol_planeite doit depasser la fleche du bombement (bombement x largeur / 2).",
  "",
  sprintf("Detail complet : %s", file.path(OUT, "calibrage_largeur.csv")),
  paste(sprintf("GPKG : %s", vapply(res, `[[`, character(1), "gpkg")), collapse = "\n")
)
writeLines(rap, file.path(OUT, "rapport_validation.md"))
cat(paste(rap, collapse = "\n"), "\n")
