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
#' @param methode Interpolation de l'extraction : `"bilinear"` (defaut, pour un
#'   MNT continu) ou `"simple"` (plus proche voisin, pour une grille a trous
#'   comme la hauteur de sursol).
#'
#' @return Une liste : `stations` (`sf` `POINT` des centres, avec `chainage`),
#'   `offsets` (positions transversales, m), `z` (matrice `stations x offsets`
#'   des altitudes), `normales` (matrice `stations x 2`, vecteur transversal
#'   unitaire par station).
#' @seealso [dsr_measure()].
#' @export
dsr_profils <- function(trace, mnt, pas = 2, demi_largeur = 8, pas_travers = 0.5,
                        methode = c("bilinear", "simple")) {
  methode <- match.arg(methode)
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
    terra::extract(mnt, cbind(as.vector(px), as.vector(py)), method = methode)[, 1],
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
#' **Largeur roulable.** `"planeite"` ajuste le plan de chaussee sur une fenetre
#' centrale puis s'ecarte tant que la surface reste a moins de `tol_planeite` de
#' ce plan, avec interpolation du bord entre echantillons. `"gradient"` retient
#' la plage ou la pente transversale reste sous `seuil_devers`. Sur un profil de
#' synthese de largeur connue (4,00 m, bombement 3 %) :
#'
#' | bruit du MNT | `"gradient"` | `"planeite"` |
#' |---|---|---|
#' | aucun  | 3,00 m (-1,00) | 3,92 m (-0,08) |
#' | 5 cm   | 2,56 m (-1,44) | 3,72 m (-0,28) |
#' | 10 cm  | 0,93 m (-3,08) | 3,66 m (-0,34) |
#'
#' Surtout, le biais de `"gradient"` depend du pas transversal (-3,74 m a
#' `pas_travers = 0.1`, 0,00 m a 1 m) autant que de `seuil_devers` : un seuil
#' cale sur un jeu ne vaut que pour ce pas et ce niveau de bruit. C'est pourquoi
#' `"planeite"` est le defaut — voir [dsr_calibrer_largeur()] pour la suite.
#'
#' `tol_planeite` a une lecture physique : il doit **depasser la fleche du
#' bombement**, soit `bombement x largeur / 2`. Une route de 6 m bombee a 3 %
#' (fleche 9 cm) passe avec le defaut de 10 cm ; la meme bombee a 6 % (fleche
#' 18 cm) est tronquee a 4,4 m et demande 0,20. Le bombement, symetrique, n'est
#' pas un devers : `DEVERS` ne retient que l'inclinaison d'ensemble, celle qui
#' compte pour la stabilite d'un chargement.
#'
#' **Rayon de courbure.** Il est ajuste par un cercle des moindres carres sur
#' une fenetre de `base_courbure` metres, et non sur trois stations
#' consecutives. La quantification du trace vectorise (un sommet par cellule)
#' rend le cercle circonscrit inutilisable : sur un arc de rayon vrai 60 m,
#' quantifie au metre puis lisse, la mediane des rayons vaut
#'
#' | estimateur | mediane |
#' |---|---|
#' | 3 stations consecutives | 16,6 m |
#' | cercle des moindres carres, base 20 m | 49,0 m |
#' | cercle des moindres carres, base 30 m | 56,5 m |
#' | cercle des moindres carres, base 50 m | 60,0 m |
#'
#' La base par defaut (30 m) est aussi l'ordre de grandeur d'un ensemble
#' routier grumier : c'est l'echelle a laquelle la courbure contraint reellement
#' le passage. `RAYON_COURBURE_P05` est le quantile 5 % ; le preferer au
#' minimum, qui reste sensible a une station aberrante.
#'
#' @param trace Un `sf`/`sfc` `LINESTRING` (ou la sortie de [dsr_pathfinder()]).
#' @param mnt Le MNT (`SpatRaster`).
#' @param pas,demi_largeur,pas_travers Parametres des profils, voir
#'   [dsr_profils()].
#' @param seuil_devers Pente transversale (m/m) sous laquelle la surface est
#'   consideree roulable. Defaut 0.15 (~8,5 deg) ; sur route de montagne a fort
#'   devers, monter a 0.20. Methode `"gradient"` seulement.
#' @param prof_fosse Profondeur minimale (m) d'un creux lateral pour compter un
#'   fosse. Defaut 0.2.
#' @param liss_travers,liss_long Fenetres de lissage (en echantillons) des
#'   profils, transversale et longitudinale. Indispensables sur un MNT bruite
#'   sous couvert dense (voir Details). Defaut 3 et 5.
#' @param methode_largeur `"planeite"` (defaut) ou `"gradient"` (methode
#'   historique) ; voir Details.
#' @param tol_planeite Ecart maximal (m) au plan de chaussee ajuste, methode
#'   `"planeite"` seulement. Defaut 0.10.
#' @param base_courbure Longueur (m) de la fenetre d'ajustement du cercle de
#'   courbure. `0` pour revenir au cercle circonscrit a trois stations
#'   consecutives. Defaut 30.
#' @param reference Geometrie de reference `sf`/`sfc` (p. ex. le troncon BD TOPO
#'   d'origine) pour le `DEPLACEMENT` ; `NULL` pour l'omettre.
#' @param confiance `SpatRaster` de confiance (p. ex. `densite_sol` de
#'   [dsr_layers_pc()]) pour `CONFIANCE_MNT` ; `NULL` pour l'omettre.
#'
#' @return Une liste : `stations` (`sf` `POINT` avec `LARGEUR_ROULABLE`,
#'   `DEVERS`, `FOSSES`, `PENTE_LONG`, et si fournis `CONFIANCE_MNT`,
#'   `DEPLACEMENT`), et `resume` (metriques globales : `LARGEUR_ROULABLE_MED`,
#'   `PENTE_LONG_MOY`, `PENTE_LONG_MAX`, `RAYON_COURBURE_MIN`,
#'   `RAYON_COURBURE_P05`, `SINUOSITE`).
#' @seealso [dsr_profils()], [dsr_pathfinder()], [dsr_calibrer_largeur()].
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
                        seuil_devers = 0.15, prof_fosse = 0.2,
                        liss_travers = 3, liss_long = 5,
                        methode_largeur = c("planeite", "gradient"),
                        tol_planeite = 0.10, base_courbure = 30,
                        reference = NULL, confiance = NULL) {
  methode_largeur <- match.arg(methode_largeur)
  pr <- dsr_profils(trace, mnt, pas = pas, demi_largeur = demi_largeur,
    pas_travers = pas_travers)
  offsets <- pr$offsets
  z <- pr$z
  ns <- nrow(z)
  ic <- which.min(abs(offsets)) # colonne du centre (offset ~ 0)

  larg <- numeric(ns); dev <- numeric(ns); fos <- integer(ns)
  for (i in seq_len(ns)) {
    zi <- dsr_lisser(z[i, ], liss_travers) # attenue le bruit du MNT sous couvert
    m <- dsr_mesurer_profil(zi, offsets, ic, seuil_devers, prof_fosse,
      methode = methode_largeur, tol_planeite = tol_planeite)
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

  xy <- sf::st_coordinates(pr$stations)[, 1:2]
  rayon <- if (is.finite(base_courbure) && base_courbure > 0) {
    .dsr_rayon_cercle(xy, base_courbure)
  } else {
    dsr_rayon_courbure_vec(xy)
  }

  st <- pr$stations
  st$LARGEUR_ROULABLE <- larg
  st$DEVERS <- dev
  st$FOSSES <- fos
  st$PENTE_LONG <- pente
  st$RAYON_COURBURE <- rayon

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
    RAYON_COURBURE_MIN = min(rayon[is.finite(rayon)], Inf),
    RAYON_COURBURE_P05 = if (any(is.finite(rayon))) {
      unname(stats::quantile(rayon[is.finite(rayon)], 0.05))
    } else Inf,
    SINUOSITE = dsr_sinuosite(sf::st_coordinates(st)[, 1:2])
  )
  list(stations = st, resume = resume)
}


