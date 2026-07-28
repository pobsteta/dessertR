# Validation multi-massifs --- projets nemeton
# ------------------------------------------------------------------------------
# Chaine complete de dessertR sur les massifs disponibles dans nemeton (BRIEF
# section 4). Le BRIEF demande 2 a 3 massifs contrastes : ce script les traite
# tous et publie un tableau comparatif.
#
# CE QUI FAIT REFERENCE, ET POUR QUOI
#
#   BD TOPO (layers/roads.gpkg)
#     - POSITION : oui. C'est sa force, et le socle de dsr_repositionner().
#       L'ecart au recalage se mesure contre elle.
#     - EXISTENCE d'un troncon : oui. Base valable pour la precision/rappel de
#       la detection hors reference.
#     - LARGEUR : non, pas au sens metrologique. LARGEUR_DE_CHAUSSEE est un
#       attribut DECLARATIF, souvent defaute par classe et frequemment vide sur
#       Chemin et Sentier -- justement notre cas d'usage. Elle sert ici de
#       controle ORDINAL (l'ordre des classes doit etre respecte), pas de metre
#       etalon.
#
#   desserte_corrigee.gpkg (foretaccess)
#     - N'EST PAS UNE REFERENCE. C'est la sortie d'un autre algorithme, qui
#       s'appuie aujourd'hui sur ALSroads, lequel sous-estime la BD TOPO.
#       Calibrer dessus serait circulaire : comme dsr_calibrer_largeur() retient
#       le reglage qui MINIMISE l'ecart, on selectionnerait les parametres qui
#       reproduisent le biais d'ALSroads au lieu de le reveler. La couche est
#       exportee dans le GPKG pour comparaison visuelle, jamais utilisee pour
#       caler quoi que ce soit.
#
#   Vraie verite terrain (releves, GNSS, photo-interpretation sur ortho)
#     - La seule qui permette de CALIBRER la largeur. Pointer DSR_TERRAIN vers
#       un fichier la portant declenche le calibrage ; sinon le script se limite
#       aux diagnostics de coherence, qui n'exigent aucune verite.
#
# Les donnees ne sont pas redistribuees : le script pointe le cache local des
# projets. Il DECOUVRE les projets presents plutot que d'en coder les noms en
# dur -- ajouter un massif dans nemeton suffit a l'inclure.
#
#   DSR_NEMETON     racine des projets (defaut : emplacement standard par OS)
#   DSR_PROJETS     sous-ensemble, noms separes par des virgules (defaut : tous)
#   DSR_OUT         repertoire de sortie
#   DSR_INVENTAIRE  a 1 : afficher l'inventaire et s'arreter, sans rien traiter
#   DSR_TERRAIN     chemin d'une couche de verite terrain (largeur mesuree)
#   DSR_TERRAIN_CHAMP  nom du champ de largeur dans cette couche
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
      # presente pour comparaison visuelle seulement -- voir l'en-tete
      foretaccess = file.exists(file.path(ca, "accessibility", "desserte_corrigee.gpkg")),
      stringsAsFactors = FALSE
    )
  }))
}

inv <- inventorier(RACINE)
message(sprintf("Racine : %s", RACINE))
message(sprintf("%-28s %8s %5s %6s %13s", "projet", "dalles", "MNT", "roads",
  "foretaccess"))
