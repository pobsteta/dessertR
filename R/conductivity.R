# Conductivite (BRIEF section 3.4). Le point de conception le plus important :
# NE PAS fusionner en un score unique. Deux rasters distincts :
#   - sigma_geo  : probabilite d'une EMPREINTE de route dans le terrain (canal
#                  geomorphologique, memoire longue) -> ce fichier ;
#   - sigma_surf : probabilite que cette empreinte soit encore DEGAGEE (canal
#                  nuage, etat present) -> module layers_pc + state (a venir).
# Le pathfinder tourne sur sigma_geo ; l'etat se lit dans la DIVERGENCE des deux.
#
# Fusion vers sigma_geo : on commence par une combinaison parametrique explicite
# (produit pondere de fonctions d'appartenance, avec sigma_min pour eviter les
# zeros infranchissables). L'interface prevoit des le depart le passage a une
# conductivite apprise (method = "model"), non implementee tant qu'un jeu de
# validation n'existe pas.


#' Fonction d'appartenance floue
#'
#' Transforme un canal continu en un degre d'appartenance dans `[0, 1]` (BRIEF
#' section 3.4). Trois formes : rampe croissante, rampe decroissante, ou cloche
#' (plateau trapezoidal). Quand les bornes ne sont pas fournies, elles sont
#' derivees des quantiles des donnees — pratique pour une premiere conductivite
#' *inspectable* avant calibration, a figer ensuite sur un jeu de validation.
#'
#' @param x Un `SpatRaster` mono-couche, ou un vecteur numerique.
#' @param type `"croissante"`, `"decroissante"` ou `"cloche"`.
#' @param a,b Bornes de la rampe (`a` = debut, `b` = fin). Pour `"cloche"`, `a`
#'   et `b` delimitent le plateau et `marge` sa retombee. `NULL` -> quantiles
#'   (`croissante`/`decroissante` : 0.5 et 0.95 ; `cloche` : 0.25 et 0.75).
#' @param marge Largeur des flancs de la cloche (unites de `x`). `NULL` ->
#'   `(b - a) / 2`.
#' @return Un objet de meme type que `x` (raster ou vecteur), valeurs dans
#'   `[0, 1]`.
#' @seealso [dsr_conductivite()].
#' @examples
#' v <- c(0, 25, 50, 75, 100)
#' dsr_appartenance(v, "croissante", a = 20, b = 80)
#' @export
dsr_appartenance <- function(x, type = c("croissante", "decroissante", "cloche"),
                             a = NULL, b = NULL, marge = NULL) {
  type <- match.arg(type)
  est_raster <- inherits(x, "SpatRaster")
  v <- if (est_raster) terra::values(x, mat = FALSE) else x

  qs <- if (type == "cloche") c(0.25, 0.75) else c(0.5, 0.95)
  if (is.null(a)) a <- stats::quantile(v, qs[1], na.rm = TRUE, names = FALSE)
  if (is.null(b)) b <- stats::quantile(v, qs[2], na.rm = TRUE, names = FALSE)
  if (b <= a) b <- a + .Machine$double.eps

  mu <- switch(type,
    croissante   = (v - a) / (b - a),
    decroissante = (b - v) / (b - a),
    cloche = {
      m <- if (is.null(marge)) (b - a) / 2 else marge
      m <- max(m, .Machine$double.eps)
      pmin((v - (a - m)) / m, (( b + m) - v) / m)
    }
  )
  mu <- pmin(pmax(mu, 0), 1)

  if (est_raster) {
    out <- terra::rast(x)
    terra::values(out) <- mu
    names(out) <- "appartenance"
    out
  } else {
    mu
  }
}


#' Specifications d'appartenance par defaut du canal geomorphologique
#'
#' Jeu de regles *provisoire* reliant les couches de [dsr_layers_dtm()] a leur
#' appartenance a « empreinte de route » : une route est un lineaire en creux
#' (`vesselness` haute), aux bords concaves (`openness_neg` haute) et
#' anormalement lisse (`rugosite` basse). Les bornes sont laissees a `NULL`
#' (derivees des quantiles) tant qu'un jeu de validation ne permet pas de les
#' caler (BRIEF section 4). A adapter librement.
#'
#' @return Une liste nommee par nom de base de canal ; chaque element est une
#'   liste `type` / `a` / `b` / `poids` pour [dsr_conductivite()].
#' @seealso [dsr_conductivite()], [dsr_appartenance()].
#' @export
dsr_specs_geomorpho <- function() {
  list(
    vesselness   = list(type = "croissante", poids = 2),
    openness_neg = list(type = "croissante", poids = 1),
    rugosite     = list(type = "decroissante", poids = 1)
  )
}


