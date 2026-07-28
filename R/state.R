# Etat de la desserte par DIVERGENCE des canaux (BRIEF section 3.4). C'est le
# point fort du dispositif : plutot qu'un score composite, on lit l'etat dans
# l'ecart entre la memoire longue du terrain (sigma_geo) et l'etat de surface
# present (sigma_surf).
#
#   sigma_geo | sigma_surf | interpretation
#   ----------+------------+-------------------------------------------------
#   fort      | fort       | Route en service
#   fort      | faible     | Route abandonnee / recolonisee   <- le signal
#   faible    | fort       | Trouee sans route (coupe, ligne, layon) : FP
#   faible    | faible     | Pas de route
#
# Plus interpretable et directement defendable dans une publication qu'un SCORE
# composite a la ALSroads.

# Codes et libelles des classes d'etat (raster categoriel terra).
#' @noRd
DSR_ETAT_NIVEAUX <- data.frame(
  value = c(1L, 2L, 3L, 4L),
  etat  = c("en_service", "abandonnee", "trouee_sans_route", "hors_route")
)


#' Divergence des canaux de conductivite
#'
#' Ecart signe `sigma_geo - sigma_surf`. Positif la ou l'empreinte persiste dans
#' le terrain mais que la surface s'est refermee : c'est la signature d'une
#' **route abandonnee / recolonisee** (BRIEF section 3.4). Negatif sur les
#' trouees sans route (faux positifs geomorphologiques).
#'
#' @param sigma_geo,sigma_surf `SpatRaster` mono-couche alignes, dans `[0, 1]`.
#' @return Un `SpatRaster` mono-couche `divergence` dans `[-1, 1]`.
#' @seealso [dsr_etat()].
#' @export
dsr_divergence <- function(sigma_geo, sigma_surf) {
  dsr_verifier_alignement(sigma_geo, sigma_surf)
  out <- sigma_geo - sigma_surf
  names(out) <- "divergence"
  out
}


#' Etat de la desserte par croisement des deux conductivites
#'
#' Classe chaque cellule en quatre etats selon le croisement de `sigma_geo`
#' (empreinte dans le terrain) et `sigma_surf` (emprise encore degagee), par
#' seuillage (BRIEF section 3.4) :
#'
#' \describe{
#'   \item{`en_service`}{`sigma_geo` fort et `sigma_surf` fort.}
#'   \item{`abandonnee`}{`sigma_geo` fort et `sigma_surf` faible -- **le signal
#'     recherche** : route recolonisee.}
#'   \item{`trouee_sans_route`}{`sigma_geo` faible et `sigma_surf` fort --
#'     faux positif geomorphologique (coupe rase, ligne electrique, layon).}
#'   \item{`hors_route`}{les deux faibles.}
#' }
#'
#' L'etat n'est reellement interpretable que **le long d'un trace retenu** par le
#' pathfinder ; en raster plein il sert d'inspection et de diagnostic.
#'
#' @param sigma_geo,sigma_surf `SpatRaster` mono-couche alignes, dans `[0, 1]`
#'   (sorties de [dsr_conductivite()] et [dsr_sigma_surf()]).
#' @param seuil_geo,seuil_surf Seuils de bascule fort/faible. Defaut 0.5.
#' @return Un `SpatRaster` categoriel `etat` (facteur a 4 niveaux, voir
#'   description), aligne sur les entrees.
#' @seealso [dsr_conductivite()], [dsr_sigma_surf()], [dsr_divergence()].
#' @examples
#' \donttest{
#' sg <- terra::rast(nrows = 4, ncols = 4, xmin = 0, xmax = 4, ymin = 0, ymax = 4,
#'   crs = "EPSG:2154")
#' ss <- terra::rast(sg)
#' terra::values(sg) <- c(rep(0.9, 8), rep(0.1, 8))
#' terra::values(ss) <- rep(c(0.9, 0.1), 8)
#' e <- dsr_etat(sg, ss)
#' terra::levels(e)
#' }
#' @export
dsr_etat <- function(sigma_geo, sigma_surf, seuil_geo = 0.5, seuil_surf = 0.5) {
  dsr_verifier_alignement(sigma_geo, sigma_surf)

  code <- .dsr_classer_etat(
    terra::values(sigma_geo, mat = FALSE),
    terra::values(sigma_surf, mat = FALSE),
    seuil_geo, seuil_surf
  )

  out <- terra::rast(sigma_geo)
  terra::values(out) <- code
  names(out) <- "etat"
  levels(out) <- DSR_ETAT_NIVEAUX
  out
}


