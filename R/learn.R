# Conductivite apprise (BRIEF sections 3.4 et 5, lot 8). L'interface
# `method = c("param", "model")` etait prevue des le lot 1 ; ce module la remplit.
#
# Sur le choix du modele. Le BRIEF evoquait « un petit U-Net sur la pile de
# rasters ». On ne le suit pas, et c'est delibere : un U-Net demande torch, un
# GPU, et surtout un corpus annote que le projet n'a pas -- un seul massif de
# validation. Avec quelques milliers de cellules etiquetees et une dizaine de
# canaux deja informatifs (ce sont des descripteurs concus pour la tache, pas des
# pixels bruts), une regression logistique regularisee par la validation croisee
# fait aussi bien, s'inspecte coefficient par coefficient, et ne demande aucune
# dependance. La foret aleatoire (`ranger`, en Suggests) capte les interactions
# quand le jeu grossit. Le passage a un modele convolutif se fera derriere la
# meme interface, quand le jeu de validation le justifiera (BRIEF section 4).
#
# Le garde-fou qui compte : l'AUC est calculee en validation croisee stratifiee,
# jamais en resubstitution. Un modele appris sur un massif et applique a un autre
# reste a valider massif par massif.


#' Echantillon d'apprentissage de la conductivite
#'
#' Construit la table d'apprentissage d'une conductivite apprise : une ligne par
#' cellule retenue, la valeur de chaque canal en colonnes, et l'etiquette `y`
#' (1 = route, 0 = hors route). Les positifs sont les cellules sous le reseau de
#' reference, les negatifs celles suffisamment eloignees de tout lineaire connu.
#'
#' @details
#' **La bande grise est ecartee.** Entre `buffer_pos` et `buffer_neg` autour du
#' reseau, aucune cellule n'est prelevee : ce sont les accotements, les fosses et
#' l'imprecision planimetrique residuelle de la reference. Les y verser
#' brouillerait les deux classes et le modele apprendrait le flou de la BD TOPO
#' plutot que la route.
#'
#' Le tirage est aleatoire : appeler [set.seed()] en amont pour un echantillon
#' reproductible.
#'
#' @param couches `SpatRaster` multi-bandes des canaux explicatifs — la pile de
#'   [dsr_layers_dtm()], celle de [dsr_layers_pc()], ou leur concatenation.
#' @param positifs `sf`/`sfc` du reseau connu comme reellement present (BD TOPO
#'   verifiee, releves GNSS, desserte du gestionnaire).
#' @param negatifs `sf`/`sfc` des zones connues sans desserte ; `NULL` (defaut)
#'   pour prendre tout ce qui est au-dela de `buffer_neg` des `positifs`.
#' @param buffer_pos Demi-largeur (m) du tampon des positifs. Defaut 3.
#' @param buffer_neg Distance (m) au-dela de laquelle une cellule est tenue pour
#'   negative. Defaut 25. Ignore si `negatifs` est fourni.
#' @param emprise `sf`/`sfc` polygonal restreignant la zone de prelevement ;
#'   `NULL` pour toute la grille.
#' @param n_max Nombre maximal de cellules prelevees. Defaut 20000.
#' @param equilibre `TRUE` (defaut) pour tirer autant de positifs que de
#'   negatifs ; `FALSE` pour conserver la prevalence reelle.
#'
#' @return Un `data.frame` : colonne `y` (0/1) puis une colonne par canal.
#'   L'attribut `"cellules"` porte les numeros de cellule preleves.
#' @seealso [dsr_apprendre_conductivite()], [dsr_conductivite()].
#' @export
dsr_echantillon <- function(couches, positifs, negatifs = NULL, buffer_pos = 3,
                            buffer_neg = 25, emprise = NULL, n_max = 20000,
                            equilibre = TRUE) {
  if (!inherits(couches, "SpatRaster")) {
    dsr_abort("{.arg couches} doit etre un {.cls SpatRaster} multi-bandes.")
  }
  if (missing(positifs) || is.null(positifs)) {
    dsr_abort("{.arg positifs} est requis : le reseau connu comme present.")
  }
  if (is.null(negatifs) && buffer_neg <= buffer_pos) {
    dsr_abort("{.arg buffer_neg} doit exceder {.arg buffer_pos} (bande grise a ecarter).")
  }

  grille <- couches[[1]]
  geo_pos <- sf::st_union(sf::st_geometry(positifs))
  pos <- .dsr_cellules(sf::st_buffer(geo_pos, buffer_pos), grille)

  neg <- if (is.null(negatifs)) {
    proches <- .dsr_cellules(sf::st_buffer(geo_pos, buffer_neg), grille)
    setdiff(seq_len(terra::ncell(grille)), proches)
  } else {
    gn <- sf::st_union(sf::st_geometry(negatifs))
    if (!all(sf::st_geometry_type(gn) %in% c("POLYGON", "MULTIPOLYGON"))) {
      gn <- sf::st_buffer(gn, buffer_pos)
    }
    .dsr_cellules(gn, grille)
  }
  neg <- setdiff(neg, pos)

  if (!is.null(emprise)) {
    dedans <- .dsr_cellules(sf::st_union(sf::st_geometry(emprise)), grille)
    pos <- intersect(pos, dedans)
    neg <- intersect(neg, dedans)
  }

  v <- terra::values(couches, mat = TRUE)
  colnames(v) <- names(couches)
  complet <- stats::complete.cases(v)
  pos <- pos[complet[pos]]
  neg <- neg[complet[neg]]
  if (length(pos) == 0L || length(neg) == 0L) {
    dsr_abort(c(
      "Echantillon vide pour au moins une classe (positifs : {length(pos)}, negatifs : {length(neg)}).",
      "i" = "Verifier le recouvrement entre {.arg couches}, {.arg positifs} et {.arg emprise}, et les {.val NA} des canaux."
    ))
  }

  if (isTRUE(equilibre)) {
    n_cl <- min(length(pos), length(neg), max(1L, as.integer(n_max %/% 2L)))
    pos <- pos[sample.int(length(pos), n_cl)]
    neg <- neg[sample.int(length(neg), n_cl)]
  } else if (length(pos) + length(neg) > n_max) {
    f <- n_max / (length(pos) + length(neg))
    pos <- pos[sample.int(length(pos), max(1L, as.integer(length(pos) * f)))]
    neg <- neg[sample.int(length(neg), max(1L, as.integer(length(neg) * f)))]
  }

  cellules <- c(pos, neg)
  out <- as.data.frame(v[cellules, , drop = FALSE])
  names(out) <- names(couches)
  out <- cbind(y = c(rep(1L, length(pos)), rep(0L, length(neg))), out)
  rownames(out) <- NULL
  attr(out, "cellules") <- cellules
  out
}


