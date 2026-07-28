# Detection de la desserte ABSENTE de la reference (BRIEF section 3.9, v2). Le
# gisement le plus important : pistes, cloisonnements, anciennes RF que la
# BD TOPO ne porte pas. On repere les empreintes lineaires en creux (sigma_geo /
# vesselness) HORS du corridor du reseau de reference, et on en extrait une
# centre-ligne. Pour une vectorisation fine, chainer avec `vecnet` ; ce module
# fournit une detection premiere, defendable et sans dependance externe.

#' Detecter la desserte hors reference
#'
#' Repere les axes de desserte probables **absents du reseau de reference** : les
#' cellules de forte conductivite geomorphologique (et, si fourni, de forte
#' linearite `vesselness`) situees **hors** d'un tampon autour de la reference,
#' regroupees en composantes connexes puis reduites a une centre-ligne par
#' analyse en composantes principales (BRIEF section 3.9). Complementaire du
#' recalage, qui lui conserve la reference ([dsr_repositionner()]).
#'
#' @param sigma_geo Conductivite geomorphologique ([dsr_conductivite()]),
#'   `SpatRaster`.
#' @param reference `sf`/`sfc` du reseau de reference (BD TOPO) a exclure ;
#'   `NULL` pour ne rien exclure.
#' @param vesselness Raster de linearite ([dsr_layers_dtm()]) pour restreindre
#'   aux structures lineaires ; `NULL` pour l'ignorer.
#' @param seuil,seuil_vessel Seuils de conductivite et de linearite. Defaut 0.6
#'   et 0.3.
#' @param buffer_ref Demi-largeur (m) du corridor de reference a exclure. Defaut
#'   15.
#' @param long_min Longueur minimale (m) d'un axe detecte. Defaut 30.
#' @param ratio_min Rapport d'allongement minimal (grand axe / petit axe) d'une
#'   composante pour etre traitee comme lineaire. Defaut 3.
#' @param pas_bin Pas d'echantillonnage (m) le long de l'axe principal pour la
#'   centre-ligne. Defaut 5.
#'
#' @return Un `sf` `LINESTRING` des axes detectes (colonnes `id`, `longueur`),
#'   ou un `sf` vide si aucun. A affiner avec `vecnet` pour une vectorisation
#'   topologique complete.
#' @seealso [dsr_conductivite()], [dsr_repositionner()].
#' @export
dsr_detecter <- function(sigma_geo, reference = NULL, vesselness = NULL,
                         seuil = 0.6, seuil_vessel = 0.3, buffer_ref = 15,
                         long_min = 30, ratio_min = 3, pas_bin = 5) {
  if (!inherits(sigma_geo, "SpatRaster")) {
    dsr_abort("{.arg sigma_geo} doit etre un {.cls SpatRaster}.")
  }
  crs <- sf::st_crs(terra::crs(sigma_geo))
  vide <- sf::st_sf(id = integer(0), longueur = numeric(0),
    geometry = sf::st_sfc(crs = crs))

  cand <- sigma_geo >= seuil
  if (!is.null(vesselness)) cand <- cand & (vesselness >= seuil_vessel)
  cand <- terra::ifel(cand, 1L, NA_integer_)

  if (!is.null(reference)) {
    buf <- sf::st_buffer(sf::st_union(sf::st_geometry(reference)), buffer_ref)
    cand <- terra::mask(cand, terra::vect(sf::st_as_sf(buf)), inverse = TRUE)
  }
  if (all(is.na(terra::values(cand, mat = FALSE)))) return(vide)

  # Composantes connexes -> centre-ligne par ACP des cellules de chaque tache.
  pat <- terra::patches(cand, directions = 8L, zeroAsNA = TRUE)
  vals <- terra::values(pat, mat = FALSE)
  ids <- sort(unique(vals[!is.na(vals)]))
  min_cells <- max(5L, as.integer(long_min / terra::res(sigma_geo)[1]))

  lignes <- list()
  for (id in ids) {
    cells <- which(vals == id)
    if (length(cells) < min_cells) next
    xy <- terra::xyFromCell(pat, cells)
    ln <- dsr_centre_ligne_acp(xy, pas_bin, ratio_min)
    if (is.null(ln)) next
    if (as.numeric(sf::st_length(sf::st_sfc(ln, crs = crs))) >= long_min) {
      lignes[[length(lignes) + 1L]] <- ln
    }
  }
  if (length(lignes) == 0L) return(vide)

  sf::st_sf(
    id = seq_along(lignes),
    longueur = vapply(lignes, function(l) as.numeric(sf::st_length(sf::st_sfc(l, crs = crs))), numeric(1)),
    geometry = sf::st_sfc(lignes, crs = crs)
  )
}


# Centre-ligne d'un nuage de cellules par ACP : projette sur l'axe principal,
# bille le long de cet axe et prend la position transversale mediane par bille.
# Renvoie un LINESTRING (sfg) ou NULL si la tache n'est pas assez lineaire.
#' @noRd
dsr_centre_ligne_acp <- function(xy, pas_bin, ratio_min) {
  if (nrow(xy) < 5L) return(NULL)
  ctr <- colMeans(xy)
  cxy <- sweep(xy, 2, ctr)
  e <- eigen(stats::cov(cxy), symmetric = TRUE)
  sdev <- sqrt(pmax(e$values, 0))
  if (sdev[2] <= 1e-6 || sdev[1] / sdev[2] < ratio_min) return(NULL)

  axe <- e$vectors[, 1]; perp_v <- e$vectors[, 2]
  along <- as.numeric(cxy %*% axe)
  across <- as.numeric(cxy %*% perp_v)
  br <- seq(min(along), max(along), by = pas_bin)
  if (length(br) < 2L) return(NULL)
  bin <- findInterval(along, br, rightmost.closed = TRUE)

  pts <- do.call(rbind, lapply(sort(unique(bin)), function(b) {
    idx <- bin == b
    ctr + mean(along[idx]) * axe + stats::median(across[idx]) * perp_v
  }))
  if (nrow(pts) < 2L) return(NULL)
  sf::st_linestring(pts)
}