for (i in seq_len(nrow(inv))) {
  message(sprintf("%-28s %8d %5s %6s %13s", inv$projet[i], inv$n_dalles[i],
    ifelse(inv$mnt[i], "oui", "-"), ifelse(inv$roads[i], "oui", "-"),
    ifelse(inv$foretaccess[i], "oui", "-")))
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
message(paste("\nRappel : la colonne foretaccess n'est PAS une reference",
  "(sortie d'ALSroads, qui sous-estime la BD TOPO).\n",
  "Le calibrage de la largeur exige une verite terrain -- voir DSR_TERRAIN."))

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


# --- Verite terrain optionnelle -----------------------------------------------
# SEULE entree qui autorise un calibrage de la largeur. En son absence le script
# ne calibre rien : il ne dispose d'aucune mesure independante a laquelle se
# comparer, et se caler sur la sortie d'un autre algorithme serait circulaire.
TERRAIN <- NULL
TERRAIN_CHAMP <- Sys.getenv("DSR_TERRAIN_CHAMP", "largeur_m")
chemin_terrain <- Sys.getenv("DSR_TERRAIN", "")
if (nzchar(chemin_terrain)) {
  if (!file.exists(chemin_terrain)) {
    stop(sprintf("DSR_TERRAIN introuvable : %s", chemin_terrain))
  }
  TERRAIN <- sf::st_zm(sf::st_read(chemin_terrain, quiet = TRUE))
  if (!TERRAIN_CHAMP %in% names(TERRAIN)) {
    stop(sprintf(paste0("Le champ '%s' est absent de %s.\n",
      "  Champs disponibles : %s\n",
      "  Definir DSR_TERRAIN_CHAMP."), TERRAIN_CHAMP, chemin_terrain,
      paste(setdiff(names(TERRAIN), attr(TERRAIN, "sf_column")), collapse = ", ")))
  }
  message(sprintf("Verite terrain : %d troncons, champ '%s'.",
    nrow(TERRAIN), TERRAIN_CHAMP))
} else {
  message(paste("Pas de verite terrain (DSR_TERRAIN non defini) :",
    "aucun calibrage,\n  seulement les diagnostics de coherence."))
}


# --- Traitement d'un massif ---------------------------------------------------
traiter <- function(nom, P, avec_foretaccess) {
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
  # Exportee pour comparaison visuelle uniquement : ce n'est pas une reference.
  fa <- if (avec_foretaccess) {
    tryCatch(lire_clip("accessibility/desserte_corrigee.gpkg", "desserte_corrigee"),
      error = function(e) NULL)
  } else NULL
  message(sprintf("  %d dalles | %d routes BD TOPO (%.1f km)",
    nrow(cat_dalles), nrow(roads),
    sum(as.numeric(sf::st_length(roads))) / 1000))

  message("  canal geomorphologique + sigma_geo...")
  grille <- dsr_grille_reference(mnt50, res = 1)
  pile <- dsr_layers_dtm(mnt50, grille = grille)
  sigma_geo <- dsr_conductivite(pile)

  message("  repositionnement contraint (+/- 10 m)...")
  recale <- dsr_repositionner(roads, sigma_geo, theta = pile[["theta"]],
    poids = pile[["vesselness"]], deviation_max = 10, attraction = 1)

  # --- Calibrage : seulement si une VRAIE verite terrain est fournie ----------
  cal <- NULL
  best <- list(methode_largeur = "chaussee", tol_planeite = 0.10)
  if (!is.null(TERRAIN)) {
    dans <- TERRAIN[sf::st_intersects(TERRAIN, emp, sparse = FALSE)[, 1], ]
    if (nrow(dans) > 0L) {
      message(sprintf("  calibrage sur verite terrain (%d troncons)...", nrow(dans)))
      cal <- dsr_calibrer_largeur(recale, mnt50, dans, TERRAIN_CHAMP,
        grille = expand.grid(
          methode_largeur = c("chaussee", "planeite", "gradient"),
          tol_planeite = c(0.05, 0.10, 0.20), stringsAsFactors = FALSE),
        long_min = 30, pas = 2, demi_largeur = 8, pas_travers = 0.25,
        liss_travers = 3)
      cal$massif <- nom
      best <- cal[1, ]
      message(sprintf("  meilleur reglage : %s, tol %.2f (MAE %.2f m, biais %+.2f m)",
        best$methode_largeur, best$tol_planeite, best$mae, best$biais))
    } else {
      message("  verite terrain sans recouvrement avec ce massif.")
    }
  } else {
    message("  pas de verite terrain : mesure aux defauts, diagnostics de coherence.")
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

  # --- Diagnostics sans verite terrain ---------------------------------------
  # Ils ne disent pas que la mesure est JUSTE, ils disent si elle est
  # REPRODUCTIBLE et PLAUSIBLE. C'est tout ce qu'on peut affirmer sans releve.
  #
  # 1. Dispersion intra-troncon : une meme route mesuree en cent stations doit
  #    rendre a peu pres la meme largeur. Un ecart interquartile large signale
  #    du bruit de mesure, sans qu'aucune reference soit necessaire.
  # 2. Ordre des classes BD TOPO : c'est le seul usage metrologiquement tenable
  #    de la BD TOPO ici. L'attribut de largeur est declaratif, mais l'ORDRE
  #    des natures (Route empierree > Chemin > Sentier) est, lui, verifiable.
  #    Si la mesure ne le reproduit pas, elle est fausse ; si elle le reproduit,
  #    elle est coherente -- pas calibree.
  iqr_intra <- NA_real_
  if (!is.null(stations) && nrow(stations) > 0L) {
    par_tr <- stats::aggregate(LARGEUR_ROULABLE ~ troncon, data = stations,
      FUN = function(x) stats::IQR(x, na.rm = TRUE))
    iqr_intra <- stats::median(par_tr$LARGEUR_ROULABLE, na.rm = TRUE)
  }

  # 3. Part des stations ou la rupture chaussee/accotement a ete RESOLUE. C'est
  #    la premiere chose a lire : quand elle vaut 0, la largeur rendue est une
  #    largeur de PLATEFORME, pas de chaussee. Sur l'extrait de 200 m livre avec
  #    le paquet (MNT 50 cm, montagne, sous couvert), 162 stations sur 222 sont
  #    dans ce cas. Reste a savoir si ce taux tient sur des massifs entiers :
  #    s'il se confirme, c'est l'argument pour un micro-MNT sur points sol bruts.
  # 4. Repartition des fosses. Une valeur ecrasante sur une seule modalite est
  #    suspecte : c'est ainsi qu'on a vu que le critere precedent declarait un
  #    fosse a 211 stations sur 222, qui n'etaient que le versant aval.
  pct_nets <- NA_real_
  if (!is.null(stations) && "BORDS_CHAUSSEE" %in% names(stations)) {
    pct_nets <- 100 * mean(stations$BORDS_CHAUSSEE > 0, na.rm = TRUE)
  }
  rep_fosses <- if (!is.null(stations) && "FOSSES" %in% names(stations)) {
    t <- table(factor(stations$FOSSES, levels = 0:2))
    paste(sprintf("%d:%.0f%%", 0:2, 100 * as.numeric(t) / sum(t)), collapse = " ")
  } else NA_character_

  ordre <- NULL
  champ_nature <- intersect(c("NATURE", "nature"), names(roads))
  if (length(champ_nature) > 0L && !is.null(stations) && nrow(stations) > 0L) {
    nat <- roads[[champ_nature[1]]][stations$troncon]
    ordre <- stats::aggregate(list(largeur = stations$LARGEUR_ROULABLE),
      by = list(nature = nat), FUN = stats::median, na.rm = TRUE)
    ordre <- ordre[order(-ordre$largeur), , drop = FALSE]
    ordre$massif <- nom
  }

  gpkg <- file.path(OUT, sprintf("validation_%s.gpkg", nom))
  couches <- list(routes_bdtopo = roads, routes_recalees = recale,
    stations = stations)
  # nommee sans ambiguite : ce n'est pas une reference, c'est un comparatif
  if (!is.null(fa)) couches$foretaccess_alsroads <- fa
  dsr_export_gpkg(couches, gpkg, styles = FALSE)

  list(
    massif = nom, calibrage = cal, ordre = ordre, gpkg = gpkg,
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
      iqr_intra = iqr_intra,
      pct_nets = pct_nets,
      fosses = rep_fosses,
      rayon_p05 = stats::quantile(
        stations$RAYON_COURBURE[is.finite(stations$RAYON_COURBURE)], 0.05,
        names = FALSE)
    )
  )
}

res <- lapply(seq_len(nrow(inv)), function(i) {
  tryCatch(traiter(inv$projet[i], inv$cache[i], inv$foretaccess[i]),
    error = function(e) {
      message(sprintf("  ECHEC sur %s : %s", inv$projet[i], conditionMessage(e)))
      NULL
    })
})
res <- Filter(Negate(is.null), res)
if (length(res) == 0L) stop("Aucun massif n'a pu etre traite.")

resume <- do.call(rbind, lapply(res, `[[`, "resume"))
calibrage <- do.call(rbind, Filter(Negate(is.null), lapply(res, `[[`, "calibrage")))
ordres <- do.call(rbind, Filter(Negate(is.null), lapply(res, `[[`, "ordre")))
bloc_ordre <- if (is.null(ordres)) {
  "Champ NATURE absent de roads.gpkg : controle ordinal impossible."
} else {
  utils::capture.output(print(ordres, row.names = FALSE))
}
if (!is.null(calibrage)) {
  utils::write.csv(calibrage, file.path(OUT, "calibrage_largeur.csv"),
    row.names = FALSE)
}


# --- Rapport ------------------------------------------------------------------
# Le tableau croise est la piece maitresse : un reglage qui gagne sur un massif
# et perd sur les autres n'est pas un reglage, c'est un surajustement.
bloc_croise <- if (is.null(calibrage)) {
  paste("Pas de verite terrain fournie (DSR_TERRAIN) : aucun calibrage.",
    "La largeur n'est ni validee ni invalidee -- seulement mesuree avec une",
    "erreur d'estimateur bornee sur profils de synthese.", sep = "\n")
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
  "| massif | dalles | km BD TOPO | deplacement med. | methode | IQR intra | bords nets | fosses 0/1/2 | rayon P05 (m) |",
  "|---|---|---|---|---|---|---|---|---|",
  apply(resume, 1, function(r) sprintf(
    "| %s | %s | %.1f | %.1f | %s | %.2f | %s | %s | %.0f |",
    r[["massif"]], r[["dalles"]], as.numeric(r[["km_bdtopo"]]),
    as.numeric(r[["deplacement_med"]]), r[["methode"]],
    as.numeric(r[["iqr_intra"]]),
    if (is.na(r[["pct_nets"]])) "-" else sprintf("%.0f%%", as.numeric(r[["pct_nets"]])),
    r[["fosses"]], as.numeric(r[["rayon_p05"]]))),
  "", "## Calibrage croise (MAE en m, plus bas = mieux)", "",
  "Un reglage n'est retenu que s'il tient sur TOUS les massifs.", "",
  bloc_croise,
  "", "## Coherence sans verite terrain", "",
  "Ces indicateurs ne disent pas que la mesure est JUSTE. Ils disent si elle est",
  "reproductible et plausible -- tout ce qu'on peut affirmer sans releve.", "",
  "- `iqr_intra` : ecart interquartile median de la largeur AU SEIN d'un meme",
  "  troncon. Une route mesuree en cent stations doit rendre a peu pres la meme",
  "  largeur ; un IQR large est du bruit de mesure, sans reference necessaire.",
  "- Ordre des classes BD TOPO : seul usage metrologiquement tenable de la",
  "  BD TOPO ici. Son attribut de largeur est declaratif, mais l'ORDRE des",
  "  natures est verifiable. S'il n'est pas reproduit, la mesure est fausse ;",
  "  s'il l'est, elle est coherente -- pas calibree.",
  "- `bords nets` : part des stations ou la rupture chaussee/accotement a ete",
  "  RESOLUE. A LIRE EN PREMIER. Quand elle est basse, la colonne",
  "  LARGEUR_ROULABLE rend surtout des largeurs de PLATEFORME, accotement",
  "  compris, et non des largeurs de chaussee. Filtrer sur BORDS_CHAUSSEE > 0",
  "  avant toute conclusion sur la largeur.",
  "- `fosses 0/1/2` : une modalite ecrasante est suspecte. C'est ainsi qu'on a",
  "  vu que l'ancien critere declarait un fosse a 211 stations sur 222, qui",
  "  n'etaient que le versant aval d'une route en devers.", "",
  bloc_ordre, "",
  "## Ce qui ferait vraiment reference", "",
  "- POSITION : la BD TOPO, sans reserve. C'est le socle du recalage.",
  "- EXISTENCE d'un troncon : la BD TOPO egalement.",
  "- LARGEUR : ni la BD TOPO (attribut declaratif, souvent vide sur Chemin et",
  "  Sentier), ni desserte_corrigee.gpkg (sortie d'ALSroads, qui sous-estime la",
  "  BD TOPO -- s'y caler reproduirait son biais au lieu de le reveler). Il faut",
  "  un releve : decametre, GNSS, ou photo-interpretation sur ortho THR.",
  "  Pointer DSR_TERRAIN dessus declenche le calibrage.",
  "- tol_planeite doit depasser la fleche du bombement (bombement x largeur / 2).",
  "",
  if (is.null(calibrage)) "" else
    sprintf("Detail complet : %s", file.path(OUT, "calibrage_largeur.csv")),
  paste(sprintf("GPKG : %s", vapply(res, `[[`, character(1), "gpkg")), collapse = "\n")
)
writeLines(rap, file.path(OUT, "rapport_validation.md"))
cat(paste(rap, collapse = "\n"), "\n")