#' Ajuster une conductivite apprise
#'
#' Ajuste sur un echantillon ([dsr_echantillon()]) le modele qui remplace la
#' combinaison parametrique de [dsr_conductivite()] quand `method = "model"`
#' (BRIEF sections 3.4 et 5, lot 8).
#'
#' @details
#' Deux moteurs. `"glm"` (defaut) est une regression logistique : sans
#' dependance, ses coefficients se lisent, et sur une dizaine de canaux deja
#' concus pour la tache elle est difficile a battre avec quelques milliers de
#' cellules. `"ranger"` (paquet en Suggests) est une foret aleatoire en mode
#' probabiliste, utile quand le jeu grossit et que les interactions comptent.
#'
#' **L'AUC rapportee est celle de la validation croisee stratifiee** a `k` plis,
#' pas celle de l'apprentissage : c'est la seule qui dise quelque chose de la
#' generalisation. L'ecart entre `auc_vc` et `auc_app` mesure le surapprentissage.
#' Un modele ajuste sur un massif n'est pas presume valide sur un autre — le
#' revalider avant de l'y appliquer (BRIEF section 4).
#'
#' @param echantillon `data.frame` issu de [dsr_echantillon()] : colonne `y`
#'   (0/1) et une colonne par canal.
#' @param methode `"glm"` (regression logistique, defaut) ou `"ranger"` (foret
#'   aleatoire probabiliste).
#' @param k Nombre de plis de la validation croisee stratifiee. `NULL` ou `< 2`
#'   pour la sauter. Defaut 5.
#' @param ... Arguments supplementaires transmis a `ranger::ranger()`.
#'
#' @return Un objet de classe `dsr_modele_conductivite` : liste `fit`,
#'   `methode`, `canaux`, `auc_vc` (validation croisee), `auc_app`
#'   (apprentissage), `n`, `prevalence`, `k`.
#' @seealso [dsr_echantillon()], [predict.dsr_modele_conductivite()],
#'   [dsr_conductivite()].
#' @export
dsr_apprendre_conductivite <- function(echantillon, methode = c("glm", "ranger"),
                                       k = 5, ...) {
  methode <- match.arg(methode)
  if (!is.data.frame(echantillon)) {
    dsr_abort("{.arg echantillon} doit etre un {.cls data.frame} ({.fun dsr_echantillon}).")
  }
  if (!"y" %in% names(echantillon)) {
    dsr_abort("{.arg echantillon} doit porter une colonne {.field y} (0/1).")
  }
  canaux <- setdiff(names(echantillon), "y")
  if (length(canaux) == 0L) {
    dsr_abort("{.arg echantillon} ne contient aucun canal explicatif.")
  }
  if (identical(methode, "ranger") && !requireNamespace("ranger", quietly = TRUE)) {
    dsr_abort(c("Le paquet {.pkg ranger} est requis pour {.code methode = \"ranger\"}.",
      "i" = 'Installation : install.packages("ranger")'))
  }

  d <- echantillon
  d$y <- as.integer(d$y > 0)
  d <- d[stats::complete.cases(d), , drop = FALSE]
  if (length(unique(d$y)) < 2L) {
    dsr_abort("{.arg echantillon} doit contenir les deux classes ({.field y} = 0 et 1).")
  }

  forme <- stats::as.formula(
    paste("y ~", paste(paste0("`", canaux, "`"), collapse = " + "))
  )
  ajuster <- if (identical(methode, "glm")) {
    function(dd) suppressWarnings(stats::glm(forme, data = dd, family = stats::binomial()))
  } else {
    function(dd) {
      dd$y <- factor(dd$y, levels = c(0L, 1L))
      ranger::ranger(forme, data = dd, probability = TRUE, ...)
    }
  }

  auc_vc <- NA_real_
  n_cl <- table(d$y)
  if (!is.null(k) && k >= 2L && all(n_cl >= k)) {
    plis <- .dsr_plis(d$y, k)
    pred <- rep(NA_real_, nrow(d))
    for (i in seq_len(k)) {
      test <- which(plis == i)
      if (length(test) == 0L || length(unique(d$y[-test])) < 2L) next
      pred[test] <- .dsr_predire_brut(ajuster(d[-test, , drop = FALSE]), methode,
        d[test, , drop = FALSE])
    }
    auc_vc <- .dsr_auc(d$y, pred)
  }

  fit <- ajuster(d)
  structure(
    list(
      fit = fit, methode = methode, canaux = canaux,
      auc_vc = auc_vc, auc_app = .dsr_auc(d$y, .dsr_predire_brut(fit, methode, d)),
      n = nrow(d), prevalence = mean(d$y), k = k
    ),
    class = "dsr_modele_conductivite"
  )
}


