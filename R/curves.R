# Geometrie des centre-lignes issues du squelette (post-traitement du
# vectoriseur, voir detect.R).
#
# Le squelette d'une emprise rasterisee est un escalier : ses sommets sont des
# centres de cellules, donc chaque virage est un ressaut de 0 ou 45 degres. Ce
# n'est pas qu'un defaut cosmetique -- c'est une geometrie fausse la ou elle
# compte. `dsr_measure()` en tire RAYON_COURBURE et SINUOSITE, et
# `dsr_trafficability()` en deduit l'aptitude grumier : un escalier gonfle la
# sinuosite et ecrase le rayon de courbure, donc declare inapte une route qui
# ne l'est pas.
#
# Deux lissages, tires de la litterature fournie :
#
#   - Savitzky-Golay (Wang et al. 2025, arXiv 2502.07486) : ajustement
#     polynomial local, applique separement a x(t) et y(t). Filtre local,
#     conserve la longueur, ne coupe pas les virages francs.
#   - Bezier cubique par morceaux (representation de DOGE, Sun et al. 2025,
#     arXiv 2511.19850) : ajustement aux moindres carres a la Schneider, avec
#     decoupe recursive sur l'erreur maximale. Donne une courbe C1 par morceaux,
#     analytiquement derivable, et beaucoup moins de sommets.
#
# Dans les deux cas les EXTREMITES SONT FIGEES : elles portent la topologie
# (carrefours, raccordements au reseau public). Un lissage qui les deplace
# casserait le graphe que dsr_reseau() reconstruit ensuite.


# --- Savitzky-Golay ----------------------------------------------------------

# Coefficients d'un ajustement polynomial local sur une fenetre centree :
# renvoie la matrice (ordre+1) x (2*demi+1) telle que C %*% y donne les
# coefficients du polynome ajuste, en base z = -demi..demi.
#' @noRd
.dsr_sg_coef <- function(demi, ordre) {
  z <- seq(-demi, demi)
  vdm <- outer(z, 0:ordre, "^")
  solve(crossprod(vdm), t(vdm))
}


# Lissage Savitzky-Golay d'une serie. Les bords sont traites par evaluation du
# polynome de la fenetre extreme (equivalent du mode « interp » de scipy),
# et non par repetition ou troncature.
#' @noRd
.dsr_savitzky_golay <- function(y, demi, ordre = 2L) {
  n <- length(y)
  if (demi < 1L || ordre >= 2L * demi + 1L || n < 2L * demi + 1L) return(y)
  co <- .dsr_sg_coef(demi, ordre)
  z <- seq(-demi, demi)
  out <- y

  centre <- co[1, ]
  for (i in (demi + 1L):(n - demi)) {
    out[i] <- sum(centre * y[(i - demi):(i + demi)])
  }
  c_debut <- co %*% y[1:(2L * demi + 1L)]
  c_fin <- co %*% y[(n - 2L * demi):n]
  for (i in seq_len(demi)) {
    out[i] <- sum(c_debut * z[i]^(0:ordre))
    out[n - demi + i] <- sum(c_fin * z[demi + 1L + i]^(0:ordre))
  }
  out
}


# Lissage d'une polyligne : Savitzky-Golay sur x et y separement, extremites
# restituees a l'identique pour ne pas rompre la topologie.
#' @noRd
.dsr_lisser_sg <- function(co, demi, ordre = 2L) {
  if (nrow(co) < 2L * demi + 1L) return(co)
  out <- cbind(
    .dsr_savitzky_golay(co[, 1], demi, ordre),
    .dsr_savitzky_golay(co[, 2], demi, ordre)
  )
  out[1, ] <- co[1, ]
  out[nrow(out), ] <- co[nrow(co), ]
  out
}


# --- Bezier cubique par morceaux (representation DOGE) -----------------------

#' @noRd
.dsr_unitaire <- function(v) {
  n <- sqrt(sum(v^2))
  if (!is.finite(n) || n < 1e-12) c(0, 0) else v / n
}