#' Conductivite geomorphologique `sigma_geo`
#'
#' Fusionne les couches du canal geomorphologique en une conductivite `sigma_geo`
#' dans `[sigma_min, 1]` — la probabilite qu'un pixel porte l'**empreinte** d'une
#' route (BRIEF section 3.4). La combinaison est une **moyenne geometrique
#' ponderee** des fonctions d'appartenance, plancher a `sigma_min` pour eviter
#' les zeros infranchissables. Les canaux multi-echelles (p. ex. `openness_neg_2`
#' / `_5` / `_10`) sont regroupes par nom de base et moyennes avant ponderation.
#'
#' @details
#' **Ponderation par la confiance.** La ou la densite de points sol s'effondre,
#' l'openness devient du bruit : passer cette couche de confiance (normalisee
#' dans `[0, 1]`, typiquement `densite_sol` mise a l'echelle) via `confiance`
#' tire `sigma_geo` vers l'**incertain** (0.5) plutot que vers une valeur faible
#' trompeuse.
#'
#' @param couches Le `SpatRaster` multi-bandes de [dsr_layers_dtm()] (ou tout
#'   sous-ensemble aligne).
#' @param specs Regles d'appartenance ; defaut [dsr_specs_geomorpho()]. Les
#'   canaux sans regle sont ignores.
#' @param method `"param"` (defaut) pour la combinaison parametrique, ou
#'   `"model"` (conductivite apprise) — reserve, non encore implemente.
#' @param sigma_min Plancher de conductivite. Defaut 0.05.
#' @param confiance `SpatRaster` de confiance dans `[0, 1]`, aligne sur
#'   `couches` ; `NULL` pour ne pas ponderer.
#' @return Un `SpatRaster` mono-couche `sigma_geo`, valeurs dans `[sigma_min, 1]`.
#' @seealso [dsr_layers_dtm()], [dsr_appartenance()], [dsr_specs_geomorpho()].
#' @examples
#' \donttest{
#' mnt <- terra::rast(
#'   nrows = 60, ncols = 60, xmin = 0, xmax = 60, ymin = 0, ymax = 60,
#'   crs = "EPSG:2154"
#' )
#' terra::values(mnt) <- 100 + terra::rowFromCell(mnt, seq_len(terra::ncell(mnt))) * 0.1
#' pile <- dsr_layers_dtm(mnt, res = 1)
#' sg <- dsr_conductivite(pile)
#' }
#' @export
dsr_conductivite <- function(couches, specs = dsr_specs_geomorpho(),
                             method = c("param", "model"),
                             sigma_min = 0.05, confiance = NULL) {
  method <- match.arg(method)
  if (!inherits(couches, "SpatRaster")) {
    dsr_abort("{.arg couches} doit etre un {.cls SpatRaster} (sortie de {.fun dsr_layers_dtm}).")
  }
  if (identical(method, "model")) {
    dsr_abort(c(
      "La conductivite apprise ({.code method = \"model\"}) n'est pas encore implementee.",
      "i" = "Elle attend un jeu de validation (BRIEF section 4) ; utiliser {.code method = \"param\"} d'ici la."
    ))
  }

  bases <- sub("_[0-9.]+$", "", names(couches))
  utilises <- intersect(unique(bases), names(specs))
  if (length(utilises) == 0L) {
    dsr_abort(c(
      "Aucun canal de {.arg couches} ne correspond aux regles {.arg specs}.",
      "i" = "Canaux presents : {.val {unique(bases)}} ; regles : {.val {names(specs)}}."
    ))
  }

  n <- terra::ncell(couches)
  log_acc <- rep(0, n)
  poids_tot <- 0
  for (base in utilises) {
    sp <- specs[[base]]
    idx <- which(bases == base)
    # Moyenne des appartenances sur les echelles d'un meme canal.
    mu <- rep(0, n)
    for (i in idx) {
      mu <- mu + dsr_appartenance(couches[[i]], type = sp$type, a = sp$a, b = sp$b,
        marge = sp$marge)[]
    }
    mu <- mu / length(idx)
    w <- if (is.null(sp$poids)) 1 else sp$poids
    log_acc <- log_acc + w * log(pmax(mu, sigma_min))
    poids_tot <- poids_tot + w
  }
  sigma <- exp(log_acc / poids_tot)
  sigma <- pmax(sigma, sigma_min)

  if (!is.null(confiance)) {
    if (!inherits(confiance, "SpatRaster")) {
      dsr_abort("{.arg confiance} doit etre un {.cls SpatRaster} dans [0, 1].")
    }
    conf <- pmin(pmax(terra::values(confiance, mat = FALSE), 0), 1)
    # Faible confiance -> tirer vers l'incertain (0.5), pas vers faible.
    sigma <- conf * sigma + (1 - conf) * 0.5
  }

  out <- terra::rast(couches[[1]])
  terra::values(out) <- sigma
  names(out) <- "sigma_geo"
  out
}
