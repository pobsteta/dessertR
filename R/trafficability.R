# Praticabilite : la sortie METIER (BRIEF section 3.7). Regles PARAMETRABLES, a
# caler avec un gestionnaire (ONF, cooperative, ETF), jamais figees en dur. Deux
# apports propres au nuage : le gabarit libre sous branches (critere reel pour un
# grumier, ~4,5 m, absent de toutes les bases existantes) et la detection des
# elargissements (places de depot / de retournement).

#' Seuils d'aptitude au grumier par defaut
#'
#' Jeu de seuils *indicatif* pour [dsr_trafficability()], a **caler avec le
#' gestionnaire** (BRIEF section 3.7) : ils ne sont jamais figes en dur.
#'
#' @return Une liste : `largeur_min` (m), `pente_max` (m/m), `rayon_min` (m),
#'   `gabarit_min` (m).
#' @seealso [dsr_trafficability()].
#' @export
dsr_seuils_grumier <- function() {
  list(largeur_min = 3, pente_max = 0.10, rayon_min = 12, gabarit_min = 4.5)
}


#' Gabarit libre sous branches le long d'un trace
#'
#' Hauteur libre au-dessus de la chaussee -- la hauteur de la plus basse branche
#' ou du plus bas echo de sursol qui surplombe l'emprise -- calculee directement
#' sur le nuage classe (BRIEF section 3.7). Critere reel pour un grumier
#' (~4,5 m), totalement absent des bases existantes. Une valeur elevee (jusqu'au
#' `plafond`) signifie un ciel degage au-dessus de la chaussee.
#'
#' @param trace Un `sf`/`sfc` `LINESTRING` (ou la sortie de [dsr_pathfinder()]).
#' @param dalle Chemin d'un fichier LAZ/LAS/COPC classe.
#' @param demi_largeur_route Demi-largeur de chaussee consideree, en metres.
#'   Defaut 1.5.
#' @param seuil_bas Hauteur au sol minimale (m) d'un echo pour compter comme
#'   obstacle (ignore le sol et le bruit). Defaut 0.3.
#' @param plafond Hauteur (m) au-dela de laquelle on considere le ciel degage
#'   (absence d'obstacle). Defaut 8.
#' @param res Resolution de la grille de sursol, en metres. Defaut 1.
#' @param pas Espacement des stations le long du trace, en metres. Defaut 2.
#'
#' @return Un `sf` `POINT` par station, avec `chainage` et `GABARIT_LIBRE` (m).
#' @seealso [dsr_trafficability()].
#' @export
dsr_gabarit_libre <- function(trace, dalle, demi_largeur_route = 1.5,
                              seuil_bas = 0.3, plafond = 8, res = 1, pas = 2) {
  dsr_verifier_lasR()
  if (is.list(trace) && !is.null(trace$trace)) trace <- trace$trace
  if (!is.character(dalle) || !file.exists(dalle)) {
    dsr_abort("{.arg dalle} doit etre un chemin de fichier LAZ/LAS existant.")
  }
  geom <- sf::st_geometry(trace)
  bb <- as.numeric(sf::st_bbox(sf::st_buffer(geom, demi_largeur_route + 2)))

  # Grille de la plus basse hauteur de sursol (hauteur au sol des echos > seuil).
  pipeline <- lasR::reader_las_rectangles(bb[1], bb[2], bb[3], bb[4]) +
    lasR::normalize() +
    lasR::rasterize(res, "min", filter = lasR::keep_z_above(seuil_bas),
      ofile = lasR::temptif())
  ans <- lasR::exec(pipeline, on = dalle)
  # exec renvoie un SpatRaster (un seul etage de sortie), une liste, ou un chemin.
  gab <- ans
  if (is.list(gab) && !inherits(gab, "SpatRaster")) {
    ok <- vapply(gab, function(x) inherits(x, "SpatRaster") || is.character(x), logical(1))
    gab <- gab[ok][[1]]
  }
  if (is.character(gab)) gab <- terra::rast(gab)

  # Gabarit par station = plus bas obstacle sur la largeur de chaussee ; aucun
  # obstacle sous le plafond -> ciel degage (= plafond).
  pr <- dsr_profils(trace, gab, pas = pas, demi_largeur = demi_largeur_route,
    pas_travers = res / 2, methode = "simple")
  gab_st <- apply(pr$z, 1, function(v) {
    m <- suppressWarnings(min(v, na.rm = TRUE))
    if (!is.finite(m) || m > plafond) plafond else m
  })

  st <- pr$stations
  st$GABARIT_LIBRE <- gab_st
  st
}


