# Interface R du noyau de recherche de chemin anisotrope (BRIEF section 3.5). Le
# calcul (Dijkstra sur l'etat (cellule, cap), voisinage 16, anisotropie et
# courbure) vit dans le crate Rust ; ici on prepare les grilles a plat, on
# convertit les points en cellules et on recolle le trace en geometrie sf.

#' Trace de moindre cout anisotrope entre deux points
#'
#' Recherche le chemin optimal sur la conductivite geomorphologique `sigma_geo`,
#' avec un **cout anisotrope** (les deplacements en travers de l'orientation
#' locale `theta` sont penalises : une route a une direction) et une **penalite
#' de courbure** (BRIEF section 3.5). Le voisinage 16 supprime le biais de
#' metrication du Dijkstra 8-connexe (traces en escalier). Le pathfinder tourne
#' sur `sigma_geo` (robuste a la vegetation) ; l'etat de la desserte se lit
#' ensuite le long du trace ([dsr_etat()]).
#'
#' @param sigma_geo Conductivite geomorphologique, `SpatRaster` mono-couche
#'   (sortie de [dsr_conductivite()]) ; `NA` = infranchissable.
#' @param depart,arrivee Extremites : un `POINT` `sf`/`sfc`, un couple
#'   numerique `c(x, y)`, ou un indice de cellule entier.
#' @param theta Orientation locale des lineaires en degres (`vesselness` /
#'   `theta` de [dsr_layers_dtm()]), aligne sur `sigma_geo` ; `NULL` -> isotrope.
#' @param poids Force de l'anisotropie par cellule (p. ex. `vesselness`, 0..1),
#'   aligne sur `sigma_geo` ; `NULL` -> 0 (isotrope).
#' @param k Nombre de caps discrets de l'etat d'orientation. Defaut 16.
#' @param lambda Poids de l'anisotropie (penalite de traverse). Defaut 4.
#' @param mu Poids de la courbure (penalite de changement de cap). Defaut 2.
#' @param sigma_min Plancher de conductivite (evite les resistances infinies).
#'   Defaut 0.05.
#' @param cout_cumule Renvoyer aussi le champ de cout minimal a la source (utile
#'   pour l'incertitude laterale). Defaut `FALSE`.
#'
#' @return Une liste : `trace` (un `sf` `LINESTRING`, du depart a l'arrivee, avec
#'   la colonne `cout`), `cout` (le cout total) et `cout_cumule` (un `SpatRaster`
#'   ou `NULL`).
#' @seealso [dsr_conductivite()], [dsr_layers_dtm()], [dsr_etat()].
#' @examples
#' \donttest{
#' sg <- terra::rast(nrows = 40, ncols = 40, xmin = 0, xmax = 40, ymin = 0,
#'   ymax = 40, crs = "EPSG:2154")
#' terra::values(sg) <- 0.1
#' sg[20, ] <- 0.95 # un couloir conducteur horizontal
#' tr <- dsr_pathfinder(sg, c(1, 20.5), c(39, 20.5))
#' tr$cout
#' }
#' @export
dsr_pathfinder <- function(sigma_geo, depart, arrivee, theta = NULL, poids = NULL,
                           k = 16L, lambda = 4, mu = 2, sigma_min = 0.05,
                           cout_cumule = FALSE) {
  if (!inherits(sigma_geo, "SpatRaster")) {
    dsr_abort("{.arg sigma_geo} doit etre un {.cls SpatRaster}.")
  }
  if (terra::nlyr(sigma_geo) > 1L) sigma_geo <- sigma_geo[[1]]

  ncell <- terra::ncell(sigma_geo)
  th <- if (is.null(theta)) rep(NA_real_, ncell) else dsr_valeurs_alignees(theta, sigma_geo, "theta")
  wt <- if (is.null(poids)) rep(0, ncell) else dsr_valeurs_alignees(poids, sigma_geo, "poids")
  sg <- terra::values(sigma_geo, mat = FALSE)

  src <- dsr_cellule(sigma_geo, depart) - 1L
  dst <- dsr_cellule(sigma_geo, arrivee) - 1L
  if (is.na(src) || is.na(dst)) {
    dsr_abort("{.arg depart} ou {.arg arrivee} tombe hors de l'emprise de {.arg sigma_geo}.")
  }

  r <- pathfinder_anisotrope(
    sg, th, wt, terra::nrow(sigma_geo), terra::ncol(sigma_geo),
    terra::res(sigma_geo)[1], as.integer(k), lambda, mu, sigma_min,
    as.integer(src), as.integer(dst)
  )
  if (length(r$path) < 2L || is.na(r$cost)) {
    dsr_abort(c(
      "Aucun chemin trouve entre {.arg depart} et {.arg arrivee}.",
      "i" = "Verifier que les deux points sont relies par des cellules non {.code NA}."
    ))
  }

  xy <- terra::xyFromCell(sigma_geo, r$path)
  crs <- sf::st_crs(terra::crs(sigma_geo))
  trace <- sf::st_sf(
    cout = r$cost,
    geometry = sf::st_sfc(sf::st_linestring(xy), crs = crs)
  )

  cc <- NULL
  if (isTRUE(cout_cumule)) {
    cc <- terra::rast(sigma_geo)
    terra::values(cc) <- r$cumcost
    names(cc) <- "cout_cumule"
  }
  list(trace = trace, cout = r$cost, cout_cumule = cc)
}


