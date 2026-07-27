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

  g <- terra::values(sigma_geo, mat = FALSE)
  s <- terra::values(sigma_surf, mat = FALSE)
  geo_fort  <- g >= seuil_geo
  surf_fort <- s >= seuil_surf

  code <- rep(NA_integer_, length(g))
  ok <- !is.na(g) & !is.na(s)
  code[ok &  geo_fort &  surf_fort] <- 1L # en_service
  code[ok &  geo_fort & !surf_fort] <- 2L # abandonnee
  code[ok & !geo_fort &  surf_fort] <- 3L # trouee_sans_route
  code[ok & !geo_fort & !surf_fort] <- 4L # hors_route

  out <- terra::rast(sigma_geo)
  terra::values(out) <- code
  names(out) <- "etat"
  levels(out) <- DSR_ETAT_NIVEAUX
  out
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
