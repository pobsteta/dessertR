# Mesure de la geometrie de la desserte le long d'un trace (BRIEF section 3.6).
# Premier livrable metier : mesurer ce que la BD TOPO ne dit pas ou dit mal --
# largeur roulable reelle, fosses, devers, pente longitudinale, rayon de
# courbure, sinuosite. On travaille par PROFILS TRANSVERSAUX preleves tous les
# `pas` metres, perpendiculairement au trace, sur le MNT (a 50 cm pour la finesse
# de la plateforme et des fosses).

#' Profils transversaux le long d'un trace
#'
#' Preleve, tous les `pas` metres le long d'un trace, un profil d'altitude
#' **perpendiculaire** au trace, echantillonne sur le MNT (BRIEF section 3.6).
#' C'est la matiere premiere de [dsr_measure()].
#'
#' @param trace Un `sf`/`sfc` `LINESTRING` (ou l'element `trace` de
#'   [dsr_pathfinder()]).
#' @param mnt Le MNT (`SpatRaster`), de preference a 50 cm.
#' @param pas Espacement des profils le long du trace, en metres. Defaut 2.
#' @param demi_largeur Demi-largeur des profils, en metres. Defaut 8.
#' @param pas_travers Pas d'echantillonnage transversal, en metres. Defaut 0.5.
#'
#' @return Une liste : `stations` (`sf` `POINT` des centres, avec `chainage`),
#'   `offsets` (positions transversales, m), `z` (matrice `stations x offsets`
#'   des altitudes), `normales` (matrice `stations x 2`, vecteur transversal
#'   unitaire par station).
#' @seealso [dsr_measure()].
#' @export
dsr_profils <- function(trace, mnt, pas = 2, demi_largeur = 8, pas_travers = 0.5) {
  if (is.list(trace) && !is.null(trace$trace)) trace <- trace$trace
  if (!inherits(mnt, "SpatRaster")) dsr_abort("{.arg mnt} doit etre un {.cls SpatRaster}.")
  if (terra::nlyr(mnt) > 1L) mnt <- mnt[[1]]
  geom <- sf::st_geometry(trace)
  if (length(geom) > 1L) geom <- sf::st_line_merge(sf::st_union(geom))
  crs <- sf::st_crs(geom)

  # Stations REGULIEREMENT espacees (pas) par interpolation le long du trace :
  # un simple segmentize garderait l'escalier pixel du pathfinder (pas ~ 0,
  # tangentes bruitees, courbure pixelisee).
  long <- as.numeric(sf::st_length(geom))
  if (!is.finite(long) || long < 2 * pas) dsr_abort("{.arg trace} trop court pour des profils.")
  frac <- unique(c(seq(0, 1, by = pas / long), 1))
  pts <- sf::st_line_sample(geom, sample = frac)
  xy <- sf::st_coordinates(pts)[, c("X", "Y"), drop = FALSE]
  ns <- nrow(xy)
  if (ns < 3L) dsr_abort("{.arg trace} trop court pour des profils.")
  chainage <- c(0, cumsum(sqrt(rowSums(diff(xy)^2))))

  # Tangente centree -> normale unitaire (transversale) par station.
  tg <- matrix(0, ns, 2)
  tg[2:(ns - 1), ] <- xy[3:ns, ] - xy[1:(ns - 2), ]
  tg[1, ] <- xy[2, ] - xy[1, ]
  tg[ns, ] <- xy[ns, ] - xy[ns - 1, ]
  norme <- sqrt(rowSums(tg^2))
  norme[norme == 0] <- 1
  tg <- tg / norme
  normales <- cbind(-tg[, 2], tg[, 1]) # rotation 90 deg

  offsets <- seq(-demi_largeur, demi_largeur, by = pas_travers)
  no <- length(offsets)

  # Tous les points de tous les transects, en un seul extract (efficace).
  # Point = centre + offset * normale, pour chaque station x offset.
  off_m <- matrix(offsets, ns, no, byrow = TRUE)
  px <- matrix(xy[, 1], ns, no) + matrix(normales[, 1], ns, no) * off_m
  py <- matrix(xy[, 2], ns, no) + matrix(normales[, 2], ns, no) * off_m

  # Interpolation bilineaire : sans quoi un echantillonnage transversal plus fin
  # que la maille du MNT donne un profil en escalier (gradient corrompu).
  z <- matrix(
    terra::extract(mnt, cbind(as.vector(px), as.vector(py)), method = "bilinear")[, 1],
    ns, no
  )

  stations <- sf::st_sf(
    chainage = chainage,
    geometry = sf::st_sfc(lapply(seq_len(ns), function(i) sf::st_point(xy[i, ])), crs = crs)
  )
  list(stations = stations, offsets = offsets, z = z, normales = normales)
}


