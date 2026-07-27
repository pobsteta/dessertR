# Canal surface et qualite, via lasR (BRIEF section 3.3). C'est le module qui
# justifie l'ajout du nuage : le profil vertical dans l'emprise (densite d'echos
# entre 0,3 et 3 m au-dessus du sol) separe « route degagee sous couvert haut »
# de « route recolonisee », signal totalement absent du MNH et de tout raster
# derive. Fournit aussi la couche de CONFIANCE du MNT (densite de points sol) :
# la ou elle s'effondre, l'openness est du bruit et sigma_geo doit le savoir.
#
# lasR fonctionne par pipelines (lecteur -> etages -> exec) executes en C++
# multi-thread, avec gestion native du tuilage et des buffers. On qualifie
# TOUJOURS les appels par lasR:: car plusieurs noms (rasterize, normalize)
# entrent en collision avec terra.

#' Canaux de surface et de qualite du nuage de points
#'
#' Rasterise, via `lasR`, les metriques du nuage classe qui portent l'etat de
#' surface d'une desserte et la confiance du MNT (BRIEF section 3.3), sur une
#' grille alignee sur le MNT :
#'
#' \describe{
#'   \item{`densite_sol`}{points sol (classe 2) au m2 -- **couche de confiance**
#'     du MNT, pas de detection.}
#'   \item{`taux_penetration`}{points sol / points totaux -- ouverture de la
#'     canopee au-dessus de l'emprise.}
#'   \item{`densite_sousetage`}{echos entre `sousetage` m au-dessus du sol,
#'     rapportes au total -- **recolonisation de l'emprise, le signal d'abandon**,
#'     inaccessible au MNH.}
#'   \item{`h_couvert`}{percentile haut de la vegetation haute (hauteur au sol).}
#'   \item{`masque_exclusion`}{1 la ou une classe neutralisee (eau, points
#'     virtuels, sursol perenne, batiment) est presente.}
#'   \item{`masque_pont`}{1 la ou la classe tablier de pont est presente --
#'     corridors franchissables.}
#' }
#'
#' @details
#' Les hauteurs au sol sont obtenues par `lasR::normalize()` (TIN des points sol).
#' Les points virtuels sont exclus du calcul de `densite_sol`. Le regime corridor
#' (lecture restreinte a l'emprise) rend le traitement d'un massif realiste :
#' passer `emprise` limite la lecture a un rectangle ; passer en plus `masque`
#' decoupe finement les sorties au corridor.
#'
#' @param dalle Chemin d'un fichier LAZ/LAS/COPC, ou une ligne de
#'   [dsr_catalog()] (colonne `laz`).
#' @param res Resolution des rasters en metres. Defaut 1 (aligne sur la grille de
#'   reference ; 2 suffit pour les seules metriques de couvert).
#' @param grille Grille de reference ([dsr_grille_reference()]) pour aligner les
#'   sorties ; `NULL` conserve la grille native de `lasR`.
#' @param emprise Restreint la **lecture** a un rectangle : `NULL` (dalle
#'   entiere), un vecteur `c(xmin, ymin, xmax, ymax)`, ou un objet `sf`/`sfc`/
#'   `SpatVector` (son emprise est utilisee).
#' @param masque Objet `sf`/`sfc`/`SpatVector` pour **decouper** finement les
#'   sorties (corridor) ; `NULL` pour ne pas masquer.
#' @param sousetage Bornes de hauteur du sous-etage, en metres. Defaut
#'   `c(0.3, 3)`.
#' @param classe_sol,classe_couvert,classe_pont Codes ASPRS du sol (2), de la
#'   vegetation haute (5) et du tablier de pont (17).
#' @param classes_exclusion Codes ASPRS a neutraliser. Defaut `c(6, 9, 64, 66)`
#'   (batiment, eau, sursol perenne, points virtuels).
#' @param seuil_couvert Percentile de hauteur pour `h_couvert`. Defaut 0.95.
#'
#' @return Un `SpatRaster` multi-bandes aligne (si `grille` fourni) portant les
#'   canaux ci-dessus. Noms compatibles avec la suite du traitement (`sigma_surf`,
#'   etat, confiance de [dsr_conductivite()]).
#' @seealso [dsr_conductivite()] (consomme `densite_sol` comme confiance),
#'   [dsr_grille_reference()].
#' @export
dsr_layers_pc <- function(dalle, res = DSR_RES_MULTIECHELLE, grille = NULL,
                          emprise = NULL, masque = NULL,
                          sousetage = c(0.3, 3),
                          classe_sol = 2L, classe_couvert = 5L, classe_pont = 17L,
                          classes_exclusion = c(6L, 9L, 64L, 66L),
                          seuil_couvert = 0.95) {
  dsr_verifier_lasR()
  if (inherits(dalle, "sf") || inherits(dalle, "data.frame")) {
    dalle <- as.character(dalle$laz)[1]
  }
  if (!is.character(dalle) || !file.exists(dalle)) {
    dsr_abort("{.arg dalle} doit etre un chemin de fichier LAZ/LAS existant.")
  }

  lecteur <- dsr_lecteur_lasr(emprise)
  op_couvert <- sprintf("z_p%d", as.integer(round(seuil_couvert * 100)))

  # Ordre FIXE des etages -> on recupere les sorties par position.
  etages <- list(
    n_tot   = lasR::rasterize(res, "count", ofile = lasR::temptif()),
    n_sol   = lasR::rasterize(res, "count",
      filter = lasR::keep_class(classe_sol), ofile = lasR::temptif()),
    n_sous  = lasR::rasterize(res, "count",
      filter = lasR::keep_z_between(sousetage[1], sousetage[2]), ofile = lasR::temptif()),
    h_couv  = lasR::rasterize(res, op_couvert,
      filter = lasR::keep_class(classe_couvert), ofile = lasR::temptif()),
    n_excl  = lasR::rasterize(res, "count",
      filter = lasR::keep_class(classes_exclusion), ofile = lasR::temptif()),
    n_pont  = lasR::rasterize(res, "count",
      filter = lasR::keep_class(classe_pont), ofile = lasR::temptif())
  )
  pipeline <- Reduce(`+`, etages, lecteur + lasR::normalize())
  res_exec <- lasR::exec(pipeline, on = dalle)

  # exec renvoie une liste ordonnee ; on la remappe sur les noms d'etages.
  rasters <- res_exec[vapply(res_exec, inherits, logical(1), "SpatRaster")]
  if (length(rasters) < length(etages)) {
    dsr_abort("Sortie {.pkg lasR} inattendue : {length(rasters)} rasters pour {length(etages)} etages.")
  }
  names(rasters) <- names(etages)

  gabarit <- rasters$n_tot
  z0 <- function(r) terra::ifel(is.na(r), 0, r) # comptage manquant -> 0
  valide <- !is.na(gabarit) # cellules couvertes par des points

  densite_sol      <- terra::mask(z0(rasters$n_sol) / (res * res), valide, maskvalue = FALSE)
  taux_penetration <- terra::mask(z0(rasters$n_sol) / gabarit, valide, maskvalue = FALSE)
  densite_sousetage <- terra::mask(z0(rasters$n_sous) / gabarit, valide, maskvalue = FALSE)
  h_couvert        <- rasters$h_couv
  masque_exclusion <- terra::mask(z0(rasters$n_excl) > 0, valide, maskvalue = FALSE)
  masque_pont      <- terra::mask(z0(rasters$n_pont) > 0, valide, maskvalue = FALSE)

  out <- c(densite_sol, taux_penetration, densite_sousetage,
    h_couvert, masque_exclusion, masque_pont)
  names(out) <- c("densite_sol", "taux_penetration", "densite_sousetage",
    "h_couvert", "masque_exclusion", "masque_pont")

  if (!is.null(grille)) {
    out <- dsr_aligner(out, terra::rast(grille), methode = "near")
  }
  if (!is.null(masque)) {
    mv <- if (inherits(masque, "SpatVector")) masque else terra::vect(sf::st_as_sf(masque))
    out <- terra::mask(out, mv)
  }
  out
}


# Construire le lecteur lasR selon l'emprise demandee (dalle entiere ou
# rectangle). Une emprise vectorielle est reduite a son rectangle englobant.
#' @noRd
dsr_lecteur_lasr <- function(emprise) {
  if (is.null(emprise)) {
    return(lasR::reader_las())
  }
  if (inherits(emprise, c("sf", "sfc", "SpatVector"))) {
    bb <- if (inherits(emprise, "SpatVector")) {
      as.vector(terra::ext(emprise))[c(1, 3, 2, 4)]
    } else {
      as.numeric(sf::st_bbox(emprise))
    }
    emprise <- bb # xmin, ymin, xmax, ymax
  }
  if (!is.numeric(emprise) || length(emprise) != 4L) {
    dsr_abort("{.arg emprise} doit etre {.code NULL}, un vecteur c(xmin, ymin, xmax, ymax), ou un objet spatial.")
  }
  lasR::reader_las_rectangles(emprise[1], emprise[2], emprise[3], emprise[4])
}