# Mesurer un profil transversal : largeur roulable, devers, fosses lateraux.
#
# Deux estimateurs de largeur, voir dsr_measure(). Le critere de fosse est
# commun : un creux au-dela du bord de plateforme, dans une fenetre de ~4 m,
# plus bas que ce bord d'au moins `prof_fosse`.
#' @noRd
dsr_mesurer_profil <- function(zi, offsets, ic, seuil_devers, prof_fosse,
                               methode = c("planeite", "gradient"),
                               tol_planeite = 0.10, base_plan = 1,
                               tol_ecart = 2L) {
  methode <- match.arg(methode)
  no <- length(offsets)
  pt <- offsets[2] - offsets[1]

  m <- if (identical(methode, "planeite")) {
    .dsr_largeur_planeite(zi, offsets, ic, tol_planeite, base_plan, tol_ecart)
  } else {
    .dsr_largeur_gradient(zi, offsets, ic, seuil_devers)
  }
  if (m$largeur <= 0) {
    return(list(largeur = 0, devers = m$devers, fosses = 0L))
  }

  fenetre <- max(1L, round(4 / pt))
  fosse <- function(edge, dir) {
    idx <- edge + dir * seq_len(fenetre)
    idx <- idx[idx >= 1 & idx <= no]
    if (length(idx) == 0L) return(0L)
    as.integer((zi[edge] - min(zi[idx], na.rm = TRUE)) > prof_fosse)
  }
  list(largeur = m$largeur, devers = m$devers,
    fosses = fosse(m$il, -1L) + fosse(m$ir, 1L))
}


