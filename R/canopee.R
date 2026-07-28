# Canal optique : ce que l'ortho apporte, et ou s'arrete ce qu'elle peut dire.
#
# Frontiere posee d'emblee, parce que c'est la seule chose qui compte ici : la
# largeur de chaussee se mesure sur le MNT (voir measure.R), et rien dans ce
# fichier ne sert a la mesurer ni a la calibrer. Une trouee de canopee n'est pas
# une chaussee : sous futaie mature elle est plus etroite (les houppiers
# debordent), sur une coupe rase elle est beaucoup plus large. L'ecart n'est pas
# constant, il est correle a la structure du peuplement riverain, donc il change
# tout au long du troncon. Un decalage constant se calibre ; celui-la non.
#
# Ce que le canal optique apporte reellement, et que le lidar ne donne pas :
#
#   - dsr_gabarit_lateral() : jusqu'ou la trouee s'ecarte de l'axe, donc ou les
#     houppiers debordent sur l'emprise. C'est le critere LATERAL qui manquait a
#     dsr_trafficability() -- lequel ne verifiait que pente, devers, rayon,
#     largeur et gabarit vertical. Sortie metier : ou elaguer.
#
#   - dsr_ndvi() / dsr_largeur_ndvi() : la signature spectrale du mineral, a la
#     resolution NATIVE de la BD ORTHO (20 cm), la seule des sorties optiques qui
#     soit a la bonne echelle pour une chaussee de 3 a 4 m.
#
# Pourquoi ces canaux valent quelque chose malgre tout : ils sont INDEPENDANTS
# du lidar. Un modele de hauteur de canopee predit depuis l'ortho (RVB + IRC) ne
# partage aucune erreur avec le MNT Lidar HD. C'est precisement ce qui manquait
# quand on a ecarte les traces produites par ALSroads : une seconde source qui ne
# soit pas la premiere sous un autre nom.


