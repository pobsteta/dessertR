# Systeme de coordonnees par defaut du Lidar HD metropolitain (RGF93 / Lambert-93)
#' @noRd
DSR_CRS_DEFAUT <- 2154L

# Taille de dalle du programme Lidar HD, en metres
#' @noRd
DSR_TAILLE_DALLE <- 1000

# Resolution de reference des canaux morphometriques multi-echelles, en metres.
# Le MNT Lidar HD a 50 cm est trop fin pour l'openness et le SVF : rececheantillonner
# a 1 m divise le cout du balayage directionnel par ~4 et reduit le bruit
# d'interpolation sous couvert (voir BRIEF section 3.2). Le 50 cm reste reserve a la
# mesure de largeur et a la detection de fosses (measure.R).
#' @noRd
DSR_RES_MULTIECHELLE <- 1

# On propage `.envir` pour que les expressions glue `{var}` des messages soient
# evaluees dans la fonction appelante, ou vivent les variables interpolees, et
# non dans ce wrapper (sinon : "object '<var>' not found").
#' @noRd
dsr_abort <- function(..., .envir = parent.frame()) cli::cli_abort(c(...), .envir = .envir)

#' @noRd
dsr_inform <- function(..., .envir = parent.frame()) cli::cli_inform(c(...), .envir = .envir)

#' @noRd
dsr_verifier_lasR <- function() {
  if (!requireNamespace("lasR", quietly = TRUE)) {
    dsr_abort(c(
      "Le paquet {.pkg lasR} est requis pour cette fonction.",
      "i" = 'Installation : install.packages("lasR", repos = "https://r-lidar.r-universe.dev")'
    ))
  }
  invisible(TRUE)
}


#' Nombre de coeurs alloues aux traitements lasR
#'
#' Politique du paquet : **tous les coeurs sauf un**, au minimum 1. Le defaut de
#' `lasR` est la moitie des coeurs ([lasR::half_cores()]), trop conservateur
#' pour un traitement de bloc ; en garder un seul de libre laisse la machine
#' utilisable et evite d'affamer les threads GDAL/terra qui tournent entre deux
#' etages du pipeline.
#'
#' @details
#' La base de calcul est [lasR::ncores()] -- le nombre de threads que `lasR`
#' peut reellement utiliser (1 si la version installee est sans OpenMP) -- et
#' non `parallel::detectCores()`, qui annoncerait des coeurs inexploitables.
#'
#' Deux garde-fous : l'option `dessertR.ncores` impose une valeur fixe, et le
#' resultat est plafonne a 2 sous `R CMD check` (`_R_CHECK_LIMIT_CORES_`).
#' Enfin, une strategie posee globalement par [lasR::set_parallel_strategy()]
#' reste prioritaire sur ce reglage : c'est `lasR` qui arbitre.
#'
#' @param reserve Nombre de coeurs laisses libres. Defaut 1.
#' @return Un entier >= 1.
#' @seealso [lasR::set_parallel_strategy()], [lasR::ncores()].
#' @examples
#' dsr_ncores()
#' @export
dsr_ncores <- function(reserve = 1L) {
  n <- getOption("dessertR.ncores")
  if (is.null(n)) {
    dispo <- if (requireNamespace("lasR", quietly = TRUE)) lasR::ncores() else 1L
    n <- as.integer(dispo) - as.integer(reserve)
  }
  n <- max(1L, as.integer(n))
  if (nzchar(Sys.getenv("_R_CHECK_LIMIT_CORES_"))) n <- min(n, 2L)
  n
}


# Strategie de parallelisation passee a `lasR::exec(ncores = )`. Une seule dalle
# -> paralleliser les POINTS (un seul fichier a lire, rien a repartir) ;
# plusieurs dalles -> paralleliser les FICHIERS, ou le gain est franc.
#' @noRd
dsr_strategie_lasr <- function(n_dalles = 1L) {
  n <- dsr_ncores()
  if (n_dalles > 1L) lasR::concurrent_files(n) else lasR::concurrent_points(n)
}


# Validation commune des entrees « dalle » des fonctions adossees a lasR.
#
# Accepte UN OU PLUSIEURS chemins. L'ancienne garde testait
# `!file.exists(dalle)` dans un `if`, ce qui erre des que le vecteur depasse un
# element (« 'length = 4' in coercion to 'logical(1)' » sous R >= 4.2) -- et la
# variante catalogue ne gardait que la premiere ligne, silencieusement. La
# consequence n'etait pas seulement une limitation : la strategie
# `concurrent_files` de dsr_strategie_lasr() ne pouvait jamais se declencher,
# puisque `length(dalle)` valait toujours 1.
#' @noRd
dsr_valider_dalles <- function(dalle, nom = "dalle") {
  if (!is.character(dalle) || !length(dalle)) {
    dsr_abort("{.arg {nom}} doit etre un ou plusieurs chemins de fichiers LAZ/LAS.")
  }
  manquants <- dalle[!file.exists(dalle)]
  if (length(manquants)) {
    dsr_abort(c(
      "{.arg {nom}} : {length(manquants)} fichier{?s} introuvable{?s}.",
      "x" = "{.file {utils::head(manquants, 3)}}"
    ))
  }
  dalle
}