#' Etat de la desserte le long d'un trace
#'
#' Echantillonne `sigma_geo` et `sigma_surf` le long d'un trace (sortie de
#' [dsr_pathfinder()] ou geometrie de reference BD TOPO), en classe l'etat par
#' troncon et resume la repartition. C'est la lecture **pertinente** de l'etat :
#' en raster plein il est bruite (faux positifs geomorphologiques sous couvert),
#' mais le long du trace retenu il devient interpretable (BRIEF section 3.4).
#'
#' @param trace Un `sf`/`sfc` `LINESTRING` (ou l'element `trace` renvoye par
#'   [dsr_pathfinder()]).
#' @param sigma_geo,sigma_surf `SpatRaster` mono-couche alignes, dans `[0, 1]`.
#' @param pas Pas d'echantillonnage le long du trace, en metres. Defaut 2.
#' @param seuil_geo,seuil_surf Seuils de bascule fort/faible. Defaut 0.5.
#'
#' @return Une liste :
#'   \describe{
#'     \item{`troncons`}{`sf` `LINESTRING` decoupe en segments d'etat homogene,
#'       colonnes `etat`, `longueur`, `sigma_geo`, `sigma_surf`, `divergence`.}
#'     \item{`profil`}{`sf` `POINT` echantillonne, avec `chainage` (m) et les
#'       memes valeurs -- le profil longitudinal.}
#'     \item{`resume`}{`data.frame` : longueur et pourcentage par etat.}
#'   }
#' @seealso [dsr_etat()], [dsr_pathfinder()].
#' @export
dsr_etat_trace <- function(trace, sigma_geo, sigma_surf, pas = 2,
                           seuil_geo = 0.5, seuil_surf = 0.5) {
  dsr_verifier_alignement(sigma_geo, sigma_surf)
  if (is.list(trace) && !is.null(trace$trace)) trace <- trace$trace
  geom <- sf::st_geometry(trace)
  if (!all(as.character(sf::st_geometry_type(geom)) %in%
        c("LINESTRING", "MULTILINESTRING"))) {
    dsr_abort("{.arg trace} doit etre une geometrie {.code LINESTRING}.")
  }
  crs <- sf::st_crs(geom)

  # Densifier a `pas` metres puis relever les sommets ordonnes. Pour un trace en
  # plusieurs parties, les fusionner d'abord (sinon le chainage saute).
  if (length(geom) > 1L) geom <- sf::st_line_merge(sf::st_union(geom))
  ligne <- sf::st_segmentize(geom, dfMaxLength = pas)
  xy <- sf::st_coordinates(ligne)[, c("X", "Y"), drop = FALSE]
  if (nrow(xy) < 2L) dsr_abort("{.arg trace} est trop court pour etre echantillonne.")

  seg <- sqrt(rowSums(diff(xy)^2))
  chainage <- c(0, cumsum(seg))

  g <- terra::extract(sigma_geo, xy)[, 1]
  s <- terra::extract(sigma_surf, xy)[, 1]
  code_pt <- .dsr_classer_etat(g, s, seuil_geo, seuil_surf)

  # Profil longitudinal (points).
  profil <- sf::st_sf(
    chainage   = chainage,
    sigma_geo  = g,
    sigma_surf = s,
    divergence = g - s,
    etat       = .dsr_etiqueter_etat(code_pt),
    geometry   = sf::st_sfc(
      lapply(seq_len(nrow(xy)), function(i) sf::st_point(xy[i, ])), crs = crs
    )
  )

  # Segments (entre sommets consecutifs), etat = celui du sommet amont.
  n <- nrow(xy)
  code_seg <- code_pt[-n]
  runs <- rle(ifelse(is.na(code_seg), -1L, code_seg))
  fin <- cumsum(runs$lengths)
  deb <- fin - runs$lengths + 1L
  troncons <- do.call(rbind, lapply(seq_along(runs$lengths), function(r) {
    idx <- deb[r]:(fin[r] + 1L) # sommets du troncon (segments + borne finale)
    cd <- runs$values[r]
    sf::st_sf(
      etat       = .dsr_etiqueter_etat(if (cd < 0) NA_integer_ else cd),
      longueur   = chainage[fin[r] + 1L] - chainage[deb[r]],
      sigma_geo  = mean(g[idx], na.rm = TRUE),
      sigma_surf = mean(s[idx], na.rm = TRUE),
      divergence = mean(g[idx] - s[idx], na.rm = TRUE),
      geometry   = sf::st_sfc(sf::st_linestring(xy[idx, , drop = FALSE]), crs = crs)
    )
  }))

  # Resume : longueur et part par etat.
  long_tot <- sum(troncons$longueur)
  resume <- stats::aggregate(longueur ~ etat, data = sf::st_drop_geometry(troncons), FUN = sum)
  resume$pourcentage <- round(100 * resume$longueur / long_tot, 1)
  resume <- resume[order(-resume$longueur), ]

  list(troncons = troncons, profil = profil, resume = resume)
}


# Classification d'etat par croisement seuille (partagee par dsr_etat et
# dsr_etat_trace). Renvoie des codes 1..4, NA si une entree est NA.
#' @noRd
.dsr_classer_etat <- function(g, s, seuil_geo, seuil_surf) {
  geo_fort  <- g >= seuil_geo
  surf_fort <- s >= seuil_surf
  code <- rep(NA_integer_, length(g))
  ok <- !is.na(g) & !is.na(s)
  code[ok &  geo_fort &  surf_fort] <- 1L # en_service
  code[ok &  geo_fort & !surf_fort] <- 2L # abandonnee
  code[ok & !geo_fort &  surf_fort] <- 3L # trouee_sans_route
  code[ok & !geo_fort & !surf_fort] <- 4L # hors_route
  code
}


# Codes d'etat -> facteur libelle, dans l'ordre canonique.
#' @noRd
.dsr_etiqueter_etat <- function(code) {
  factor(DSR_ETAT_NIVEAUX$etat[match(code, DSR_ETAT_NIVEAUX$value)],
    levels = DSR_ETAT_NIVEAUX$etat)
}


# Verifier que deux rasters partagent grille et emprise (sinon la comparaison
# cellule a cellule n'a pas de sens).
#' @noRd
dsr_verifier_alignement <- function(a, b) {
  if (!inherits(a, "SpatRaster") || !inherits(b, "SpatRaster")) {
    dsr_abort("Les deux entrees doivent etre des {.cls SpatRaster}.")
  }
  if (!terra::compareGeom(a, b, stopOnError = FALSE, messages = FALSE)) {
    dsr_abort(c(
      "Les rasters {.arg sigma_geo} et {.arg sigma_surf} ne sont pas alignes.",
      "i" = "Les produire sur la meme grille de reference ({.fun dsr_grille_reference})."
    ))
  }
  invisible(TRUE)
}