#' Mesurer la geometrie de la desserte le long d'un trace
#'
#' Derive, station par station, les attributs geometriques d'une desserte a
#' partir des profils transversaux ([dsr_profils()]) et du fil du trace (BRIEF
#' section 3.6) : largeur roulable, devers, presence de fosses, pente
#' longitudinale, plus les metriques globales de rayon de courbure et de
#' sinuosite. Optionnellement la confiance du MNT (densite de points sol) et le
#' deplacement par rapport a une geometrie de reference (BD TOPO).
#'
#' @details
#' La finesse des mesures depend directement de la qualite du MNT. Sous couvert
#' dense, le MNT interpole a partir de points sol epars presente un bruit
#' vertical decimetrique a metrique (BRIEF, risque n.3) qui degrade la largeur
#' roulable et la pente longitudinale : d'ou le lissage (`liss_travers`,
#' `liss_long`) et l'interet, pour la mesure fine, de descendre au MNT 50 cm et
#' de recalculer un micro-MNT sur les seuls points sol de l'emprise (a venir).
#'
#' @param trace Un `sf`/`sfc` `LINESTRING` (ou la sortie de [dsr_pathfinder()]).
#' @param mnt Le MNT (`SpatRaster`).
#' @param pas,demi_largeur,pas_travers Parametres des profils, voir
#'   [dsr_profils()].
#' @param seuil_devers Pente transversale (m/m) sous laquelle la surface est
#'   consideree roulable. Defaut 0.12 (~7 deg).
#' @param prof_fosse Profondeur minimale (m) d'un creux lateral pour compter un
#'   fosse. Defaut 0.2.
#' @param liss_travers,liss_long Fenetres de lissage (en echantillons) des
#'   profils, transversale et longitudinale. Indispensables sur un MNT bruite
#'   sous couvert dense (voir Details). Defaut 3 et 5.
#' @param reference Geometrie de reference `sf`/`sfc` (p. ex. le troncon BD TOPO
#'   d'origine) pour le `DEPLACEMENT` ; `NULL` pour l'omettre.
#' @param confiance `SpatRaster` de confiance (p. ex. `densite_sol` de
#'   [dsr_layers_pc()]) pour `CONFIANCE_MNT` ; `NULL` pour l'omettre.
#'
#' @return Une liste : `stations` (`sf` `POINT` avec `LARGEUR_ROULABLE`,
#'   `DEVERS`, `FOSSES`, `PENTE_LONG`, et si fournis `CONFIANCE_MNT`,
#'   `DEPLACEMENT`), et `resume` (metriques globales : `LARGEUR_ROULABLE_MED`,
#'   `PENTE_LONG_MOY`, `PENTE_LONG_MAX`, `RAYON_COURBURE_MIN`, `SINUOSITE`).
#' @seealso [dsr_profils()], [dsr_pathfinder()].
#' @examples
#' \donttest{
#' mnt <- terra::rast(nrows = 60, ncols = 60, xmin = 0, xmax = 60, ymin = 0,
#'   ymax = 60, resolution = 1, crs = "EPSG:2154")
#' terra::values(mnt) <- 100
#' tr <- sf::st_sf(geometry = sf::st_sfc(
#'   sf::st_linestring(cbind(c(5, 55), c(30, 30))), crs = 2154))
#' m <- dsr_measure(tr, mnt)
#' m$resume
#' }
#' @export
dsr_measure <- function(trace, mnt, pas = 2, demi_largeur = 8, pas_travers = 0.5,
                        seuil_devers = 0.12, prof_fosse = 0.2,
                        liss_travers = 3, liss_long = 5,
                        reference = NULL, confiance = NULL) {
  pr <- dsr_profils(trace, mnt, pas = pas, demi_largeur = demi_largeur,
    pas_travers = pas_travers)
  offsets <- pr$offsets
  z <- pr$z
  ns <- nrow(z)
  ic <- which.min(abs(offsets)) # colonne du centre (offset ~ 0)

  larg <- numeric(ns); dev <- numeric(ns); fos <- integer(ns)
  for (i in seq_len(ns)) {
    zi <- dsr_lisser(z[i, ], liss_travers) # attenue le bruit du MNT sous couvert
    m <- dsr_mesurer_profil(zi, offsets, ic, seuil_devers, prof_fosse)
    larg[i] <- m$largeur; dev[i] <- m$devers; fos[i] <- m$fosses
  }

  # Pente longitudinale locale (dz/ds) au centre du trace, sur z lisse.
  zc <- dsr_lisser(z[, ic], liss_long)
  ch <- pr$stations$chainage
  pente <- rep(NA_real_, ns)
  dz <- diff(zc); ds <- diff(ch)
  g <- dz / ds
  pente[1] <- g[1]; pente[ns] <- g[ns - 1]
  pente[2:(ns - 1)] <- (g[1:(ns - 2)] + g[2:(ns - 1)]) / 2

  st <- pr$stations
  st$LARGEUR_ROULABLE <- larg
  st$DEVERS <- dev
  st$FOSSES <- fos
  st$PENTE_LONG <- pente

  if (!is.null(confiance)) {
    st$CONFIANCE_MNT <- terra::extract(confiance[[1]], sf::st_coordinates(st))[, 1]
  }
  if (!is.null(reference)) {
    ref <- sf::st_geometry(reference)
    st$DEPLACEMENT <- as.numeric(sf::st_distance(st, sf::st_union(ref)))
  }

  resume <- list(
    LARGEUR_ROULABLE_MED = stats::median(larg, na.rm = TRUE),
    PENTE_LONG_MOY = mean(abs(pente), na.rm = TRUE),
    PENTE_LONG_MAX = max(abs(pente), na.rm = TRUE),
    RAYON_COURBURE_MIN = dsr_rayon_courbure_min(sf::st_coordinates(st)[, 1:2]),
    SINUOSITE = dsr_sinuosite(sf::st_coordinates(st)[, 1:2])
  )
  list(stations = st, resume = resume)
}