#' Repositionner un reseau de reference sous contrainte
#'
#' Recale chaque troncon d'un reseau de reference (BD TOPO) sur le MNT lidar via
#' le pathfinder, **sans jamais s'ecarter de plus de `deviation_max` metres de
#' l'axe d'origine** (couloir dur) et en etant attire vers cet axe (contrainte
#' douce). La reference fait autorite : la validation a montre qu'un
#' repositionnement libre sur `sigma_geo` accroche des lineaires paralleles
#' (fosses, traces fossiles, risque n.1 du BRIEF) et degrade la mesure. La
#' contrainte l'empeche.
#'
#' La **totalite du reseau de reference est conservee** : si le pathfinder
#' echoue sur un troncon, on garde sa geometrie d'origine. Le recalage ne peut
#' donc que deplacer un axe dans son couloir, jamais en supprimer.
#'
#' @param reseau Un `sf` de `LINESTRING` (reseau de reference, p. ex. BD TOPO).
#' @param sigma_geo Conductivite geomorphologique ([dsr_conductivite()]),
#'   `SpatRaster`.
#' @param theta,poids Orientation et force d'anisotropie ([dsr_layers_dtm()]),
#'   alignes sur `sigma_geo` ; `NULL` -> isotrope.
#' @param deviation_max Ecart lateral maximal a l'axe d'origine, en metres.
#'   Defaut 10.
#' @param attraction Force du rappel vers l'axe (0 = aucun ; plus grand = plus
#'   colle a l'axe). Defaut 1.
#' @param lambda,mu,sigma_min Parametres du pathfinder ([dsr_pathfinder()]).
#'
#' @return Le `sf` d'entree, geometries recalees, avec les colonnes
#'   `DEPLACEMENT_MAX` et `DEPLACEMENT_MOY` (ecart a l'axe d'origine, m) et
#'   `RECALE` (logique : `FALSE` = repli sur l'origine).
#' @seealso [dsr_pathfinder()], [dsr_conductivite()], [dsr_measure()].
#' @export
dsr_repositionner <- function(reseau, sigma_geo, theta = NULL, poids = NULL,
                              deviation_max = 10, attraction = 1,
                              lambda = 4, mu = 2, sigma_min = 0.05) {
  if (!inherits(reseau, "sf")) dsr_abort("{.arg reseau} doit etre un {.cls sf}.")
  if (!inherits(sigma_geo, "SpatRaster")) {
    dsr_abort("{.arg sigma_geo} doit etre un {.cls SpatRaster}.")
  }
  g <- sf::st_geometry(reseau)
  n <- length(g)
  geoms <- vector("list", n)
  dmax <- rep(NA_real_, n); dmoy <- rep(NA_real_, n); recale <- rep(FALSE, n)

  for (i in seq_len(n)) {
    axe <- g[i]
    res <- dsr_recaler_une(axe, sigma_geo, theta, poids, deviation_max,
      attraction, lambda, mu, sigma_min)
    if (is.null(res)) {
      geoms[[i]] <- axe[[1]] # repli : conserver l'axe BD TOPO
    } else {
      geoms[[i]] <- res
      pts <- sf::st_cast(sf::st_sfc(res, crs = sf::st_crs(reseau)), "POINT")
      d <- as.numeric(sf::st_distance(pts, axe))
      dmax[i] <- max(d); dmoy[i] <- mean(d); recale[i] <- TRUE
    }
  }

  out <- sf::st_set_geometry(reseau, sf::st_sfc(geoms, crs = sf::st_crs(reseau)))
  out$DEPLACEMENT_MAX <- dmax
  out$DEPLACEMENT_MOY <- dmoy
  out$RECALE <- recale
  out
}