# Largeur par PLANEITE (defaut). On ajuste le plan de chaussee sur une fenetre
# centrale, puis on s'ecarte de part et d'autre tant que la surface reste a
# moins de `tol` de ce plan.
#
# Trois raisons de proceder ainsi plutot que par seuil de pente :
#   - le devers est ABSORBE par le plan ajuste, au lieu d'etre confondu avec un
#     bord de chaussee (une route bombee a 8 % n'est pas un talus) ;
#   - le residu est une hauteur en metres, donc le critere ne depend pas du pas
#     d'echantillonnage transversal, contrairement a un gradient dont le bruit
#     croit comme sigma / pas_travers ;
#   - le bord est interpole entre deux echantillons, ce qui supprime le biais
#     systematique de troncature.
#' @noRd
.dsr_largeur_planeite <- function(zi, offsets, ic, tol, base_plan, tol_ecart) {
  no <- length(offsets)
  pt <- offsets[2] - offsets[1]
  k <- max(2L, as.integer(round(base_plan / pt)))
  win <- max(1L, ic - k):min(no, ic + k)
  ok <- is.finite(zi[win])
  if (sum(ok) < 3L) return(list(largeur = 0, devers = NA_real_, il = ic, ir = ic))

  fit <- stats::lm.fit(cbind(1, offsets[win][ok]), zi[win][ok])
  res <- zi - (fit$coefficients[1] + fit$coefficients[2] * offsets)

  bord <- function(dir) {
    i <- ic; manques <- 0L; dernier <- ic
    repeat {
      i <- i + dir
      if (i < 1L || i > no) break
      if (!is.finite(res[i]) || abs(res[i]) > tol) {
        manques <- manques + 1L
        if (manques > tol_ecart) break
      } else {
        manques <- 0L
        dernier <- i
      }
    }
    j <- dernier + dir
    pos <- if (j >= 1L && j <= no && is.finite(res[j]) &&
        abs(res[j]) > tol && abs(res[j]) > abs(res[dernier])) {
      f <- (tol - abs(res[dernier])) / (abs(res[j]) - abs(res[dernier]))
      offsets[dernier] + f * (offsets[j] - offsets[dernier])
    } else {
      offsets[dernier]
    }
    list(pos = pos, idx = dernier)
  }
  g <- bord(-1L); d <- bord(1L)
  list(largeur = max(0, d$pos - g$pos), devers = unname(fit$coefficients[2]),
    il = g$idx, ir = d$idx)
}


