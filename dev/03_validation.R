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
#   DSR_NEMETON     racine des projets (defaut : emplacement standard par OS)
#   DSR_PROJETS     sous-ensemble, noms separes par des virgules (defaut : tous)
#   DSR_OUT         repertoire de sortie
#   DSR_INVENTAIRE  a 1 : afficher l'inventaire et s'arreter, sans rien traiter
#
# Usage :  Rscript dev/03_validation.R
#          DSR_INVENTAIRE=1 Rscript dev/03_validation.R   (voir ce qui est vu)

suppressMessages({library(terra); library(sf); library(dessertR)})

# --- Ou vit nemeton ? ---------------------------------------------------------
# L'emplacement suit la convention de chaque systeme. Sous Windows, le double
# « nemeton\nemeton » n'est pas une faute : c'est le schema
# <LOCALAPPDATA>/<editeur>/<application> des bibliotheques de chemins standard.
racine_nemeton <- function() {
  perso <- Sys.getenv("DSR_NEMETON")
  if (nzchar(perso)) return(perso)
  base <- switch(Sys.info()[["sysname"]],
    Windows = {
      la <- Sys.getenv("LOCALAPPDATA")
      if (!nzchar(la)) la <- file.path(Sys.getenv("USERPROFILE"), "AppData", "Local")
      file.path(la, "nemeton", "nemeton")
    },
    Darwin = file.path(path.expand("~"), "Library", "Application Support", "nemeton"),
    {
      xdg <- Sys.getenv("XDG_DATA_HOME")
      file.path(if (nzchar(xdg)) xdg else file.path(path.expand("~"), ".local", "share"),
        "nemeton")
    }
  )
  file.path(base, "projects")
}

RACINE <- racine_nemeton()
OUT <- Sys.getenv("DSR_OUT", file.path(tempdir(), "validation_dessertR"))
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)


# --- Inventaire ---------------------------------------------------------------
# On n'ecarte rien en silence : chaque projet est liste avec ce qu'il porte.
# Un projet sans desserte de reference reste traitable -- il ne sera simplement
# pas calibrable, et le rapport le dira.
inventorier <- function(racine) {
  if (!dir.exists(racine)) {
    stop(sprintf(paste0("Racine nemeton introuvable : %s\n",
      "  Definir DSR_NEMETON si les projets sont ailleurs."), racine))
  }
  cand <- list.dirs(racine, recursive = FALSE)
  if (length(cand) == 0L) stop(sprintf("Aucun projet sous %s.", racine))

  do.call(rbind, lapply(cand, function(p) {
    ca <- file.path(p, "cache")
    nuage <- list.files(file.path(ca, "layers", "lidar_nuage"),
      pattern = "[.](laz|las|copc[.]laz)$", ignore.case = TRUE)
    data.frame(
      projet = basename(p),
      cache = ca,
      n_dalles = length(nuage),
      mnt = file.exists(file.path(ca, "layers", "lidar_mnt_mosaic.tif")),
      roads = file.exists(file.path(ca, "layers", "roads.gpkg")),
      reference = file.exists(file.path(ca, "accessibility", "desserte_corrigee.gpkg")),
      stringsAsFactors = FALSE
    )
  }))
}

inv <- inventorier(RACINE)
message(sprintf("Racine : %s", RACINE))
message(sprintf("%-28s %8s %5s %6s %10s", "projet", "dalles", "MNT", "roads", "reference"))
for (i in seq_len(nrow(inv))) {
  message(sprintf("%-28s %8d %5s %6s %10s", inv$projet[i], inv$n_dalles[i],
    ifelse(inv$mnt[i], "oui", "-"), ifelse(inv$roads[i], "oui", "-"),
    ifelse(inv$reference[i], "oui", "-")))
}

# Le minimum pour faire tourner la chaine : un MNT mosaique et un reseau.
exploitable <- inv$mnt & inv$roads
if (any(!exploitable)) {
  message(sprintf("\nEcartes (MNT mosaique ou roads.gpkg absent) : %s",
    paste(inv$projet[!exploitable], collapse = ", ")))
}
inv <- inv[exploitable, , drop = FALSE]
if (nrow(inv) == 0L) {
  stop(sprintf("Aucun projet exploitable sous %s.", RACINE))
}
if (any(!inv$reference)) {
  message(sprintf("Traites mais NON calibrables (pas de desserte de reference) : %s",
    paste(inv$projet[!inv$reference], collapse = ", ")))
}

choix <- Sys.getenv("DSR_PROJETS", "")
if (nzchar(choix)) {
  vus <- trimws(strsplit(choix, ",")[[1]])
  manquants <- setdiff(vus, inv$projet)
  if (length(manquants)) {
    stop(sprintf("Projets absents ou inexploitables : %s", paste(manquants, collapse = ", ")))
  }
  inv <- inv[inv$projet %in% vus, , drop = FALSE]
}