#' Largeur de la trouee de canopee et surplomb le long d'un trace
#'
#' Mesure, station par station, la largeur de la **trouee de canopee** centree
#' sur l'axe -- la plage continue ou la hauteur de vegetation reste sous
#' `seuil_ouvert` -- et, si la largeur de chaussee est fournie, le **surplomb** :
#' de combien les houppiers empietent sur l'emprise roulable. C'est le critere
#' lateral absent de [dsr_trafficability()], et la reponse a la question
#' operationnelle *ou elaguer*.
#'
#' @details
#' **Ce n'est pas une mesure de largeur de chaussee.** La trouee et la chaussee
#' divergent de facon variable selon le peuplement riverain ; voir l'en-tete du
#' fichier. `LARGEUR_DEGAGEE` ne doit jamais alimenter
#' [dsr_calibrer_largeur()].
#'
#' **Le surplomb est detecte, sa hauteur est surestimee.** Un modele de hauteur
#' de canopee donne le **sommet** du houppier, pas le dessous de la branche. Une
#' branche basse d'un arbre de 25 m est vue a 25 m : `HAUT_SURPLOMB` est donc un
#' indicateur **permissif**, qui attrape a coup sur la regeneration et les
#' rejets de bord de route (le cas dominant) et rate les branches basses des
#' grands arbres. Seul [dsr_gabarit_libre()], sur le nuage classe, donne le
#' dessous de branche.
#'
#' **Attention a la maille reelle.** Un CHM predit par les modeles Open-Canopy
#' a une maille native de l'ordre de 1,5 m ; sureechantillonne a 0,20 m il
#' *declare* 0,20 m mais ne porte que l'information de sa maille d'origine. Le
#' paquet ne peut pas detecter ce cas -- la fonction ne signale que la
#' resolution declaree. Pour une mesure au decimetre, il n'y a que le MNT.
#'
#' @param trace Un `sf`/`sfc` `LINESTRING` (ou l'element `trace` de
#'   [dsr_pathfinder()]).
#' @param chm `SpatRaster` de hauteur de vegetation (CHM predit depuis l'ortho,
#'   ou MNH lidar). Une seule bande utilisee.
#' @param largeur Largeur roulable par station, pour le surplomb : un vecteur
#'   numerique (longueur 1 ou nombre de stations), ou le `sf` `stations` de
#'   [dsr_measure()] dont la colonne `LARGEUR_ROULABLE` est reprise. `NULL`
#'   (defaut) : `SURPLOMB` et `HAUT_SURPLOMB` valent `NA`. Le decoupage en
#'   stations etant deterministe, un `dsr_measure()` et un
#'   `dsr_gabarit_lateral()` appeles sur le meme trace avec le meme `pas`
#'   donnent le meme nombre de stations.
#' @param pas Espacement des stations le long du trace, en metres. Defaut 2.
#' @param demi_largeur Demi-largeur des profils, en metres. Defaut 8. Une trouee
#'   plus large que `2 * demi_largeur` est tronquee (colonne `TRONQUE`).
#' @param pas_travers Pas d'echantillonnage transversal, en metres. Defaut 0.5.
#' @param seuil_ouvert Hauteur (m) sous laquelle une cellule compte comme
#'   degagee. Defaut 2 : en deca on est dans l'herbe et le semis, qui ne genent
#'   pas un grumier lateralement.
#' @param liss_travers Fenetre de lissage transversal (nombre d'echantillons,
#'   impair). Defaut 1 (aucun lissage) : contrairement au MNT, un CHM porte de
#'   vraies ruptures qu'il ne faut pas arrondir.
#'
#' @return Un `sf` `POINT` par station, avec `chainage`, `LARGEUR_DEGAGEE` (m),
#'   `DEGAGE_G` et `DEGAGE_D` (distance de l'axe au bord de trouee, m, par
#'   cote), `TRONQUE` (la trouee sort du profil), et si `largeur` est fourni
#'   `SURPLOMB` (m d'emprise recouverte, 0 si aucun) et `HAUT_SURPLOMB` (hauteur
#'   du plus bas houppier empietant, lue au plus proche voisin pour rester une
#'   valeur de cellule reelle ; `Inf` si aucun).
#' @seealso [dsr_gabarit_libre()] pour le gabarit vertical sur le nuage,
#'   [dsr_trafficability()] qui consomme `SURPLOMB` et `HAUT_SURPLOMB`.
#' @examples
#' \donttest{
#' chm <- terra::rast(xmin = 0, xmax = 60, ymin = 0, ymax = 60,
#'   resolution = 1, crs = "EPSG:2154")
#' terra::values(chm) <- 20
#' # Un couloir degage de 6 m de large autour de y = 30
#' xy <- terra::xyFromCell(chm, seq_len(terra::ncell(chm)))
#' chm[abs(xy[, 2] - 30) <= 3] <- 0
#' tr <- sf::st_sf(geometry = sf::st_sfc(
#'   sf::st_linestring(cbind(c(5, 55), c(30, 30))), crs = 2154))
#' g <- dsr_gabarit_lateral(tr, chm, largeur = 4)
#' summary(g$LARGEUR_DEGAGEE)
#' }
#' @export
dsr_gabarit_lateral <- function(trace, chm, largeur = NULL, pas = 2,
                                demi_largeur = 8, pas_travers = 0.5,
                                seuil_ouvert = 2, liss_travers = 1) {
  if (!inherits(chm, "SpatRaster")) {
    dsr_abort("{.arg chm} doit etre un {.cls SpatRaster} de hauteur de vegetation.")
  }
  if (terra::nlyr(chm) > 1L) chm <- chm[[1]]
  .dsr_avertir_maille(chm, pas_travers)

  pr <- dsr_profils(trace, chm, pas = pas, demi_largeur = demi_largeur,
    pas_travers = pas_travers)
  offsets <- pr$offsets
  z <- pr$z
  ns <- nrow(z)
  ic <- which.min(abs(offsets))

  larg <- .dsr_largeur_arg(largeur, ns)

  # Deux lectures du meme CHM, et il faut les deux.
  #
  # La GEOMETRIE (bord de trouee) se lit en bilineaire : c'est ce qui permet
  # d'interpoler le bord entre deux echantillons et d'effacer le biais de
  # troncature au pas d'echantillonnage.
  #
  # La HAUTEUR se lit au plus proche voisin. Le surplomb se mesure par
  # construction a l'aplomb du bord de trouee, or c'est exactement la que la
  # bilineaire melange le vide et le houppier : elle y rend une hauteur
  # intermediaire qui n'existe dans aucune cellule. Sur une trouee de 3 m sous
  # une chaussee de 5 m, ce melange divise la hauteur lue par deux. Un minimum
  # sur des valeurs interpolees n'est pas une mesure.
  zn <- if (any(!is.na(larg))) {
    dsr_profils(trace, chm, pas = pas, demi_largeur = demi_largeur,
      pas_travers = pas_travers, methode = "simple")$z
  } else {
    NULL
  }

  lg <- numeric(ns); dg <- numeric(ns); dd <- numeric(ns)
  tronque <- logical(ns); haut <- rep(NA_real_, ns)
  for (i in seq_len(ns)) {
    v <- dsr_lisser(z[i, ], liss_travers)
    r <- .dsr_run_centre(v, offsets, ic, seuil_ouvert, sens = "sous")
    lg[i] <- r$largeur; dg[i] <- -r$g; dd[i] <- r$d; tronque[i] <- r$tronque
    # Plus bas houppier qui empiete sur l'emprise roulable : minimum du CHM
    # parmi les cellules FERMEES situees a l'aplomb de la chaussee.
    if (!is.na(larg[i]) && larg[i] > 0) {
      vn <- zn[i, ]
      ferme <- abs(offsets) <= larg[i] / 2 & !is.na(vn) & vn > seuil_ouvert
      haut[i] <- if (any(ferme)) min(vn[ferme]) else Inf
    }
  }

  st <- pr$stations
  st$LARGEUR_DEGAGEE <- lg
  st$DEGAGE_G <- dg
  st$DEGAGE_D <- dd
  st$TRONQUE <- tronque
  st$SURPLOMB <- if (all(is.na(larg))) NA_real_ else pmax(0, larg - lg)
  st$HAUT_SURPLOMB <- haut
  st
}