# Largeur par SEUIL DE PENTE (methode historique). Chaussee = plage ou la pente
# transversale reste sous `seuil_devers`, contenant le centre -- ou la plus
# proche du centre si l'axe de reference tombe sur un talus.
#
# Conservee pour comparaison, mais son biais depend du pas d'echantillonnage et
# du lissage autant que du seuil : elle n'est pas calibrable telle quelle
# (voir dsr_calibrer_largeur()).
#' @noRd
.dsr_largeur_gradient <- function(zi, offsets, ic, seuil_devers) {
  no <- length(offsets)
  pt <- offsets[2] - offsets[1]
  grad <- rep(NA_real_, no)
  grad[2:(no - 1)] <- (zi[3:no] - zi[1:(no - 2)]) / (2 * pt)

  plat <- !is.na(grad) & abs(grad) <= seuil_devers
  rr <- rle(plat)
  fin <- cumsum(rr$lengths)
  deb <- fin - rr$lengths + 1L
  segs <- which(rr$values)
  if (length(segs) == 0L) {
    return(list(largeur = 0, devers = NA_real_, il = ic, ir = ic))
  }
  contient <- vapply(segs, function(k) deb[k] <= ic && ic <= fin[k], logical(1))
  k <- if (any(contient)) segs[which(contient)[1]] else {
    centres <- vapply(segs, function(k) (offsets[deb[k]] + offsets[fin[k]]) / 2,
      numeric(1))
    segs[which.min(abs(centres))]
  }
  il <- deb[k]; ir <- fin[k]
  list(largeur = offsets[ir] - offsets[il],
    devers = mean(grad[il:ir], na.rm = TRUE), il = il, ir = ir)
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


# Rayon de courbure par station (m) par ajustement algebrique d'un cercle aux
# moindres carres sur une fenetre de `base` metres centree sur la station.
# Inf quand la fenetre est trop courte ou le systeme degenere (alignement).
#' @noRd
.dsr_rayon_cercle <- function(xy, base) {
  n <- nrow(xy)
  r <- rep(Inf, n)
  if (n < 4L || !is.finite(base) || base <= 0) return(r)
  s <- c(0, cumsum(sqrt(rowSums(diff(xy)^2))))
  for (i in seq_len(n)) {
    sel <- which(abs(s - s[i]) <= base / 2)
    if (length(sel) < 4L) next
    x <- xy[sel, 1]; y <- xy[sel, 2]
    dec <- qr(cbind(x, y, 1))
    if (dec$rank < 3L) next
    cf <- qr.coef(dec, x^2 + y^2)
    rr <- cf[3] + (cf[1]^2 + cf[2]^2) / 4
    if (!is.finite(rr) || rr <= 0) next
    r[i] <- sqrt(rr)
  }
  r
}


# Rayon de courbure par sommet (m), via le cercle circonscrit a chaque triplet
# de sommets consecutifs ; Inf aux extremites et sur les alignements.
# Conserve pour comparaison : sur un trace quantifie il sous-estime d'un ordre
# de grandeur (voir dsr_measure(), section Details).
#' @noRd
dsr_rayon_courbure_vec <- function(xy) {
  n <- nrow(xy)
  r <- rep(Inf, n)
  if (n < 3L) return(r)
  for (i in 2:(n - 1)) {
    a <- sqrt(sum((xy[i, ] - xy[i - 1, ])^2))
    b <- sqrt(sum((xy[i + 1, ] - xy[i, ])^2))
    cc <- sqrt(sum((xy[i + 1, ] - xy[i - 1, ])^2))
    aire <- abs((xy[i, 1] - xy[i - 1, 1]) * (xy[i + 1, 2] - xy[i - 1, 2]) -
      (xy[i + 1, 1] - xy[i - 1, 1]) * (xy[i, 2] - xy[i - 1, 2])) / 2
    if (aire > 1e-9) r[i] <- (a * b * cc) / (4 * aire)
  }
  r
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


#' Calibrer la mesure de largeur sur une reference terrain
#'
#' Balaie une grille de parametres de [dsr_measure()] et confronte la largeur
#' mesuree a une largeur de reference (releves du gestionnaire, GNSS,
#' photo-interpretation), station par station. Renvoie le tableau des ecarts,
#' trie du meilleur au pire, pour arbitrer sur des chiffres plutot que sur une
#' impression.
#'
#' @details
#' **Le calibrage ne peut pas commencer par le seuil.** Avec
#' `methode_largeur = "gradient"`, le biais depend du pas transversal et du
#' lissage autant que de `seuil_devers` : la valeur trouvee ne vaudrait que pour
#' un triplet de parametres et un niveau de bruit. C'est pourquoi le defaut est
#' `"planeite"`, dont le biais est stable (voir [dsr_measure()]) — un seuil cale
#' sur un massif a alors une chance d'etre transferable.
#'
#' **Separer le biais de mesure de l'ecart de definition.** Un biais residuel
#' constant, une fois la methode stabilisee, ne signale pas une erreur de mesure
#' mais un desaccord sur ce qu'on mesure : la largeur roulable retient la bande
#' de faible devers, tandis qu'une « largeur carrossable » de gestionnaire inclut
#' souvent les accotements. C'est une question a trancher avec le gestionnaire,
#' pas un parametre a tordre. Regarder `biais` et `mae` ensemble : un biais
#' constant avec une MAE faible est un decalage de definition ; une MAE forte
#' avec un biais faible est du bruit de mesure.
#'
#' **Stratifier.** La qualite du MNT commande tout (BRIEF, risque n.3) : passer
#' `confiance` (typiquement `densite_sol` de [dsr_layers_pc()]) fait sortir les
#' ecarts par classe de confiance. Un biais qui se creuse quand la densite de
#' points sol s'effondre n'appelle pas un autre seuil, il appelle une reserve sur
#' le domaine de validite.
#'
#' @param traces `sf` des troncons a mesurer.
#' @param mnt Le MNT (`SpatRaster`).
#' @param reference `sf` portant la largeur de reference.
#' @param champ_largeur Nom de la colonne de `reference` portant la largeur (m).
#' @param grille `data.frame` des combinaisons a essayer ; une colonne par
#'   argument de [dsr_measure()] a faire varier. `NULL` (defaut) balaie
#'   `methode_largeur` x `tol_planeite`.
#' @param long_min Longueur minimale (m) d'un troncon mesure. Defaut 30.
#' @param confiance `SpatRaster` de confiance pour la stratification ; `NULL`
#'   pour ne pas stratifier.
#' @param seuils_confiance Bornes de stratification de `confiance`. Defaut
#'   `c(0, 2, 5, Inf)` (points sol par m2).
#' @param ... Arguments communs transmis a [dsr_measure()].
#'
#' @return Un `data.frame` : les colonnes de `grille`, puis `n` (stations
#'   appariees), `biais` (mesure - reference, m), `mae`, `rmse`, `med_dsr`,
#'   `med_ref`. Trie par `mae` croissante. Si `confiance` est fourni, une ligne
#'   par combinaison **et** par classe de confiance, avec la colonne `strate`.
#' @seealso [dsr_measure()], [dsr_layers_pc()].
#' @export
dsr_calibrer_largeur <- function(traces, mnt, reference, champ_largeur,
                                 grille = NULL, long_min = 30,
                                 confiance = NULL,
                                 seuils_confiance = c(0, 2, 5, Inf), ...) {
  if (!inherits(traces, "sf")) dsr_abort("{.arg traces} doit etre un {.cls sf}.")
  if (!inherits(mnt, "SpatRaster")) dsr_abort("{.arg mnt} doit etre un {.cls SpatRaster}.")
  if (!champ_largeur %in% names(reference)) {
    dsr_abort("{.arg reference} ne porte pas la colonne {.field {champ_largeur}}.")
  }
  if (is.null(grille)) {
    grille <- expand.grid(
      methode_largeur = c("planeite", "gradient"),
      tol_planeite = c(0.05, 0.10, 0.20),
      stringsAsFactors = FALSE
    )
  }
  ref_larg <- reference[[champ_largeur]]
  garde <- as.numeric(sf::st_length(traces)) >= long_min

  lignes <- list()
  for (k in seq_len(nrow(grille))) {
    args_k <- as.list(grille[k, , drop = FALSE])
    sta <- .dsr_mesurer_lot(traces[garde, ], mnt, args_k, list(...))
    if (is.null(sta) || nrow(sta) == 0L) next

    proche <- sf::st_nearest_feature(sta, reference)
    d <- data.frame(dsr = sta$LARGEUR_ROULABLE, ref = ref_larg[proche])
    if (!is.null(confiance)) {
      d$conf <- terra::extract(confiance[[1]], sf::st_coordinates(sta))[, 1]
    }
    d <- d[is.finite(d$dsr) & is.finite(d$ref) & d$ref > 0, , drop = FALSE]
    if (nrow(d) == 0L) next

    if (is.null(confiance)) {
      lignes[[length(lignes) + 1L]] <- cbind(grille[k, , drop = FALSE],
        strate = NA_character_, .dsr_ecarts(d$dsr, d$ref))
    } else {
      d$strate <- cut(d$conf, breaks = seuils_confiance, include.lowest = TRUE)
      for (s in levels(d$strate)) {
        di <- d[!is.na(d$strate) & d$strate == s, , drop = FALSE]
        if (nrow(di) == 0L) next
        lignes[[length(lignes) + 1L]] <- cbind(grille[k, , drop = FALSE],
          strate = s, .dsr_ecarts(di$dsr, di$ref))
      }
    }
  }
  if (length(lignes) == 0L) {
    dsr_abort(c(
      "Aucune station appariee a la reference.",
      "i" = "Verifier le recouvrement entre {.arg traces}, {.arg mnt} et {.arg reference}."
    ))
  }
  out <- do.call(rbind, lignes)
  rownames(out) <- NULL
  out[order(out$mae), , drop = FALSE]
}


# Mesure d'un lot de troncons sous un jeu de parametres ; les troncons en echec
# sont ignores plutot que d'interrompre le balayage.
#' @noRd
.dsr_mesurer_lot <- function(traces, mnt, args_var, args_fixes) {
  out <- list()
  for (i in seq_len(nrow(traces))) {
    m <- tryCatch(
      do.call(dsr_measure, c(list(traces[i, ], mnt), args_var, args_fixes)),
      error = function(e) NULL
    )
    if (!is.null(m)) {
      m$stations$troncon <- i
      out[[length(out) + 1L]] <- m$stations
    }
  }
  if (length(out) == 0L) return(NULL)
  do.call(rbind, out)
}


# Ecarts a la reference : le biais dit le decalage systematique (souvent une
# question de definition), la MAE la dispersion (du bruit de mesure).
#' @noRd
.dsr_ecarts <- function(dsr, ref) {
  data.frame(
    n = length(dsr),
    biais = mean(dsr - ref),
    mae = mean(abs(dsr - ref)),
    rmse = sqrt(mean((dsr - ref)^2)),
    med_dsr = stats::median(dsr),
    med_ref = stats::median(ref)
  )
}
