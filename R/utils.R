# Systeme de coordonnees par defaut du Lidar HD metropolitain (RGF93 / Lambert-93)
#' @noRd
DSR_CRS_DEFAUT <- 2154L

# Taille de dalle du programme Lidar HD, en metres
#' @noRd
DSR_TAILLE_DALLE <- 1000

#' @noRd
dsr_abort <- function(...) cli::cli_abort(c(...))

#' @noRd
dsr_inform <- function(...) cli::cli_inform(c(...))

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
