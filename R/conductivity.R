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
#' (`vesselness` haute), aux bords concaves (`openness_neg` haute) et **plus
#' rugueuse que son environnement** (`rugosite` haute). Les bornes sont laissees
#' a `NULL` (derivees des quantiles) tant qu'un jeu de validation ne permet pas
#' de les caler (BRIEF section 4). A adapter librement.
#'
#' @details
#' **`rugosite` est croissante, ce qui surprend.** L'intuition dit qu'une route
#' est lisse. A 50 cm de resolution, c'est faux : une piste empierree a
#' ornieres est plus rugueuse qu'un versant forestier localement plan, et le
#' profil en travers -- fosse, talus, devers -- domine dans une fenetre de
#' quelques cellules. Le canal etait declare `decroissante` jusqu'ici, donc
#' utilise a l'envers.
#'
#' Mesure a l'appui ([dsr_calibrer_specs()], fenetres de 1,5 km2) : `rugosite`
#' est le canal le plus discriminant des sept, `sens = +1` sur les deux massifs
#' (AUC 0,759 et 0,744 ; 0,753 en conjoint), et l'AUC de `sigma_geo` gagne
#' **+0,175 sur chacun** -- 0,530 -> 0,705 sur wsfi, 0,479 -> 0,654 sur ltcp. Le
#' defaut precedent passait donc **sous le hasard** sur un des deux massifs.
#'
#' Les autres signes sont inchangees. `pente` et `slrm` s'inversent d'un massif
#' a l'autre (`stable = FALSE`) et n'ont rien a faire dans un defaut ;
#' `openness_neg` mesure `-1` sur les deux massifs mais `+1` sur une dalle
#' Lozere recouvrant wsfi, avec une AUC proche du hasard (0,527) la ou le signe
#' se decide -- pas de quoi trancher.
#'
#' Ces regles restent un **point de depart**. Le chemin recommande est
#' [dsr_calibrer_specs()], qui mesure les signes, les poids et les bornes sur
#' vos donnees plutot que de les supposer.
#'
#' @return Une liste nommee par nom de base de canal ; chaque element est une
#'   liste `type` / `a` / `b` / `poids` pour [dsr_conductivite()].
#' @seealso [dsr_conductivite()], [dsr_appartenance()].
#' @export
dsr_specs_geomorpho <- function() {
  list(
    vesselness   = list(type = "croissante", poids = 2),
    openness_neg = list(type = "croissante", poids = 1),
    # Croissante, et non decroissante : voir les details. Mesure sur deux
    # massifs, une route forestiere est PLUS rugueuse que son environnement.
    rugosite     = list(type = "croissante", poids = 1)
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
  satures <- list()
  for (base in utilises) {
    sp <- specs[[base]]
    idx <- which(bases == base)
    mu <- rep(0, n)
    for (i in idx) {
      mu <- mu + dsr_appartenance(couches[[i]], type = sp$type, a = sp$a, b = sp$b,
        marge = sp$marge)[]
    }
    mu <- mu / length(idx)
    # Bornes EXPLICITES mal adaptees a la donnee : le canal sature d'un seul
    # cote et cesse de discriminer. Voir .dsr_alerter_bornes.
    if (!is.null(sp$a) || !is.null(sp$b)) {
      f <- mu[is.finite(mu)]
      if (length(f)) {
        s <- max(mean(f <= 0), mean(f >= 1))
        if (s >= SEUIL_SATURATION) satures[[base]] <- s
      }
    }
    w <- if (is.null(sp$poids)) 1 else sp$poids
    log_acc <- log_acc + w * log(pmax(mu, sigma_min))
    poids_tot <- poids_tot + w
  }
  .dsr_alerter_bornes(satures)
  pmax(exp(log_acc / poids_tot), sigma_min)
}


# Part d'un canal saturee a une extremite au-dela de laquelle la regle ne
# discrimine plus rien. Mesure : des bornes calibrees sur le MEME massif saturent
# au plus 50 % (par construction, `a` etant la mediane de l'absence) et de facon
# equilibree ; des bornes venues d'un autre massif saturent 85 a 99 % du meme
# cote. 0,8 separe les deux sans faux positif sur les jeux de validation.
SEUIL_SATURATION <- 0.8


# Alerte quand des bornes EXPLICITES ne correspondent pas a la donnee.
#
# Le cas type : des specs calibrees sur un massif appliquees a un autre. Les
# bornes sont dans l'unite du canal et ne se transportent pas -- des bornes de
# plaine appliquees a une montagne poussent tout au plafond. Mesure sur les deux
# massifs de validation, dans les DEUX sens : le contraste route / hors-route
# tombe a +0,010 et +0,018, contre +0,176 et +0,112 avec des bornes propres.
#
# L'AUC ne voit rien de tout cela : elle est invariante d'echelle. C'est
# precisement pourquoi ce garde-fou existe -- le defaut est invisible a la
# metrique qui sert habituellement a juger, et ne se manifeste qu'en aval, sur
# un agent qui divague parce que les couts ne sont plus a la bonne echelle.
#' @noRd
.dsr_alerter_bornes <- function(satures) {
  if (!length(satures)) return(invisible(NULL))
  if (!isTRUE(getOption("dessertR.verifier_bornes", TRUE))) return(invisible(NULL))
  pc <- sprintf("%s (%.0f %%)", names(satures), 100 * unlist(satures))
  dsr_inform(c(
    "!" = "Bornes mal adaptees a la donnee : {.val {pc}} sature{?nt} a une extremite.",
    "i" = "Des bornes calibrees sur un AUTRE massif ne se transportent pas : elles sont dans l'unite du canal.",
    "i" = "Recalibrer avec {.fun dsr_calibrer_specs} sur ces donnees, ou utiliser {.code bornes = FALSE}.",
    "i" = "Silence : {.code options(dessertR.verifier_bornes = FALSE)}."
  ))
  invisible(NULL)
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


# --- Calibrage des regles d'appartenance sur donnee reelle -------------------

# AUC de Mann-Whitney d'un canal, ORIENTEE. Un canal qui marque les routes par
# le bas (creux, NDVI faible) est aussi informatif qu'un canal qui les marque
# par le haut : on rend l'ecart au hasard et le sens separement.
#' @noRd
.dsr_auc_canal <- function(r, u, pres, absent, n) {
  dedans <- terra::values(terra::mask(r, terra::vect(sf::st_buffer(u, pres))))
  dehors <- terra::values(terra::mask(r, terra::vect(sf::st_buffer(u, absent)),
    inverse = TRUE))
  dedans <- dedans[is.finite(dedans)]
  dehors <- dehors[is.finite(dehors)]
  if (length(dedans) < 50L || length(dehors) < 50L) {
    return(c(auc = NA, sens = NA, q25_pres = NA, q75_pres = NA, q50_abs = NA))
  }
  a <- sample(dedans, min(n, length(dedans)))
  b <- sample(dehors, min(n, length(dehors)))
  auc <- mean(outer(a, b, ">")) + 0.5 * mean(outer(a, b, "=="))
  # Les quantiles des deux populations sortent de la MEME boucle que l'AUC :
  # ils sont deja a portee, et ils fournissent les bornes d'appartenance
  # absolues (voir .dsr_bornes_specs).
  q <- stats::quantile(dedans, c(0.25, 0.75), na.rm = TRUE, names = FALSE)
  c(auc = max(auc, 1 - auc), sens = if (auc >= 0.5) 1 else -1,
    q25_pres = q[1], q75_pres = q[2],
    q50_abs = stats::median(dehors, na.rm = TRUE))
}


# Bornes d'appartenance ABSOLUES a partir des deux populations mesurees.
#
# La rampe va du typique de l'ENVIRONNEMENT (mu = 0) au franchement ROUTIER
# (mu = 1), en prenant le quantile de la population correspondante :
#   croissante   a = q50(absence)  -> b = q75(presence)
#   decroissante a = q25(presence) -> b = q50(absence)
# Rappel de dsr_appartenance() : `decroissante` vaut (b - v)/(b - a), donc `a`
# y est le cote ROUTE et `b` le cote environnement -- l'ordre n'est pas le meme
# que pour `croissante`, et l'inverser retournerait la regle.
#' @noRd
.dsr_bornes_specs <- function(sens, q25_pres, q75_pres, q50_abs) {
  ab <- if (sens > 0) c(q50_abs, q75_pres) else c(q25_pres, q50_abs)
  # Une rampe degeneree (bornes confondues ou inversees) ne decrit rien : mieux
  # vaut rendre NULL et laisser dsr_appartenance() retomber sur ses quantiles
  # que fabriquer une regle qui classe tout du meme cote.
  if (!all(is.finite(ab)) || ab[2] <= ab[1]) return(NULL)
  ab
}


# Descripteurs de terrain d'une pile, pour rattacher les signes mesures au type
# de relief.
#
# POURQUOI CETTE TABLE EXISTE. Certains canaux discriminent bien sur chaque
# massif mais dans des sens OPPOSES : sur les deux massifs de validation,
# `pente` marque les routes par le bas en montagne (une route suit le moindre
# pendage) et par le haut en plaine (plateforme bombee, fosses), avec la meme
# AUC de 0,61 des deux cotes. Le test `stable` les ecarte -- prudence justifiee
# tant qu'on ne sait pas a quoi rattacher l'inversion, mais qui perd de
# l'information reelle.
#
# L'hypothese est que ces signes sont stables A L'INTERIEUR d'une classe de
# relief. On ne peut pas la trancher avec deux massifs : il en faudrait au moins
# deux par classe, sans quoi on calibrerait une classification sur n = 1. On
# INSTRUMENTE donc, sans stratifier : chaque calibration rend son terrain a cote
# de ses signes, et la question devient decidable quand les massifs
# s'accumuleront, au lieu d'etre tranchee par intuition.
#
# Les descripteurs sont pris dans la pile fournie -- aucun calcul
# supplementaire -- et il y en a plusieurs a dessein : rien ne dit d'avance si
# c'est la pente, la rugosite ou l'amplitude du relief local qui predit les
# inversions.
#' @noRd
.dsr_descripteurs_terrain <- function(pile) {
  bases <- sub("_[0-9.]+$", "", names(pile))
  resume <- function(base, f) {
    i <- which(bases == base)
    if (!length(i)) return(NA_real_)
    v <- terra::values(pile[[i[1]]], mat = FALSE)
    v <- v[is.finite(v)]
    if (!length(v)) NA_real_ else unname(f(v))
  }
  data.frame(
    pente_med    = resume("pente", stats::median),
    pente_p90    = resume("pente", function(v) stats::quantile(v, 0.9)),
    rugosite_med = resume("rugosite", stats::median),
    relief_iqr   = resume("slrm", stats::IQR)
  )
}


# Canaux d'une pile regroupes par BASE, chaque base moyennee sur ses echelles.
# C'est exactement ce que fait .dsr_fusion_appartenance() : mesurer autrement
# calibrerait autre chose que ce qui sera utilise.
#' @noRd
.dsr_bases_canaux <- function(couches, exclure = "theta") {
  bases <- sub("_[0-9.]+$", "", names(couches))
  setdiff(unique(bases), exclure)
}


#' Calibrer les regles de conductivite sur un reseau de reference
#'
#' Mesure, canal par canal, ce qui distingue reellement une route de son
#' environnement sur **vos** donnees, et en deduit un jeu de regles utilisable
#' tel quel par [dsr_conductivite()].
#'
#' @details
#' **Pourquoi cette fonction existe.** Les regles par defaut
#' ([dsr_specs_geomorpho()]) reposent sur une intuition physique : une route est
#' lisse, elle occupe un creux, elle est lineaire. Mesuree sur deux massifs
#' Lidar HD, l'intuition sur la rugosite est **fausse et inversee** -- une piste
#' empierree a ornieres est plus rugueuse, a 50 cm, qu'un versant forestier
#' localement plan. Le canal le plus discriminant des deux jeux (AUC 0,78 et
#' 0,68) etait donc utilise a l'envers, et la conductivite qui en resultait
#' tombait au niveau du hasard (0,51 et 0,54). Signes corriges, elle remonte a
#' 0,77 et 0,72.
#'
#' **Ce que la fonction mesure.** Pour chaque canal, l'aire sous la courbe ROC
#' entre les cellules proches du reseau de reference (`pres`) et celles qui en
#' sont eloignees (`absent`). L'AUC est rendue **orientee** : 0,5 signifie
#' aucun pouvoir discriminant, et `sens` dit si le canal marque la route par le
#' haut ou par le bas. Les canaux multi-echelles sont regroupes par base et
#' moyennes, comme le fait [dsr_conductivite()] -- mesurer autrement
#' calibrerait autre chose que ce qui sera utilise.
#'
#' **Plusieurs massifs valent mieux qu'un, et pas seulement pour la precision.**
#' En passant une liste, un canal n'est retenu que si son sens est **le meme
#' partout**. Ce n'est pas un raffinement : sur les deux massifs de validation,
#' la `pente` marque les routes par le bas dans l'un et par le haut dans
#' l'autre. Calibree sur un seul, elle entrait dans les regles ; calibree sur
#' les deux, elle en est ecartee. Un canal dont le signe depend du relief n'a
#' rien a faire dans une regle.
#'
#' **Bornes absolues, et pourquoi elles comptent.** La fonction rend aussi les
#' bornes `a` et `b` de chaque rampe, en unites du canal (`bornes = TRUE`).
#' Ce n'est pas un agrement : sans elles, [dsr_appartenance()] derive ses bornes
#' des quantiles de la donnee qu'on lui passe, et **la sortie depend alors de
#' l'etendue analysee**. Mesure sur le bloc wsfi, une fenetre de 0,25 km2 rend
#' 116 m de desserte detectee analysee seule, et **0 m** analysee au sein de
#' 4 km2 : le `seuil` de [dsr_detecter()] n'est pas une quantite absolue mais un
#' rang dans la population fournie. Deux sites d'etendues differentes ne sont
#' pas comparables, et le regime `corridor` change le bareme.
#'
#' La convention est de faire aller la rampe du typique de l'ENVIRONNEMENT
#' (`mu = 0`) au franchement ROUTIER (`mu = 1`) :
#'
#' | sens | `a` | `b` |
#' | --- | --- | --- |
#' | `croissante` | q50(absence) | q75(presence) |
#' | `decroissante` | q25(presence) | q50(absence) |
#'
#' Une borne, contrairement au sens et a l'AUC, est dans l'unite du canal et ne
#' se transporte pas forcement d'un massif a l'autre -- le taux de penetration
#' brut varie d'un facteur 7 entre les deux massifs de validation. Avec
#' plusieurs massifs les bornes sont donc medianes, et **calibrer sur les
#' massifs qu'on va effectivement traiter reste la bonne pratique**.
#'
#' Cette correction ne suffit pas a elle seule a rendre une pile independante de
#' l'emprise : `vesselness` est rescalee **en amont** des fonctions
#' d'appartenance et demande son propre ancrage ([dsr_c_vessel()]).
#'
#' **Terrain : instrumenter avant de stratifier.** Certains canaux discriminent
#' bien sur chaque massif mais dans des sens **opposes**. Sur les deux massifs
#' de validation, `pente` marque les routes par le bas en montagne (une route
#' suit le moindre pendage) et par le haut en plaine (plateforme bombee,
#' fosses), avec la meme AUC de 0,61 des deux cotes ; `slrm` fait de meme. Le
#' test `stable` les ecarte -- prudence justifiee tant qu'on ne sait pas a quoi
#' rattacher l'inversion, mais qui perd de l'information reelle.
#'
#' L'hypothese naturelle est que ces signes sont stables **a l'interieur d'une
#' classe de relief**. Elle n'est pas tranchable avec deux massifs : il en
#' faudrait au moins deux par classe, sans quoi on calibrerait une
#' classification sur un seul echantillon -- exactement l'erreur que cette
#' fonction existe pour eviter.
#'
#' D'ou `terrain` et `par_massif`, qui **instrumentent sans stratifier** :
#' chaque calibration rend son relief a cote de ses signes, et la question
#' devient decidable quand les massifs s'accumuleront. Les descripteurs sont
#' plusieurs a dessein -- rien ne dit d'avance si c'est la pente, la rugosite ou
#' l'amplitude du relief local qui predit les inversions, et c'est aux donnees
#' de le dire.
#'
#' **Une regularite a falsifier.** Sur les deux massifs disponibles, les canaux
#' qui s'inversent sont exactement ceux qui situent la route dans la forme
#' GENERALE du paysage, et ceux qui restent stables decrivent la route
#' ELLE-MEME :
#'
#' | canal | plaine (pente med. 2,2 deg) | montagne (22,3 deg) |
#' | --- | --- | --- |
#' | `pente` | +1 | **-1** |
#' | `slrm` | +1 | **-1** |
#' | `rugosite` (texture) | +1 | +1 |
#' | `openness_neg` / `openness_pos` / `svf` (forme du voisinage) | -1 | -1 |
#' | `vesselness` (linearite) | +1 | +1 |
#'
#' L'explication tiendrait en une phrase : en montagne une route suit le moindre
#' pendage, elle est donc **moins** pentue que son environnement ; en plaine il
#' n'y a pas de pendage a suivre, et ce qui la marque est sa forme construite --
#' bombement, fosses -- donc **plus** pentue qu'un terrain plat. Les autres
#' canaux decrivent la route et non sa place dans le paysage, ce qui expliquerait
#' leur stabilite.
#'
#' Ce n'est **pas une loi** : deux massifs ne l'etablissent pas. C'est une
#' prediction, et elle est falsifiable -- un troisieme massif dont `pente`
#' s'inverserait sans changement de classe de relief la refuterait. Elle vaut
#' surtout parce qu'elle reduit le probleme : si elle tient, seuls `pente` et
#' `slrm` demandent un conditionnement au terrain.
#'
#' **Ce que la reference peut et ne peut pas etre.** Sa POSITION doit faire
#' autorite -- la BD TOPO convient, sa precision planimetrique etant metrique.
#' Sa largeur, non : elle n'entre pas dans le calcul. Un reseau approximatif
#' (trace GPS, numerisation sur fond satellite) deplacerait les echantillons
#' « presence » hors de l'emprise reelle et calibrerait du bruit.
#'
#' @param couches Un `SpatRaster` multi-bandes ([dsr_layers_dtm()]), ou une
#'   **liste** de piles -- une par massif.
#' @param reference Reseau de reference (`sf`/`sfc` de lignes), ou une liste de
#'   meme longueur que `couches`.
#' @param pres Distance (m) en deca de laquelle une cellule compte comme
#'   « sur route ». Defaut 3.
#' @param absent Distance (m) au-dela de laquelle une cellule compte comme
#'   « hors route ». Defaut 20. La bande intermediaire est ignoree : c'est le
#'   bord de plateforme, ni route ni environnement.
#' @param auc_min AUC minimale pour qu'un canal entre dans les regles. Defaut
#'   0.55. En dessous, le canal n'apporte pas de quoi payer le bruit qu'il
#'   ajoute.
#' @param poids_max Poids attribue au canal le plus discriminant ; les autres
#'   sont proportionnels a leur ecart au hasard. Defaut 3.
#' @param n Taille des echantillons compares. Defaut 2500.
#' @param exclure Canaux ignores. Defaut `"theta"`, qui est une orientation et
#'   non une intensite.
#' @param bornes Produire aussi les bornes d'appartenance `a` et `b`, en unites
#'   du canal. Defaut `TRUE`. Voir « Bornes absolues » ci-dessous ; `FALSE`
#'   rend des regles sans bornes, donc **relatives a l'emprise**.
#'
#' @return Une liste de quatre elements :
#'   * `specs`, directement utilisable comme argument `specs` de
#'     [dsr_conductivite()] ;
#'   * `diagnostic`, un `data.frame` (`canal`, `auc`, `sens`, `stable`,
#'     `retenu`, `poids`, `a`, `b`) trie par pouvoir discriminant decroissant.
#'     Avec plusieurs massifs, `auc` est la mediane et `stable` indique si le
#'     sens concorde partout ;
#'   * `par_massif`, la mesure brute avant agregation (`canal`, `massif`, `auc`,
#'     `sens`) -- c'est la qu'on lit *comment* un canal s'inverse, la ou
#'     `diagnostic` se contente de dire qu'il le fait ;
#'   * `terrain`, les descripteurs de relief de chaque massif (`pente_med`,
#'     `pente_p90`, `rugosite_med`, `relief_iqr`). Voir « Terrain » ci-dessous.
#' @seealso [dsr_conductivite()], [dsr_specs_geomorpho()], [dsr_layers_dtm()].
#' @examples
#' \donttest{
#' mnt <- terra::rast(nrows = 60, ncols = 60, xmin = 0, xmax = 60, ymin = 0,
#'   ymax = 60, crs = "EPSG:2154")
#' terra::values(mnt) <- runif(3600)
#' couches <- dsr_layers_dtm(mnt, res = 1)
#' axe <- sf::st_sfc(sf::st_linestring(cbind(c(5, 55), c(30, 30))), crs = 2154)
#' cal <- dsr_calibrer_specs(couches, axe)
#' cal$diagnostic
#' }
#' @export
dsr_calibrer_specs <- function(couches, reference, pres = 3, absent = 20,
                               auc_min = 0.55, poids_max = 3, n = 2500,
                               exclure = "theta", bornes = TRUE) {
  if (inherits(couches, "SpatRaster")) couches <- list(couches)
  if (inherits(reference, c("sf", "sfc"))) reference <- list(reference)
  if (length(couches) != length(reference)) {
    dsr_abort("{.arg couches} et {.arg reference} doivent avoir la meme longueur.")
  }
  if (pres >= absent) {
    dsr_abort("{.arg pres} ({pres}) doit etre inferieur a {.arg absent} ({absent}).")
  }

  mesures <- list()
  terrains <- list()
  for (k in seq_along(couches)) {
    pile <- couches[[k]]
    if (!inherits(pile, "SpatRaster")) {
      dsr_abort("{.arg couches} doit contenir des {.cls SpatRaster}.")
    }
    terrains[[k]] <- cbind(massif = k, .dsr_descripteurs_terrain(pile))
    u <- sf::st_union(sf::st_geometry(reference[[k]]))
    bases <- sub("_[0-9.]+$", "", names(pile))
    for (base in .dsr_bases_canaux(pile, exclure)) {
      idx <- which(bases == base)
      # Moyenne des echelles avant mesure : c'est la grandeur que la fusion
      # utilisera reellement.
      r <- if (length(idx) == 1L) pile[[idx]] else terra::app(pile[[idx]], "mean")
      a <- .dsr_auc_canal(r, u, pres, absent, n)
      if (is.na(a["auc"])) next
      mesures[[length(mesures) + 1L]] <- data.frame(
        canal = base, massif = k, auc = unname(a["auc"]), sens = unname(a["sens"]),
        q25_pres = unname(a["q25_pres"]), q75_pres = unname(a["q75_pres"]),
        q50_abs = unname(a["q50_abs"]))
    }
  }
  if (!length(mesures)) dsr_abort("Aucun canal mesurable : verifier {.arg reference}.")
  m <- do.call(rbind, mesures)

  # Avec plusieurs massifs, les bornes sont MEDIANES sur les massifs. C'est un
  # compromis assume : contrairement au sens et a l'AUC, une borne est dans
  # l'unite du canal et ne se transporte pas forcement (le taux de penetration
  # brut varie d'un facteur 7 entre deux massifs mesures). Calibrer sur les
  # massifs qu'on va effectivement traiter reste la bonne pratique.
  agg <- lapply(split(m, m$canal), function(d) data.frame(
    canal = d$canal[1],
    auc = stats::median(d$auc),
    sens = if (length(unique(d$sens)) == 1L) d$sens[1] else NA_real_,
    stable = length(unique(d$sens)) == 1L,
    q25_pres = stats::median(d$q25_pres),
    q75_pres = stats::median(d$q75_pres),
    q50_abs = stats::median(d$q50_abs)))
  agg <- do.call(rbind, agg)
  agg <- agg[order(-agg$auc), , drop = FALSE]

  agg$retenu <- agg$stable & agg$auc >= auc_min
  ecart <- pmax(agg$auc - 0.5, 0)
  ref <- max(ecart[agg$retenu], 0)
  agg$poids <- ifelse(agg$retenu & ref > 0,
    pmax(1, round(poids_max * ecart / ref)), 0)

  agg$a <- NA_real_
  agg$b <- NA_real_
  specs <- list()
  for (i in which(agg$retenu)) {
    sp <- list(type = if (agg$sens[i] > 0) "croissante" else "decroissante",
      poids = agg$poids[i])
    if (bornes) {
      ab <- .dsr_bornes_specs(agg$sens[i], agg$q25_pres[i], agg$q75_pres[i],
        agg$q50_abs[i])
      if (!is.null(ab)) {
        sp$a <- ab[1]; sp$b <- ab[2]
        agg$a[i] <- ab[1]; agg$b[i] <- ab[2]
      }
    }
    specs[[agg$canal[i]]] <- sp
  }
  if (bornes && length(specs) && !any(is.finite(agg$a))) {
    dsr_inform(c(
      "!" = "Aucune borne absolue n'a pu etre derivee : les rampes seraient degenerees.",
      "i" = "Les regles restent relatives a l'emprise ; verifier {.arg reference} et {.arg pres}/{.arg absent}."
    ))
  }
  if (!length(specs)) {
    dsr_inform(c(
      "!" = "Aucun canal n'atteint {.arg auc_min} = {auc_min}{if (length(couches) > 1) ' avec un sens stable' else ''}.",
      "i" = "Le diagnostic reste exploitable ; abaisser le seuil ou verifier {.arg reference}."
    ))
  }
  rownames(agg) <- NULL
  agg <- agg[, setdiff(names(agg), c("q25_pres", "q75_pres", "q50_abs")),
    drop = FALSE]
  par_massif <- m[, c("canal", "massif", "auc", "sens")]
  rownames(par_massif) <- NULL
  terrain <- do.call(rbind, terrains)
  rownames(terrain) <- NULL
  list(specs = specs, diagnostic = agg, par_massif = par_massif,
    terrain = terrain)
}