#' Indice de vegetation normalise (NDVI) depuis une ortho infrarouge
#'
#' Calcule le NDVI `(PIR - Rouge) / (PIR + Rouge)` a partir d'une ortho
#' infrarouge couleur -- la BD ORTHO IRC de l'IGN, dont les bandes sont dans
#' l'ordre PIR, Rouge, Vert. Contrairement a un modele de hauteur de canopee
#' predit, le NDVI est calcule sur les pixels **natifs** de l'ortho (20 cm) :
#' c'est la seule grandeur optique a l'echelle d'une chaussee forestiere.
#'
#' @details
#' Le rapport est sans dimension : aucune normalisation radiometrique n'est
#' requise, des comptes numeriques 8 bits conviennent. Les pixels ou
#' `PIR + Rouge` s'annule sont mis a `NA`.
#'
#' Limites, a garder en tete avant d'en tirer une largeur : sous couvert ferme
#' la chaussee est a l'ombre et son NDVI remonte ; une piste enherbee ne se
#' distingue pas du sous-bois ; le millesime de l'ortho n'est pas celui du
#' lidar.
#'
#' @param irc `SpatRaster` multi-bandes de l'ortho IRC.
#' @param bandes Indices ou noms des bandes proche infrarouge et rouge. Defaut
#'   `c(pir = 1, rouge = 2)`, l'ordre de la BD ORTHO IRC.
#'
#' @return Un `SpatRaster` a une bande nommee `ndvi`, valeurs dans `[-1, 1]`.
#' @seealso [dsr_largeur_ndvi()], [dsr_canaux_externes()] pour verser le NDVI
#'   dans la pile de canaux.
#' @examples
#' irc <- terra::rast(xmin = 0, xmax = 10, ymin = 0, ymax = 10,
#'   resolution = 1, nlyrs = 3, crs = "EPSG:2154")
#' terra::values(irc) <- cbind(rep(200, 100), rep(50, 100), rep(60, 100))
#' terra::global(dsr_ndvi(irc), "mean")
#' @export
dsr_ndvi <- function(irc, bandes = c(pir = 1, rouge = 2)) {
  if (!inherits(irc, "SpatRaster")) {
    dsr_abort("{.arg irc} doit etre un {.cls SpatRaster} multi-bandes.")
  }
  if (length(bandes) != 2L) {
    dsr_abort("{.arg bandes} doit designer exactement deux bandes (PIR, Rouge).")
  }
  if (terra::nlyr(irc) < 2L) {
    dsr_abort("{.arg irc} doit porter au moins deux bandes (PIR et Rouge).")
  }
  pir <- irc[[bandes[[1]]]]
  rouge <- irc[[bandes[[2]]]]

  somme <- pir + rouge
  out <- (pir - rouge) / somme
  out[somme == 0] <- NA
  names(out) <- "ndvi"
  out
}