# Evaluation d'une Bezier cubique en t (t peut etre un vecteur).
#' @noRd
.dsr_bezier_eval <- function(pc, t) {
  u <- 1 - t
  outer(u^3, 1) %*% pc[1, , drop = FALSE] +
    outer(3 * u^2 * t, 1) %*% pc[2, , drop = FALSE] +
    outer(3 * u * t^2, 1) %*% pc[3, , drop = FALSE] +
    outer(t^3, 1) %*% pc[4, , drop = FALSE]
}


# Ajustement d'UNE Bezier cubique a un nuage ordonne, tangentes imposees aux
# deux bouts (algorithme de Schneider). Les points de controle P0 et P3 sont les
# extremites exactes : l'ajustement ne peut pas deplacer un noeud.
#' @noRd
.dsr_bezier_un <- function(co, t1, t2, param) {
  n <- nrow(co)
  p0 <- co[1, ]; p3 <- co[n, ]
  a1 <- 3 * param * (1 - param)^2
  a2 <- 3 * param^2 * (1 - param)
  base <- outer((1 - param)^3 + 3 * param * (1 - param)^2, 1) %*% rbind(p0) +
    outer(3 * param^2 * (1 - param) + param^3, 1) %*% rbind(p3)
  reste <- co - base

  c11 <- sum(a1^2) * sum(t1^2)
  c12 <- sum(a1 * a2) * sum(t1 * t2)
  c22 <- sum(a2^2) * sum(t2^2)
  x1 <- sum(reste * (a1 %o% t1))
  x2 <- sum(reste * (a2 %o% t2))

  det <- c11 * c22 - c12 * c12
  corde <- sqrt(sum((p3 - p0)^2))
  alpha <- if (abs(det) < 1e-12) {
    c(corde / 3, corde / 3)
  } else {
    c((x1 * c22 - c12 * x2) / det, (c11 * x2 - x1 * c12) / det)
  }
  if (!all(is.finite(alpha)) || any(alpha <= 1e-9)) {
    alpha <- c(corde / 3, corde / 3)
  }
  rbind(p0, p0 + alpha[1] * t1, p3 + alpha[2] * t2, p3)
}


# Ajustement recursif : si l'erreur maximale depasse `tol`, on coupe au point
# fautif et l'on recommence de part et d'autre, avec une tangente estimee par
# difference centree. C'est ce qui permet de suivre un virage franc sans le
# raboter, la ou une Bezier unique couperait la corde.
#' @noRd
.dsr_bezier_rec <- function(co, t1, t2, tol, profondeur, max_profondeur) {
  n <- nrow(co)
  if (n < 3L) {
    p0 <- co[1, ]; p3 <- co[n, ]
    return(list(rbind(p0, p0 + (p3 - p0) / 3, p3 - (p3 - p0) / 3, p3)))
  }
  d <- sqrt(rowSums(diff(co)^2))
  cum <- c(0, cumsum(d))
  total <- cum[length(cum)]
  if (total < 1e-12) return(list())
  param <- cum / total

  pc <- .dsr_bezier_un(co, t1, t2, param)
  ecart <- sqrt(rowSums((.dsr_bezier_eval(pc, param) - co)^2))
  k <- which.max(ecart)

  if (max(ecart) <= tol || profondeur >= max_profondeur ||
      k <= 1L || k >= n) {
    return(list(pc))
  }
  tk <- .dsr_unitaire(co[k + 1L, ] - co[k - 1L, ])
  c(
    .dsr_bezier_rec(co[1:k, , drop = FALSE], t1, -tk, tol, profondeur + 1L,
      max_profondeur),
    .dsr_bezier_rec(co[k:n, , drop = FALSE], tk, t2, tol, profondeur + 1L,
      max_profondeur)
  )
}


