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