#' Largeur de la plage minerale par NDVI le long d'un trace
#'
#' Mesure, station par station, la largeur de la plage continue centree sur
#' l'axe ou le NDVI reste **sous** un seuil -- la signature du mineral, donc de
#' la chaussee nue. Le seuil est determine automatiquement par la methode d'Otsu
#' (maximisation de la variance interclasse) sur l'ensemble des profils, ce qui
#' evite d'imposer une valeur qui depend du millesime, de la saison et de
#' l'exposition.
#'
#' @details
#' **Mesure independante, pas mesure de reference.** `LARGEUR_NDVI` est un
#' second avis, calcule sur une source qui ne partage aucune erreur avec le
#' MNT ; c'est ce qui la rend utile. Elle ne remplace pas
#' `LARGEUR_ROULABLE` : une piste enherbee ou ombragee ne donne aucun contraste
#' spectral, et l'ortho n'a pas le millesime du lidar. La comparer a
#' `LARGEUR_ROULABLE` renseigne sur l'etat de surface (mineral degage contre
#' enherbement), pas sur l'exactitude de la mesure MNT.
#'
#' Le seuil est **global** et non par station : sur une trentaine
#' d'echantillons transversaux, Otsu est instable. Il est renvoye dans
#' l'attribut `"seuil"` du resultat.
#'
#' @param trace Un `sf`/`sfc` `LINESTRING` (ou l'element `trace` de
#'   [dsr_pathfinder()]).
#' @param ndvi `SpatRaster` du NDVI, typiquement la sortie de [dsr_ndvi()].
#' @param seuil `"otsu"` (defaut) pour un seuil determine automatiquement, ou
#'   une valeur numerique imposee.
#' @param pas Espacement des stations le long du trace, en metres. Defaut 2.
#' @param demi_largeur Demi-largeur des profils, en metres. Defaut 8.
#' @param pas_travers Pas d'echantillonnage transversal, en metres. Defaut 0.2,
#'   la resolution native de la BD ORTHO.
#' @param liss_travers Fenetre de lissage transversal (nombre d'echantillons,
#'   impair). Defaut 5 : le NDVI pixel a pixel est bruite (ombres portees,
#'   ornieres, gravillons).
#'
#' @return Un `sf` `POINT` par station, avec `chainage`, `LARGEUR_NDVI` (m,
#'   `NA` si la plage sort du profil), `NDVI_AXE` (valeur sur l'axe) et
#'   `TRONQUE`. L'attribut `"seuil"` porte le seuil retenu.
#' @seealso [dsr_ndvi()], [dsr_measure()].
#' @examples
#' \donttest{
#' r <- terra::rast(xmin = 0, xmax = 60, ymin = 0, ymax = 60,
#'   resolution = 0.5, crs = "EPSG:2154")
#' xy <- terra::xyFromCell(r, seq_len(terra::ncell(r)))
#' terra::values(r) <- ifelse(abs(xy[, 2] - 30) <= 2, 0.05, 0.75)
#' tr <- sf::st_sf(geometry = sf::st_sfc(
#'   sf::st_linestring(cbind(c(5, 55), c(30, 30))), crs = 2154))
#' l <- dsr_largeur_ndvi(tr, r, pas_travers = 0.5)
#' stats::median(l$LARGEUR_NDVI, na.rm = TRUE)
#' }
#' @export
dsr_largeur_ndvi <- function(trace, ndvi, seuil = "otsu", pas = 2,
                             demi_largeur = 8, pas_travers = 0.2,
                             liss_travers = 5) {
  if (!inherits(ndvi, "SpatRaster")) {
    dsr_abort("{.arg ndvi} doit etre un {.cls SpatRaster}.")
  }
  if (terra::nlyr(ndvi) > 1L) ndvi <- ndvi[[1]]
  if (!(identical(seuil, "otsu") || (is.numeric(seuil) && length(seuil) == 1L))) {
    dsr_abort('{.arg seuil} doit valoir {.val otsu} ou un nombre.')
  }

  pr <- dsr_profils(trace, ndvi, pas = pas, demi_largeur = demi_largeur,
    pas_travers = pas_travers)
  offsets <- pr$offsets
  ns <- nrow(pr$z)
  ic <- which.min(abs(offsets))

  liss <- t(apply(pr$z, 1, dsr_lisser, w = liss_travers))

  s <-if (identical(seuil, "otsu")) .dsr_otsu(as.vector(liss)) else seuil
  if (!is.finite(s)) {
    dsr_abort(c(
      "Seuil NDVI indeterminable : aucune valeur finie dans les profils.",
      "i" = "Verifier le recouvrement entre {.arg trace} et {.arg ndvi}."
    ))
  }

  lg <- rep(NA_real_, ns); tronque <- logical(ns)
  for (i in seq_len(ns)) {
    r <- .dsr_run_centre(liss[i, ], offsets, ic, s, sens = "sous")
    tronque[i] <- r$tronque
    # Une plage qui sort du profil n'est pas mesuree, elle est censuree : la
    # renvoyer telle quelle ferait passer une troncature pour une largeur.
    lg[i] <- if (r$tronque) NA_real_ else r$largeur
  }

  st <- pr$stations
  st$LARGEUR_NDVI <- lg
  st$NDVI_AXE <- liss[, ic]
  st$TRONQUE <- tronque
  attr(st, "seuil") <- s
  st
}


