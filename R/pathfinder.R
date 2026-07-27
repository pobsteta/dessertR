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