#' Aptitude au grumier et motif d'inaptitude
#'
#' Combine les mesures geometriques par station ([dsr_measure()]) et, si fourni,
#' le gabarit libre ([dsr_gabarit_libre()]) en un verdict `APTE_GRUMIER` et, ce
#' qui le rend exploitable sur le terrain, le `MOTIF_INAPTITUDE` : **quel critere
#' bloque, et ou** (BRIEF section 3.7). Un booleen sans motif est inutilisable.
#'
#' @param stations Le `sf` `stations` de [dsr_measure()] (colonnes
#'   `LARGEUR_ROULABLE`, `PENTE_LONG`, `RAYON_COURBURE` ; `GABARIT_LIBRE`
#'   optionnel).
#' @param seuils Seuils d'aptitude ; defaut [dsr_seuils_grumier()].
#'
#' @return Une liste : `stations` (les memes, avec `APTE_GRUMIER` logique et
#'   `MOTIF_INAPTITUDE` -- criteres bloquants separes par `+`, `""` si apte) et
#'   `resume` (part de longueur apte et compte par motif).
#' @seealso [dsr_measure()], [dsr_gabarit_libre()], [dsr_seuils_grumier()].
#' @export
dsr_trafficability <- function(stations, seuils = dsr_seuils_grumier()) {
  if (!inherits(stations, "sf")) {
    dsr_abort("{.arg stations} doit etre un {.cls sf} (sortie de {.fun dsr_measure}).")
  }
  req <- c("LARGEUR_ROULABLE", "PENTE_LONG", "RAYON_COURBURE")
  manque <- setdiff(req, names(stations))
  if (length(manque)) {
    dsr_abort("Colonnes manquantes dans {.arg stations} : {.val {manque}}.")
  }

  criteres <- list(
    largeur = stations$LARGEUR_ROULABLE < seuils$largeur_min,
    pente   = abs(stations$PENTE_LONG) > seuils$pente_max,
    rayon   = stations$RAYON_COURBURE < seuils$rayon_min
  )
  if ("GABARIT_LIBRE" %in% names(stations)) {
    criteres$gabarit <- stations$GABARIT_LIBRE < seuils$gabarit_min
  }

  mat <- vapply(criteres, function(x) isTRUE_vec(x), logical(nrow(stations)))
  motif <- apply(mat, 1, function(r) paste(names(criteres)[r], collapse = "+"))
  apte <- motif == ""

  stations$APTE_GRUMIER <- apte
  stations$MOTIF_INAPTITUDE <- motif

  # Resume : part de stations apte + compte par critere bloquant.
  comptes <- colSums(mat, na.rm = TRUE)
  resume <- list(
    part_apte = mean(apte, na.rm = TRUE),
    n_stations = nrow(stations),
    par_motif = comptes
  )
  list(stations = stations, resume = resume)
}


#' Detecter les elargissements (places de depot / retournement)
#'
#' Reperage des elargissements locaux de la chaussee le long du trace : une
#' station dont la largeur roulable depasse nettement la largeur courante est un
#' candidat place de depot ou de retournement (BRIEF section 3.7), sortie a part
#' entiere.
#'
#' @param stations Le `sf` `stations` de [dsr_measure()] (colonne
#'   `LARGEUR_ROULABLE`, `chainage`).
#' @param marge Surlargeur minimale (m) au-dessus de la mediane pour signaler un
#'   elargissement. Defaut 2.
#' @param long_min Longueur minimale continue (m) d'un elargissement. Defaut 6.
#'
#' @return Un `sf` `POINT` des centres d'elargissement, avec `chainage`,
#'   `longueur` et `largeur_max`. Zero ligne si aucun.
#' @seealso [dsr_measure()].
#' @export
dsr_places <- function(stations, marge = 2, long_min = 6) {
  if (!all(c("LARGEUR_ROULABLE", "chainage") %in% names(stations))) {
    dsr_abort("{.arg stations} doit porter {.field LARGEUR_ROULABLE} et {.field chainage}.")
  }
  larg <- stations$LARGEUR_ROULABLE
  ch <- stations$chainage
  seuil <- stats::median(larg, na.rm = TRUE) + marge
  large <- !is.na(larg) & larg >= seuil

  runs <- rle(large)
  fin <- cumsum(runs$lengths)
  deb <- fin - runs$lengths + 1L
  xy <- sf::st_coordinates(stations)[, 1:2, drop = FALSE]
  crs <- sf::st_crs(stations)

  places <- lapply(which(runs$values), function(r) {
    idx <- deb[r]:fin[r]
    longueur <- ch[fin[r]] - ch[deb[r]]
    if (longueur < long_min) return(NULL)
    ic <- idx[which.max(larg[idx])]
    sf::st_sf(
      chainage = ch[ic], longueur = longueur, largeur_max = max(larg[idx]),
      geometry = sf::st_sfc(sf::st_point(xy[ic, ]), crs = crs)
    )
  })
  places <- places[!vapply(places, is.null, logical(1))]
  if (length(places) == 0L) {
    return(sf::st_sf(
      chainage = numeric(0), longueur = numeric(0), largeur_max = numeric(0),
      geometry = sf::st_sfc(crs = crs)
    ))
  }
  do.call(rbind, places)
}


# TRUE la ou x est TRUE, FALSE ailleurs (y compris NA) : un critere non evaluable
# ne doit pas declarer une inaptitude.
#' @noRd
isTRUE_vec <- function(x) !is.na(x) & x