# Plage continue contenant le centre du profil, avec bord INTERPOLE entre le
# dernier echantillon retenu et le premier rejete. Sans cette interpolation, la
# largeur est tronquee au pas d'echantillonnage, ce qui introduit un biais
# systematique du meme ordre que la grandeur mesuree sur une chaussee etroite.
#
# `sens = "sous"` : la plage est celle ou v <= seuil (trouee, mineral).
# `sens = "sur"`  : la plage est celle ou v >= seuil.
#' @noRd
.dsr_run_centre <- function(v, offsets, ic, seuil, sens = c("sous", "sur")) {
  sens <- match.arg(sens)
  no <- length(v)
  dedans <- if (identical(sens, "sous")) {
    !is.na(v) & v <= seuil
  } else {
    !is.na(v) & v >= seuil
  }
  if (!dedans[ic]) {
    return(list(g = 0, d = 0, largeur = 0, il = ic, ir = ic, tronque = FALSE))
  }

  il <- ic
  while (il > 1L && dedans[il - 1L]) il <- il - 1L
  ir <- ic
  while (ir < no && dedans[ir + 1L]) ir <- ir + 1L

  bord <- function(i, j) {
    if (j < 1L || j > no || is.na(v[j]) || is.na(v[i])) return(offsets[i])
    d <- v[j] - v[i]
    if (!is.finite(d) || d == 0) return(offsets[i])
    t <- (seuil - v[i]) / d
    offsets[i] + min(max(t, 0), 1) * (offsets[j] - offsets[i])
  }

  list(
    g = bord(il, il - 1L), d = bord(ir, ir + 1L),
    largeur = bord(ir, ir + 1L) - bord(il, il - 1L),
    il = il, ir = ir, tronque = il == 1L || ir == no
  )
}