message(sprintf("\nMassifs a traiter (%d) : %s", nrow(inv),
  paste(inv$projet, collapse = ", ")))
if (identical(Sys.getenv("DSR_INVENTAIRE"), "1")) {
  message("DSR_INVENTAIRE=1 : arret apres inventaire.")
  quit(save = "no")
}


# --- Traitement d'un massif ---------------------------------------------------
traiter <- function(nom, P, avec_reference) {
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
  ref <- if (avec_reference) {
    lire_clip("accessibility/desserte_corrigee.gpkg", "desserte_corrigee")
  } else NULL
  message(sprintf("  %d dalles | %d routes BD TOPO (%.1f km) | reference : %s",
    nrow(cat_dalles), nrow(roads),
    sum(as.numeric(sf::st_length(roads))) / 1000,
    if (is.null(ref)) "absente" else sprintf("%d troncons", nrow(ref))))

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
  # reglage gagne partout. Sans reference, on mesure quand meme, aux defauts.
  cal <- NULL
  best <- list(methode_largeur = "planeite", tol_planeite = 0.10)
  if (!is.null(ref)) {
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
    best <- cal[1, ]
    message(sprintf("  meilleur reglage : %s, tol %.2f (MAE %.2f m, biais %+.2f m)",
      best$methode_largeur, best$tol_planeite, best$mae, best$biais))
  } else {
    message("  pas de reference : mesure aux defauts, sans calibrage.")
  }

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
  couches <- list(routes_bdtopo = roads, routes_recalees = recale,
    stations = stations)
  if (!is.null(ref)) couches$desserte_reference <- ref
  dsr_export_gpkg(couches, gpkg, styles = FALSE)

  list(
    massif = nom, calibrage = cal, gpkg = gpkg,
    resume = data.frame(
      massif = nom,
      dalles = nrow(cat_dalles),
      km_bdtopo = sum(as.numeric(sf::st_length(roads))) / 1000,
      deplacement_med = stats::median(recale$DEPLACEMENT_MOY, na.rm = TRUE),
      methode = best$methode_largeur,
      tol = best$tol_planeite,
      n = if (is.null(cal)) NA_integer_ else best$n,
      biais = if (is.null(cal)) NA_real_ else best$biais,
      mae = if (is.null(cal)) NA_real_ else best$mae,
      rayon_p05 = stats::quantile(
        stations$RAYON_COURBURE[is.finite(stations$RAYON_COURBURE)], 0.05,
        names = FALSE)
    )
  )
}

res <- lapply(seq_len(nrow(inv)), function(i) {
  tryCatch(traiter(inv$projet[i], inv$cache[i], inv$reference[i]),
    error = function(e) {
      message(sprintf("  ECHEC sur %s : %s", inv$projet[i], conditionMessage(e)))
      NULL
    })
})
res <- Filter(Negate(is.null), res)
if (length(res) == 0L) stop("Aucun massif n'a pu etre traite.")

resume <- do.call(rbind, lapply(res, `[[`, "resume"))
calibrage <- do.call(rbind, Filter(Negate(is.null), lapply(res, `[[`, "calibrage")))
if (!is.null(calibrage)) {
  utils::write.csv(calibrage, file.path(OUT, "calibrage_largeur.csv"),
    row.names = FALSE)
}


# --- Rapport ------------------------------------------------------------------
# Le tableau croise est la piece maitresse : un reglage qui gagne sur un massif
# et perd sur les autres n'est pas un reglage, c'est un surajustement.
bloc_croise <- if (is.null(calibrage)) {
  "Aucun massif ne porte de desserte de reference : pas de calibrage possible."
} else {
  croise <- stats::aggregate(
    mae ~ methode_largeur + tol_planeite + massif, data = calibrage, FUN = min)
  utils::capture.output(print(stats::reshape(croise,
    idvar = c("methode_largeur", "tol_planeite"), timevar = "massif",
    direction = "wide"), row.names = FALSE))
}

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
  bloc_croise,
  "", "## Lecture", "",
  "- Un biais a peu pres CONSTANT avec une MAE faible n'est pas une erreur de",
  "  mesure : c'est un ecart de definition. La largeur roulable retient la bande",
  "  de faible devers ; une largeur carrossable de gestionnaire inclut souvent",
  "  les accotements. A trancher avec le gestionnaire, pas a corriger au seuil.",
  "- Une MAE forte a biais faible est du bruit de mesure : regarder la densite",
  "  de points sol (BRIEF, risque n.3) avant de toucher aux seuils.",
  "- tol_planeite doit depasser la fleche du bombement (bombement x largeur / 2).",
  "",
  if (is.null(calibrage)) "" else
    sprintf("Detail complet : %s", file.path(OUT, "calibrage_largeur.csv")),
  paste(sprintf("GPKG : %s", vapply(res, `[[`, character(1), "gpkg")), collapse = "\n")
)
writeLines(rap, file.path(OUT, "rapport_validation.md"))
cat(paste(rap, collapse = "\n"), "\n")