#' Predire une conductivite apprise
#'
#' Applique un modele ajuste par [dsr_apprendre_conductivite()] a une pile de
#' canaux ou a une table. Sur un `SpatRaster`, la sortie est un raster de
#' probabilite alignee sur l'entree ; les cellules dont un canal manque restent
#' `NA`.
#'
#' @param object Un objet `dsr_modele_conductivite`.
#' @param newdata `SpatRaster` portant au moins les canaux du modele, ou
#'   `data.frame` de memes colonnes.
#' @param ... Ignore.
#' @return Un `SpatRaster` mono-couche `p_route`, ou un vecteur numerique selon
#'   la classe de `newdata`.
#' @seealso [dsr_apprendre_conductivite()], [dsr_conductivite()].
#' @export
predict.dsr_modele_conductivite <- function(object, newdata, ...) {
  if (inherits(newdata, "SpatRaster")) {
    manquants <- setdiff(object$canaux, names(newdata))
    if (length(manquants) > 0L) {
      dsr_abort(c(
        "Canaux absents de {.arg newdata} : {.val {manquants}}.",
        "i" = "Le modele a ete ajuste sur : {.val {object$canaux}}."
      ))
    }
    v <- terra::values(newdata[[object$canaux]], mat = TRUE)
    dd <- as.data.frame(v)
    names(dd) <- object$canaux

    p <- rep(NA_real_, nrow(dd))
    ok <- stats::complete.cases(dd)
    if (any(ok)) {
      p[ok] <- .dsr_predire_brut(object$fit, object$methode, dd[ok, , drop = FALSE])
    }
    out <- terra::rast(newdata[[1]])
    terra::values(out) <- p
    names(out) <- "p_route"
    return(out)
  }

  if (!is.data.frame(newdata)) {
    dsr_abort("{.arg newdata} doit etre un {.cls SpatRaster} ou un {.cls data.frame}.")
  }
  manquants <- setdiff(object$canaux, names(newdata))
  if (length(manquants) > 0L) {
    dsr_abort("Canaux absents de {.arg newdata} : {.val {manquants}}.")
  }
  .dsr_predire_brut(object$fit, object$methode, newdata)
}