# Polyligne -> Bezier cubiques par morceaux -> polyligne reechantillonnee.
# La sortie reste un LINESTRING (sf n'a pas de type courbe) : le gain est une
# geometrie lisse et econome en sommets, pas un nouveau type geometrique.
#' @noRd
.dsr_lisser_bezier <- function(co, tol, pas, max_profondeur = 8L) {
  n <- nrow(co)
  if (n < 4L) return(co)
  t1 <- .dsr_unitaire(co[2, ] - co[1, ])
  t2 <- .dsr_unitaire(co[n - 1L, ] - co[n, ])
  courbes <- .dsr_bezier_rec(co, t1, t2, tol, 0L, max_profondeur)
  if (length(courbes) == 0L) return(co)

  morceaux <- lapply(courbes, function(pc) {
    corde <- sum(sqrt(rowSums(diff(pc)^2)))
    m <- max(2L, as.integer(ceiling(corde / max(pas, 1e-6))))
    .dsr_bezier_eval(pc, seq(0, 1, length.out = m))
  })
  out <- morceaux[[1]]
  for (i in seq_along(morceaux)[-1]) {
    out <- rbind(out, morceaux[[i]][-1, , drop = FALSE])
  }
  out[1, ] <- co[1, ]
  out[nrow(out), ] <- co[n, ]
  out
}


# --- Raccordement des trouees ------------------------------------------------

# Reconnexion des composantes separees par une trouee (Wang et al. 2025 : les
# extremites proches sont reliees par distance euclidienne). On y ajoute un
# CRITERE D'ALIGNEMENT, absent de l'article : relier deux extremites sur la
# seule distance suffit en zone peu dense, mais sur un reseau forestier serre
# cela souderait une piste a un cloisonnement voisin qu'elle ne rejoint pas.
# Les deux tangentes doivent donc pointer l'une vers l'autre.
#
# Cette etape INVENTE de la geometrie la ou la donnee ne montre rien : elle est
# desactivee par defaut, et c'est delibere.
#' @noRd
.dsr_raccorder <- function(lignes, dmax, angle_max = 40) {
  if (length(lignes) < 2L || dmax <= 0) return(lignes)
  cos_min <- cos(angle_max * pi / 180)

  repeat {
    n <- length(lignes)
    if (n < 2L) break
    bouts <- lapply(lignes, function(co) {
      list(
        p = rbind(co[1, ], co[nrow(co), ]),
        # tangentes sortantes, estimees sur quelques sommets pour amortir
        # l'escalier du squelette
        t = rbind(
          .dsr_unitaire(co[1, ] - co[min(nrow(co), 4L), ]),
          .dsr_unitaire(co[nrow(co), ] - co[max(1L, nrow(co) - 3L), ])
        )
      )
    })

    meilleur <- NULL
    for (i in seq_len(n - 1L)) {
      for (j in (i + 1L):n) {
        for (a in 1:2) for (b in 1:2) {
          v <- bouts[[j]]$p[b, ] - bouts[[i]]$p[a, ]
          d <- sqrt(sum(v^2))
          if (d > dmax || d < 1e-9) next
          u <- v / d
          if (sum(bouts[[i]]$t[a, ] * u) < cos_min) next
          if (sum(bouts[[j]]$t[b, ] * -u) < cos_min) next
          if (is.null(meilleur) || d < meilleur$d) {
            meilleur <- list(d = d, i = i, j = j, a = a, b = b)
          }
        }
      }
    }
    if (is.null(meilleur)) break

    ci <- lignes[[meilleur$i]]
    cj <- lignes[[meilleur$j]]
    if (meilleur$a == 1L) ci <- ci[nrow(ci):1, , drop = FALSE]  # bout libre a la fin
    if (meilleur$b == 2L) cj <- cj[nrow(cj):1, , drop = FALSE]  # bout libre au debut
    fusion <- rbind(ci, cj)
    lignes <- lignes[-c(meilleur$i, meilleur$j)]
    lignes[[length(lignes) + 1L]] <- fusion
  }
  lignes
}