# Mesurer un profil transversal : largeur roulable (region centrale de pente
# transversale faible), devers (pente transversale moyenne), et presence de
# fosses lateraux (creux au-dela des bords de plateforme).
#' @noRd
dsr_mesurer_profil <- function(zi, offsets, ic, seuil_devers, prof_fosse) {
  no <- length(offsets)
  pt <- offsets[2] - offsets[1]
  grad <- rep(NA_real_, no)
  grad[2:(no - 1)] <- (zi[3:no] - zi[1:(no - 2)]) / (2 * pt)

  plat <- function(dir) {
    k <- ic
    repeat {
      nk <- k + dir
      if (nk < 1 || nk > no || is.na(grad[nk]) || abs(grad[nk]) > seuil_devers) break
      k <- nk
    }
    k
  }
  il <- plat(-1L); ir <- plat(1L)
  largeur <- offsets[ir] - offsets[il]
  devers <- mean(grad[il:ir], na.rm = TRUE)

  # Fosse : creux au-dela du bord, dans une fenetre de ~4 m, plus bas que le
  # bord de plateforme d'au moins `prof_fosse`.
  fenetre <- max(1L, round(4 / pt))
  fosse <- function(edge, dir) {
    idx <- edge + dir * seq_len(fenetre)
    idx <- idx[idx >= 1 & idx <= no]
    if (length(idx) == 0L) return(0L)
    as.integer((zi[edge] - min(zi[idx], na.rm = TRUE)) > prof_fosse)
  }
  fosses <- fosse(il, -1L) + fosse(ir, 1L)
  list(largeur = largeur, devers = devers, fosses = fosses)
}


# Moyenne glissante ignorant les NA (fenetre `w` echantillons, centree).
#' @noRd
dsr_lisser <- function(v, w) {
  if (w <= 1L) return(v)
  n <- length(v)
  half <- (w - 1L) %/% 2L
  out <- v
  for (i in seq_len(n)) {
    lo <- max(1L, i - half); hi <- min(n, i + half)
    out[i] <- mean(v[lo:hi], na.rm = TRUE)
  }
  out
}


# Rayon de courbure minimal d'une polyligne (m), via le cercle circonscrit a
# chaque triplet de sommets consecutifs.
#' @noRd
dsr_rayon_courbure_min <- function(xy) {
  n <- nrow(xy)
  if (n < 3L) return(Inf)
  rmin <- Inf
  for (i in 2:(n - 1)) {
    a <- sqrt(sum((xy[i, ] - xy[i - 1, ])^2))
    b <- sqrt(sum((xy[i + 1, ] - xy[i, ])^2))
    c <- sqrt(sum((xy[i + 1, ] - xy[i - 1, ])^2))
    aire <- abs((xy[i, 1] - xy[i - 1, 1]) * (xy[i + 1, 2] - xy[i - 1, 2]) -
      (xy[i + 1, 1] - xy[i - 1, 1]) * (xy[i, 2] - xy[i - 1, 2])) / 2
    if (aire > 1e-9) {
      r <- (a * b * c) / (4 * aire)
      if (r < rmin) rmin <- r
    }
  }
  rmin
}


# Sinuosite : longueur developpee / distance a vol d'oiseau entre extremites.
#' @noRd
dsr_sinuosite <- function(xy) {
  n <- nrow(xy)
  dev <- sum(sqrt(rowSums(diff(xy)^2)))
  droit <- sqrt(sum((xy[n, ] - xy[1, ])^2))
  if (droit < 1e-9) return(NA_real_)
  dev / droit
}