#' @param x Un objet `dsr_modele_conductivite`.
#' @rdname predict.dsr_modele_conductivite
#' @export
print.dsr_modele_conductivite <- function(x, ...) {
  cli::cli_h3("Conductivite apprise ({x$methode})")
  cli::cli_ul(c(
    "Canaux : {.val {x$canaux}}",
    "Echantillon : {x$n} cellules, prevalence {round(x$prevalence, 3)}",
    "AUC validation croisee ({x$k} plis) : {round(x$auc_vc, 3)}",
    "AUC apprentissage : {round(x$auc_app, 3)}"
  ))
  invisible(x)
}


# Prediction brute (probabilite de la classe 1), commune au modele final et aux
# plis de validation croisee.
#' @noRd
.dsr_predire_brut <- function(fit, methode, dd) {
  if (identical(methode, "glm")) {
    return(as.numeric(stats::predict(fit, newdata = dd, type = "response")))
  }
  pr <- stats::predict(fit, data = dd)$predictions
  as.numeric(pr[, "1"])
}


# Affectation stratifiee des plis : chaque classe est repartie uniformement sur
# les k plis, pour qu'aucun pli d'apprentissage ne perde une classe entiere.
#' @noRd
.dsr_plis <- function(y, k) {
  plis <- integer(length(y))
  for (cl in unique(y)) {
    i <- which(y == cl)
    plis[i[sample.int(length(i))]] <- rep_len(seq_len(k), length(i))
  }
  plis
}


# AUC par la statistique de Mann-Whitney : proportion de paires (positif,
# negatif) correctement ordonnees. Insensible au seuil, robuste au desequilibre.
#' @noRd
.dsr_auc <- function(y, p) {
  ok <- !is.na(p) & !is.na(y)
  y <- y[ok]; p <- p[ok]
  n1 <- sum(y == 1L); n0 <- sum(y == 0L)
  if (n1 == 0L || n0 == 0L) return(NA_real_)
  r <- rank(p)
  (sum(r[y == 1L]) - n1 * (n1 + 1) / 2) / (n1 * n0)
}


# Numeros des cellules d'une grille couvertes par une geometrie.
#' @noRd
.dsr_cellules <- function(geom, grille) {
  m <- terra::rasterize(terra::vect(sf::st_as_sf(geom)), grille, field = 1L,
    background = NA)
  which(!is.na(terra::values(m, mat = FALSE)))
}