# Seuil d'Otsu : maximisation de la variance interclasse sur un histogramme.
# Binning fait a la main plutot que par graphics::hist() pour ne pas avoir a
# dependre de `graphics` pour vingt lignes.
#' @noRd
.dsr_otsu <- function(x, nbins = 256L) {
  x <- x[is.finite(x)]
  if (length(x) < 2L) return(NA_real_)
  rg <- range(x)
  if (diff(rg) <= 0) return(rg[1])

  br <- seq(rg[1], rg[2], length.out = nbins + 1L)
  idx <- findInterval(x, br, rightmost.closed = TRUE, all.inside = TRUE)
  p <- tabulate(idx, nbins) / length(x)
  mids <- (br[-1L] + br[-(nbins + 1L)]) / 2

  w <- cumsum(p)            # poids de la classe basse
  m <- cumsum(p * mids)     # moment de la classe basse
  mt <- m[nbins]            # moyenne totale
  den <- w * (1 - w)
  vb <- ifelse(den > 0, (mt * w - m)^2 / den, -Inf)
  mids[which.max(vb)]
}


# Normaliser l'argument `largeur` de dsr_gabarit_lateral().
#' @noRd
.dsr_largeur_arg <- function(largeur, ns) {
  if (is.null(largeur)) return(rep(NA_real_, ns))

  larg <- if (inherits(largeur, "sf") || is.data.frame(largeur)) {
    if (!"LARGEUR_ROULABLE" %in% names(largeur)) {
      dsr_abort("{.arg largeur} : colonne {.field LARGEUR_ROULABLE} absente.")
    }
    largeur$LARGEUR_ROULABLE
  } else if (is.numeric(largeur)) {
    largeur
  } else {
    dsr_abort("{.arg largeur} doit etre numerique ou un {.cls sf} de {.fun dsr_measure}.")
  }

  if (length(larg) == 1L) larg <- rep(larg, ns)
  if (length(larg) != ns) {
    dsr_abort(c(
      "{.arg largeur} : {length(larg)} valeur{?s} pour {ns} station{?s}.",
      "i" = "Appeler {.fun dsr_measure} et {.fun dsr_gabarit_lateral} sur le meme trace avec le meme {.arg pas}."
    ))
  }
  as.numeric(larg)
}


# Signaler une maille trop grossiere pour la grandeur visee. Le paquet ne peut
# pas voir qu'un raster a ete sureechantillonne : seule la resolution DECLAREE
# est testee, d'ou la mention explicite dans le message.
#' @noRd
.dsr_avertir_maille <- function(r, pas_travers) {
  m <- terra::res(r)[1]
  if (!is.finite(m) || m <= 1) return(invisible())
  dsr_inform(c(
    "!" = "Maille de {round(m, 2)} m : une chaussee de 4 m ne couvre que {round(4 / m, 1)} cellule{?s}.",
    "i" = "Sortie a lire a l'echelle du troncon, pas au decimetre.",
    "i" = "Un raster sureechantillonne declare une maille fine sans porter l'information correspondante."
  ))
  invisible()
}