# Recaler un axe unique dans son couloir +/- deviation_max. Renvoie un
# LINESTRING (sfg) ou NULL en cas d'echec.
#' @noRd
dsr_recaler_une <- function(axe, sigma_geo, theta, poids, deviation_max,
                            attraction, lambda, mu, sigma_min) {
  bb <- sf::st_bbox(sf::st_buffer(axe, deviation_max + 5))
  e <- terra::ext(bb[["xmin"]], bb[["xmax"]], bb[["ymin"]], bb[["ymax"]])
  sg <- tryCatch(terra::crop(sigma_geo, e), error = function(err) NULL)
  if (is.null(sg) || terra::ncell(sg) < 4L) return(NULL)

  # Distance a l'axe : couloir dur (NA au-dela) + attraction douce vers l'axe.
  ax <- terra::rasterize(terra::vect(sf::st_as_sf(axe)), sg, field = 1)
  dist <- terra::distance(ax)
  sgv <- terra::values(sg, mat = FALSE)
  dv <- terra::values(dist, mat = FALSE)
  eff <- sgv / (1 + attraction * (dv / deviation_max)^2)
  # Resserrer d'une diagonale de maille : `dist` mesure au centre des cellules de
  # l'axe rasterise (sous-estime la distance a la ligne d'un demi-pixel). Sans
  # cela un sommet recale pourrait depasser `deviation_max` de ~une maille.
  seuil <- deviation_max - sqrt(2) * terra::res(sg)[1]
  eff[is.na(dv) | dv > seuil] <- NA
  if (all(is.na(eff))) return(NULL)
  sg_eff <- terra::setValues(sg, eff)

  th <- if (!is.null(theta)) terra::crop(theta, sg) else NULL
  pv <- if (!is.null(poids)) terra::crop(poids, sg) else NULL

  co <- sf::st_coordinates(axe)[, 1:2, drop = FALSE]
  tr <- tryCatch(
    dsr_pathfinder(sg_eff, co[1, ], co[nrow(co), ], theta = th, poids = pv,
      lambda = lambda, mu = mu, sigma_min = sigma_min)$trace,
    error = function(err) NULL)
  if (is.null(tr)) NULL else sf::st_geometry(tr)[[1]]
}


# Extraire les valeurs d'un raster en verifiant qu'il est aligne sur la
# reference (grille et emprise identiques).
#' @noRd
dsr_valeurs_alignees <- function(r, reference, nom) {
  if (!inherits(r, "SpatRaster")) {
    dsr_abort("{.arg {nom}} doit etre un {.cls SpatRaster}.")
  }
  if (!terra::compareGeom(r, reference, stopOnError = FALSE, messages = FALSE)) {
    dsr_abort(c(
      "{.arg {nom}} n'est pas aligne sur {.arg sigma_geo}.",
      "i" = "Les produire sur la meme grille de reference ({.fun dsr_grille_reference})."
    ))
  }
  terra::values(r, mat = FALSE)
}


# Convertir une extremite (point sf/sfc, couple x/y, ou indice de cellule) en
# indice de cellule 1-based du raster.
#' @noRd
dsr_cellule <- function(raster, point) {
  if (inherits(point, c("sf", "sfc"))) {
    xy <- sf::st_coordinates(sf::st_geometry(point))[1, 1:2, drop = FALSE]
    return(terra::cellFromXY(raster, xy))
  }
  if (is.numeric(point) && length(point) == 2L) {
    return(terra::cellFromXY(raster, matrix(point, ncol = 2)))
  }
  if (is.numeric(point) && length(point) == 1L) {
    return(as.integer(point))
  }
  dsr_abort("Une extremite doit etre un {.cls POINT}, un couple {.code c(x, y)}, ou un indice de cellule.")
}
