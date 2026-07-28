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
# zeros infranchissables). Depuis le lot 8, `method = "model"` accepte une
# conductivite apprise sur un jeu etiquete (voir learn.R) ; la voie parametrique
# reste le defaut, seule utilisable sans jeu de validation.


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
#'   `"model"` pour la conductivite apprise — qui demande alors un `modele`.
#' @param sigma_min Plancher de conductivite. Defaut 0.05.
#' @param confiance `SpatRaster` de confiance dans `[0, 1]`, aligne sur
#'   `couches` ; `NULL` pour ne pas ponderer.
#' @param modele Objet `dsr_modele_conductivite` ([dsr_apprendre_conductivite()])
#'   requis quand `method = "model"` ; ignore sinon.
#' @return Un `SpatRaster` mono-couche `sigma_geo`, valeurs dans `[sigma_min, 1]`.
#' @seealso [dsr_layers_dtm()], [dsr_appartenance()], [dsr_specs_geomorpho()],
#'   [dsr_apprendre_conductivite()].
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
                             sigma_min = 0.05, confiance = NULL,
                             modele = NULL) {
  method <- match.arg(method)
  if (!inherits(couches, "SpatRaster")) {
    dsr_abort("{.arg couches} doit etre un {.cls SpatRaster} (sortie de {.fun dsr_layers_dtm}).")
  }

  sigma <- if (identical(method, "model")) {
    .dsr_conductivite_apprise(couches, modele, sigma_min)
  } else {
    .dsr_fusion_appartenance(couches, specs, sigma_min)
  }

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


# Conductivite apprise : la probabilite predite par le modele tient lieu de
# conductivite, plancher a `sigma_min` comme dans la voie parametrique (un zero
# reste infranchissable pour le pathfinder). Partage par sigma_geo et sigma_surf.
#' @noRd
.dsr_conductivite_apprise <- function(couches, modele, sigma_min) {
  if (is.null(modele) || !inherits(modele, "dsr_modele_conductivite")) {
    dsr_abort(c(
      "La conductivite apprise ({.code method = \"model\"}) demande un {.arg modele}.",
      "i" = "Ajuster d'abord avec {.fun dsr_apprendre_conductivite} sur un echantillon de {.fun dsr_echantillon}.",
      "i" = "A defaut, utiliser {.code method = \"param\"}."
    ))
  }
  p <- terra::values(stats::predict(modele, couches), mat = FALSE)
  pmin(pmax(p, sigma_min), 1)
}


# Moyenne geometrique ponderee des fonctions d'appartenance : le coeur de la
# fusion parametrique, partage par sigma_geo et sigma_surf. Renvoie un vecteur de
# valeurs (ordre des cellules de `couches`), plancher a `sigma_min`. Les canaux
# multi-echelles (suffixe _<rayon>) sont regroupes par nom de base et moyennes.
#' @noRd
.dsr_fusion_appartenance <- function(couches, specs, sigma_min) {
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
  pmax(exp(log_acc / poids_tot), sigma_min)
}


#' Specifications d'appartenance par defaut du canal de surface
#'
#' Regles reliant les couches de [dsr_layers_pc()] a la probabilite qu'une
#' emprise soit **encore degagee** : le discriminant central est
#' `densite_sousetage` (echos 0,3-3 m au-dessus du sol) -- faible = degagee,
#' forte = recolonisee (BRIEF sections 0 et 3.4). `taux_penetration` (ouverture
#' au-dessus de l'emprise) intervient en appui, avec un poids moindre.
#'
#' @return Une liste nommee par canal, chaque element une liste
#'   `type` / `poids` pour [dsr_sigma_surf()].
#' @seealso [dsr_sigma_surf()].
#' @export
dsr_specs_surface <- function() {
  list(
    densite_sousetage = list(type = "decroissante", poids = 2),
    taux_penetration  = list(type = "croissante", poids = 1)
  )
}


#' Conductivite de surface `sigma_surf`
#'
#' Probabilite que l'empreinte d'une route soit **encore degagee et circulable**
#' (canal nuage, etat present), dans `[sigma_min, 1]` (BRIEF section 3.4). Meme
#' machinerie que [dsr_conductivite()] (moyenne geometrique ponderee de fonctions
#' d'appartenance), appliquee aux couches de [dsr_layers_pc()]. Le signal central
#' est `densite_sousetage` : une emprise recolonisee par le sous-etage n'est plus
#' circulable, meme sous un couvert haut intact -- distinction impossible sur le
#' MNH.
#'
#' `sigma_surf` n'a de sens que **la ou une empreinte existe** : c'est sa
#' divergence avec `sigma_geo` qui revele l'etat ([dsr_etat()]), pas sa valeur
#' absolue.
#'
#' @param couches Le `SpatRaster` de [dsr_layers_pc()] (ou un sous-ensemble
#'   aligne).
#' @param specs Regles d'appartenance ; defaut [dsr_specs_surface()].
#' @param method `"param"` (defaut) ou `"model"` (conductivite apprise, qui
#'   demande alors un `modele`).
#' @param sigma_min Plancher de conductivite. Defaut 0.05.
#' @param masque_exclusion `SpatRaster` binaire (1 = zone neutralisee, p. ex.
#'   `masque_exclusion` de [dsr_layers_pc()]) ; les cellules a 1 sont ramenees a
#'   `sigma_min`. `NULL` pour ne pas masquer.
#' @param modele Objet `dsr_modele_conductivite` ([dsr_apprendre_conductivite()])
#'   requis quand `method = "model"` ; ignore sinon.
#' @return Un `SpatRaster` mono-couche `sigma_surf`.
#' @seealso [dsr_conductivite()], [dsr_layers_pc()], [dsr_etat()],
#'   [dsr_apprendre_conductivite()].
#' @export
dsr_sigma_surf <- function(couches, specs = dsr_specs_surface(),
                           method = c("param", "model"),
                           sigma_min = 0.05, masque_exclusion = NULL,
                           modele = NULL) {
  method <- match.arg(method)
  if (!inherits(couches, "SpatRaster")) {
    dsr_abort("{.arg couches} doit etre un {.cls SpatRaster} (sortie de {.fun dsr_layers_pc}).")
  }

  sigma <- if (identical(method, "model")) {
    .dsr_conductivite_apprise(couches, modele, sigma_min)
  } else {
    .dsr_fusion_appartenance(couches, specs, sigma_min)
  }

  if (!is.null(masque_exclusion)) {
    if (!inherits(masque_exclusion, "SpatRaster")) {
      dsr_abort("{.arg masque_exclusion} doit etre un {.cls SpatRaster} binaire.")
    }
    excl <- terra::values(masque_exclusion, mat = FALSE)
    sigma[!is.na(excl) & excl > 0] <- sigma_min
  }

  out <- terra::rast(couches[[1]])
  terra::values(out) <- sigma
  names(out) <- "sigma_surf"
  out
}
