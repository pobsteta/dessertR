# Agent conducteur : vectorisation de reseau par suivi incremental.
#
# Reimplementation terra/sf du coeur de vecnet (Roussel et al. 2023, GPL-3),
# adossee au noyau Rust du paquet. Le portage direct etait exclu : vecnet importe
# `sp`, `raster` et `gdistance` -- la pile spatiale en fin de vie -- alors que
# dessertR est terra/sf, et il n'est ni sur le CRAN ni sur un r-universe.
#
# DIFFERENCE DE NATURE avec dsr_pathfinder(). Le pathfinder relie deux points
# CONNUS : il sait ou il va. L'agent ne le sait pas. Il avance par pas, et a
# chaque pas il regarde en eventail devant lui, calcule le cout d'atteinte de
# chaque direction, et part vers la moins chere. C'est ce qui le rend robuste
# aux trouees -- une coupure de conductivite se franchit si la route reprend de
# l'autre cote -- et c'est ce qui lui fait produire un RESEAU (les directions
# non retenues sont autant d'amorces d'embranchements) la ou le pathfinder
# produit un chemin.
#
# Trois substitutions par rapport a vecnet :
#   - gdistance::costDistance / shortestPath -> noyau Rust du paquet. Meme
#     modele de cout (resistance moyenne x distance parcourue), mais sur 16
#     voisins au lieu de 8, ce qui supprime le biais de metrication.
#   - pracma::findpeaks et zoo::ma -> .dsr_minima_cout() et .dsr_moyenne_mobile().
#   - la classe MapManager (chargement de l'emprise par morceaux) -> le recadrage
#     terra par pas. terra lit deja paresseusement depuis le disque ; la
#     mecanique de tuilage de vecnet n'a plus d'objet.


# Champ de cout cumule depuis un point, sur TOUT le raster.
#
# Le noyau Rust s'arrete quand il atteint sa destination -- il n'expose donc pas
# directement un champ complet. Mais `dst` n'y sert qu'a un test d'egalite : une
# destination hors grille ne peut jamais etre atteinte, le tas se vide, et le
# `cumcost` retourne couvre alors toutes les cellules accessibles. C'est un
# Dijkstra un-vers-tous obtenu sans toucher au noyau.
#' @noRd
.dsr_champ_cout <- function(sigma, depart, k = 16L, lambda = 0, mu = 0,
                            sigma_min = 0.05) {
  ncell <- terra::ncell(sigma)
  src <- dsr_cellule(sigma, depart) - 1L
  if (is.na(src) || src < 0L || src >= ncell) return(NULL)
  sg <- terra::values(sigma, mat = FALSE)
  if (is.na(sg[src + 1L])) return(NULL)
  r <- pathfinder_anisotrope(
    sg, rep(NA_real_, ncell), rep(0, ncell),
    terra::nrow(sigma), terra::ncol(sigma), terra::res(sigma)[1],
    as.integer(k), lambda, mu, sigma_min,
    as.integer(src), as.integer(ncell) # hors grille : epuisement du tas
  )
  champ <- terra::rast(sigma)
  terra::values(champ) <- r$cumcost
  names(champ) <- "cout"
  champ
}


# Echantillonnage angulaire de l'eventail. Le pas est choisi pour que deux
# directions voisines soient separees d'environ 1,5 cellule a la distance de
# visee : plus fin ne distingue rien de plus, plus grossier saute des
# embranchements.
#' @noRd
.dsr_angles <- function(resolution, portee, fov) {
  pas <- max(1, floor(1.5 * (resolution / portee) * (180 / pi)))
  a <- seq(pas, fov / 2, by = pas)
  c(rev(-a), 0, a) * pi / 180
}


# Points de l'arc de visee, a `portee` metres devant, dans le champ de vision
# centre sur le cap courant.
#' @noRd
.dsr_extremites <- function(centre, angles, portee, cap) {
  cbind(x = centre[1] + portee * cos(cap + angles),
        y = centre[2] + portee * sin(cap + angles))
}


#' @noRd
.dsr_moyenne_mobile <- function(x, n) {
  if (n <= 1L) return(x)
  demi <- n %/% 2L
  n_x <- length(x)
  idx <- seq_len(n_x)
  vapply(idx, function(i) {
    j <- max(1L, i - demi):min(n_x, i + demi)
    mean(x[j])
  }, numeric(1))
}


# Minima du profil de cout angulaire : ou la route continue, et ou elle bifurque.
#
# Le profil est lisse deux fois avant recherche des creux, sinon le bruit du
# raster fabrique un embranchement tous les trois degres. Chaque creux est
# ensuite RECALE sur le minimum du cout brut dans ses bornes -- le lissage
# deplace la position du creux, pas le fond.
#
# La PROFONDEUR d'un creux (ecart entre les epaules et le fond) sert a moduler
# le cout acceptable : un creux franc dans un profil par ailleurs cher signale
# une route reelle qu'on peut suivre meme a cout eleve, alors qu'un creux mou
# au meme cout n'est que du bruit. Sans cette modulation, l'agent s'arrete a la
# premiere trouee de conductivite.
#' @noRd
.dsr_minima_cout <- function(cout, cout_max) {
  n <- length(cout)
  if (n < 6L) return(NULL)
  fini <- is.finite(cout)
  if (!any(fini)) return(NULL)
  # Les directions inatteignables (NA du raster, reseau existant) ne doivent pas
  # casser le lissage : on les porte a un cout sentinelle tres eleve.
  plafond <- max(99999, if (any(fini)) max(cout[fini]) else 0)
  cout[!fini] <- plafond

  large <- if (n > 36L) 9L else if (n > 18L) 5L else 3L
  liss <- .dsr_moyenne_mobile(.dsr_moyenne_mobile(cout, large), 5L)

  # Creux locaux du profil lisse.
  creux <- which(c(FALSE, liss[-c(1, n)] < liss[-c(n - 1, n)] &
                     liss[-c(1, n)] <= liss[-c(1, 2)], FALSE))
  if (!length(creux)) return(NULL)

  res <- lapply(creux, function(i) {
    # Bornes du creux : on remonte de part et d'autre tant que ca monte.
    g <- i
    while (g > 1L && liss[g - 1L] >= liss[g]) g <- g - 1L
    d <- i
    while (d < n && liss[d + 1L] >= liss[d]) d <- d + 1L
    centre <- which.min(cout[g:d]) + g - 1L
    data.frame(idx = centre, cout = cout[centre],
               profondeur = mean(c(cout[g], cout[d])) - cout[centre])
  })
  res <- do.call(rbind, res)
  res <- res[!duplicated(res$idx), , drop = FALSE]

  # Multiplicateur de cout admissible selon la profondeur : 1 a profondeur 50,
  # 2,5 a partir de 400 (valeurs de vecnet, calibrees sur donnee reelle).
  pente <- (2.5 - 1) / (400 - 50)
  mult <- pmin(1 + (res$profondeur - 50) * pente, 2.5)
  res$cout_relatif <- res$cout / (mult * cout_max)

  garde <- res$cout_relatif <= 1
  res <- if (any(garde)) res[garde, , drop = FALSE] else res[which.min(res$cout), , drop = FALSE]
  res[order(res$cout), , drop = FALSE]
}


# Fenetre de travail d'un pas : le raster recadre sur l'eventail, plancher de
# conductivite applique, trace deja parcourue et reseau existant neutralises,
# et emprises non franchissables rendues maximalement resistantes.
#' @noRd
.dsr_fenetre <- function(sigma, centre, ends, seuil, trace, reseau, tampon,
                         barriere = NULL, barriere_min = NULL) {
  bb <- terra::ext(min(ends[, 1], centre[1]) - 3 * tampon,
                   max(ends[, 1], centre[1]) + 3 * tampon,
                   min(ends[, 2], centre[2]) - 3 * tampon,
                   max(ends[, 2], centre[2]) + 3 * tampon)
  bb <- terra::intersect(bb, terra::ext(sigma))
  if (is.null(bb)) return(NULL)
  f <- terra::crop(sigma, bb)
  if (terra::ncell(f) < 4L) return(NULL)

  # Plancher de conductivite : une cellule nulle rendrait le cout infini et
  # interdirait de franchir la moindre trouee, ce qui est precisement ce que
  # l'agent doit savoir faire.
  #
  # Les NA, eux, RESTENT infranchissables. Une trouee de detection (valeur
  # basse) et une absence de donnee (NA) ne sont pas la meme chose : hors
  # emprise, hors corridor, hors dalle, il n'y a rien a suivre. Les ramener au
  # plancher -- ce que fait vecnet, ou une conductivite nulle donne malgre tout
  # un cout infini -- laisserait l'agent sortir de l'emprise qu'on lui a fixee.
  f[!is.na(f) & f < seuil] <- seuil

  # Emprise non franchissable (sous-etage referme) : ramenee au plancher, donc
  # maximalement resistante SANS devenir infranchissable.
  #
  # Le choix du plancher plutot que du NA n'est pas cosmetique. L'agent tire sa
  # valeur de sa capacite a franchir une trouee quand la route reprend derriere
  # (voir trouee_max) ; un NA lui interdirait de traverser vingt metres de
  # ronces pour retrouver une piste degagee, et hacherait le reseau en morceaux
  # a chaque fourre. Le plancher penalise sans interdire, et laisse le
  # mecanisme de trouee arbitrer sur la LONGUEUR du passage difficile.
  #
  # C'est aussi, exactement, ce que faisait l'ancien poids surf = 2 de
  # dsr_indice_detection() : il ne posait pas de barriere, il tirait les valeurs
  # vers le bas la ou le sous-etage est ferme. L'effet etait utile mais
  # accidentel -- une ponderation de DETECTION jouait une regle de
  # FRANCHISSABILITE. On le rend explicite ici, ou il a sa place.
  if (!is.null(barriere)) {
    b <- terra::crop(barriere, terra::ext(f))
    if (terra::ncell(b) == terra::ncell(f)) {
      bv <- terra::values(b, mat = FALSE)
      f[!is.na(bv) & bv < barriere_min] <- seuil
    }
  }

  # Le reseau deja connu est INFRANCHISSABLE (NA) : c'est ce qui permet de
  # detecter qu'on l'a rejoint, le cout devenant inatteignable de ce cote.
  if (!is.null(reseau) && length(reseau)) {
    m <- sf::st_buffer(sf::st_geometry(reseau), tampon)
    f <- terra::mask(f, terra::vect(m), inverse = TRUE, updatevalue = NA)
  }
  # La trace deja parcourue est ramenee au plancher, ce qui interdit a l'agent
  # de repartir sur ses pas et de boucler.
  #
  # Bouts PLATS et non arrondis : un tampon arrondi deborderait de `tampon`
  # metres au-dela du dernier point parcouru, c'est-a-dire pile sur la portion
  # de route que l'agent s'apprete a emprunter. L'appelant exclut par ailleurs
  # le segment courant (voir dsr_conduire) pour que le voisinage immediat de la
  # position reste intact : sans cela la cellule de depart devient tres
  # resistante et gonfle le cout de toutes les directions a la fois.
  if (!is.null(trace)) {
    m <- sf::st_buffer(trace, tampon, endCapStyle = "FLAT")
    f <- terra::mask(f, terra::vect(m), inverse = TRUE, updatevalue = seuil / 10)
  }
  f
}


#' Suivre une route depuis une amorce (agent conducteur)
#'
#' Vectorise une route en la **parcourant** : depuis une amorce orientee, l'agent
#' avance par pas, regarde en eventail devant lui, et part vers la direction la
#' moins couteuse. Reimplementation terra/sf de l'algorithme de vecnet
#' (Roussel *et al.* 2023) adossee au noyau Rust du paquet.
#'
#' @details
#' **Ce que cette fonction fait et que [dsr_pathfinder()] ne fait pas.** Le
#' pathfinder relie deux points connus. L'agent ne sait pas ou il va : il suit
#' la conductivite. Il en decoule deux proprietes que le squelette et le
#' pathfinder n'ont pas :
#'
#' * **robustesse aux trouees** -- une coupure de conductivite est franchie si
#'   la route reprend derriere, parce que le cout admissible est module par la
#'   *profondeur* du creux dans le profil angulaire et non par sa seule valeur ;
#' * **decouverte des embranchements** -- les directions ecartees a chaque pas
#'   sont autant d'amorces, rendues dans `amorces`, a repasser a la fonction
#'   pour explorer le reseau de proche en proche.
#'
#' **Arret.** L'agent s'arrete quand il rejoint `reseau`, quand aucune direction
#' n'est admissible, quand il sort de l'emprise, quand il a roule trop longtemps
#' au-dessus du cout maximal (`trouee_max` fois la portee), ou apres `max_pas`
#' pas.
#'
#' **Suivre une carte et etre arrete par une autre.** `sigma` dit ou aller,
#' `franchissabilite` dit ou l'on ne passe plus. C'est la separation posee par
#' le BRIEF section 3.4 -- `sigma_geo` porte l'empreinte, `sigma_surf` porte
#' l'etat present -- appliquee au conducteur : il suit l'empreinte et se fait
#' freiner par l'etat, au lieu de suivre un melange des deux.
#'
#' Cette separation a ete introduite apres une mesure. `dsr_indice_detection()`
#' ponderait le canal de surface a 2 ; ramene a sa valeur mesuree (0,5), la
#' carte s'ameliore nettement (AUC 0,698 -> 0,738) et le vectoriseur par
#' squelette avec elle, mais l'agent, lui, se degrade -- il divague, son ecart
#' median a la reference passant de 3,3 a 5,2 m. L'explication tient en une
#' phrase : l'ancien poids ecrasait la carte partout ou le sous-etage est
#' ferme, ce qui **retenait** l'agent. Ce garde-fou etait reel mais accidentel,
#' et il se payait d'une carte de detection degradee. Passer `franchissabilite`
#' le retablit la ou il doit etre, sans rien devoir a la ponderation de la
#' detection.
#'
#' **Ce que `franchissabilite_min = 0.4` fait vraiment.** Pas ce que son nom
#' laisse croire. Avec les regles par defaut de [dsr_specs_surface()], les
#' bornes d'appartenance sont laissees a `NULL`, donc derivees des quantiles :
#' `a` est la **mediane** du canal et `b` son 95e centile
#' ([dsr_appartenance()]). Il en decoule que la moitie des cellules ont, par
#' construction, `mu(taux_penetration) = 0` -- ramene au plancher `sigma_min`
#' -- et `mu(densite_sousetage) = 1`. Leur fusion vaut alors
#' `exp((2 * log(1) + log(0.05)) / 3) = 0.368`, et `sigma_surf` presente un mode
#' massif a cette valeur : 50 % des cellules sur wsfi, 34 % sur ltcp.
#'
#' Le seuil de 0,4 se place juste au-dessus de ce mode. Il ne mesure donc pas
#' une fermeture de sous-etage : il selectionne les cellules dont le **taux de
#' penetration depasse sa propre mediane**. C'est un critere de RANG deguise en
#' valeur absolue, et physiquement il dit « ne pas circuler la ou le lidar ne
#' voit pas le sol ».
#'
#' Cette lecture a une consequence pratique heureuse : le seuil se transporte
#' d'un massif a l'autre bien mieux qu'un seuil absolu ne le devrait. Le taux de
#' penetration brut vaut 0,04 sur wsfi et 0,31 sur ltcp -- un facteur 7 -- et le
#' meme 0,4 convient aux deux, parce que la normalisation par quantiles absorbe
#' l'ecart en amont. Elle a aussi une consequence genante, a garder en tete :
#' fixer `a` et `b` explicitement dans `specs` deplace le mode et **invalide le
#' defaut de 0,4**.
#'
#' Le balayage complet (`dev/07_calibrer_franchissabilite.R`, 8 seuils sur deux
#' massifs) donne des F1 indiscernables entre 0,375 et 0,45. Ce qui compte n'est
#' pas la valeur mais le COTE du mode : au-dessus, l'ecart median a la reference
#' tombe a 2,1-3,1 m sur les deux massifs ; en dessous, il remonte a 4,4-11,2 m.
#'
#' @param sigma Conductivite (`SpatRaster` mono-couche), typiquement la sortie de
#'   [dsr_conductivite()] ou une carte de probabilite. `NA` admis.
#' @param amorce Amorce orientee : un `LINESTRING` `sf`/`sfc`. Son dernier point
#'   est la position de depart, sa direction donne le cap initial.
#' @param reseau Reseau deja vectorise (`sf`/`sfc`), rendu infranchissable :
#'   l'agent s'arrete en le rejoignant. `NULL` (defaut) pour aucun.
#' @param portee Distance de visee, en metres. Defaut 100.
#' @param fov Champ de vision total, en degres. Defaut 160.
#' @param conductivite_min Conductivite en deca de laquelle une direction n'est
#'   plus consideree comme roulable. Fixe le cout maximal admissible
#'   (`portee / conductivite_min`). Defaut 0.6.
#' @param franchissabilite `SpatRaster` **aligne sur `sigma`** disant ou
#'   l'emprise est encore degagee -- typiquement [dsr_sigma_surf()]. Les cellules
#'   sous `franchissabilite_min` deviennent maximalement resistantes sans
#'   devenir infranchissables. `NULL` (defaut) pour ne poser aucune contrainte.
#'   Voir les details.
#' @param franchissabilite_min Seuil sous lequel une cellule est tenue pour
#'   refermee. Defaut 0.4. Sans effet si `franchissabilite` est `NULL`. Ce que
#'   ce chiffre fait reellement est explique dans les details -- ce n'est pas
#'   tout a fait ce qu'il annonce.
#' @param seuil Plancher de conductivite applique a la fenetre de travail.
#'   Defaut 0.1.
#' @param tampon Demi-largeur (m) de neutralisation du reseau et de la trace
#'   deja parcourue. Defaut 10.
#' @param avance Fraction de la portee effectivement parcourue a chaque pas.
#'   Defaut 0.8 : avancer de la portee entiere ferait manquer les
#'   embranchements situes juste avant le point vise.
#' @param trouee_max Longueur maximale de trouee toleree, en multiples de la
#'   portee. Defaut 2.5.
#' @param max_pas Nombre maximal de pas. Defaut 500.
#'
#' @return Une liste : `route` (`sfc` `LINESTRING`, l'amorce comprise),
#'   `amorces` (`sfc` des embranchements rencontres, ou `NULL`), `n_pas`,
#'   `arret` (motif d'arret) et `n_troncons`, le nombre de pas reellement
#'   parcourus, amorce exclue. **`n_troncons == 0` signifie que l'agent n'a pas
#'   pu avancer** : `route` n'est alors que l'amorce rendue telle quelle, et non
#'   une route decouverte.
#' @seealso [dsr_pathfinder()], [dsr_vectoriser()], [dsr_reseau()].
#' @examples
#' # Carte synthetique : une route rectiligne de conductivite 1 sur fond a 0.1.
#' r <- terra::rast(nrows = 100, ncols = 100, xmin = 0, xmax = 200,
#'   ymin = 0, ymax = 200, crs = "EPSG:2154")
#' terra::values(r) <- 0.1
#' xy <- terra::xyFromCell(r, seq_len(terra::ncell(r)))
#' r[abs(xy[, 2] - 100) < 4] <- 1
#' amorce <- sf::st_sfc(sf::st_linestring(cbind(c(10, 25), c(100, 100))),
#'   crs = "EPSG:2154")
#' ans <- dsr_conduire(r, amorce, portee = 40)
#' ans$arret
#' @export
dsr_conduire <- function(sigma, amorce, reseau = NULL, portee = 100, fov = 160,
                         conductivite_min = 0.6, seuil = 0.1, tampon = 10,
                         avance = 0.8, trouee_max = 2.5, max_pas = 500,
                         franchissabilite = NULL, franchissabilite_min = 0.4) {
  if (!inherits(sigma, "SpatRaster")) {
    dsr_abort("{.arg sigma} doit etre un {.cls SpatRaster}.")
  }
  if (terra::nlyr(sigma) > 1L) sigma <- sigma[[1]]
  if (!is.null(franchissabilite)) {
    if (!inherits(franchissabilite, "SpatRaster")) {
      dsr_abort("{.arg franchissabilite} doit etre un {.cls SpatRaster} (p. ex. {.fun dsr_sigma_surf}).")
    }
    if (terra::nlyr(franchissabilite) > 1L) franchissabilite <- franchissabilite[[1]]
    # Le recadrage par pas suppose une geometrie identique : le verifier une
    # fois ici vaut mieux que de laisser chaque fenetre echouer en silence.
    if (!terra::compareGeom(sigma, franchissabilite, stopOnError = FALSE)) {
      dsr_abort(c(
        "{.arg franchissabilite} doit etre aligne sur {.arg sigma}.",
        "i" = "Les deux rasters doivent partager grille, emprise et CRS ; voir {.fun dsr_grille_reference}."
      ))
    }
  }
  geom <- sf::st_geometry(amorce)
  if (!inherits(geom[[1]], "LINESTRING")) {
    dsr_abort("{.arg amorce} doit etre un {.cls LINESTRING} : sa direction donne le cap initial.")
  }
  crs <- sf::st_crs(geom)
  resolution <- terra::res(sigma)[1]

  co <- sf::st_coordinates(geom)[, 1:2, drop = FALSE]
  n_co <- nrow(co)
  position <- co[n_co, ]
  # Cap pris sur la seconde moitie de l'amorce : le tout premier segment d'une
  # amorce courte est trop bruite pour donner une direction fiable.
  ref <- co[max(1L, n_co %/% 2L), ]
  cap <- atan2(position[2] - ref[2], position[1] - ref[1])

  cout_max <- portee / conductivite_min
  segments <- list(co)
  amorces <- list()
  trouee <- 0
  n_surcout <- 0L
  arret <- "max_pas"
  pas <- 0L

  for (pas in seq_len(max_pas)) {
    portee_c <- portee
    fen <- NULL
    ends <- NULL

    # Reduction de la portee si l'eventail deborde de l'emprise utile.
    for (essai in 1:3) {
      angles <- .dsr_angles(resolution, portee_c, fov)
      ends <- .dsr_extremites(position, angles, portee_c, cap)
      # Le segment courant est exclu du masque : il touche la position, et le
      # masquer rendrait la cellule de depart quasi infranchissable.
      trace <- if (length(segments) > 1L) {
        sf::st_sfc(sf::st_linestring(do.call(rbind, segments[-length(segments)])), crs = crs)
      } else NULL
      fen <- .dsr_fenetre(sigma, position, ends, seuil, trace, reseau, tampon,
        barriere = franchissabilite, barriere_min = franchissabilite_min)
      # Le test porte sur `sigma` et non sur la fenetre : dans la fenetre, le
      # reseau existant est masque en NA, et le confondre avec un bord d'emprise
      # ferait sortir l'agent par « hors_emprise » juste avant de le rejoindre.
      if (!is.null(fen)) {
        if (all(!is.na(terra::extract(sigma, ends)[, 1]))) break
      }
      portee_c <- portee_c / 2
      if (portee_c < 4 * resolution) { fen <- NULL; break }
    }
    if (is.null(fen)) { arret <- "hors_emprise"; break }

    champ <- .dsr_champ_cout(fen, position)
    if (is.null(champ)) { arret <- "depart_infranchissable"; break }
    cout <- terra::extract(champ, ends)[, 1]

    # Une seule direction inatteignable suffit a signaler le reseau existant :
    # a ce stade toutes les extremites sont dans l'emprise de `sigma` (teste
    # ci-dessus), et seul le masque du reseau y introduit des NA. On raccourcit
    # alors la visee pour s'arreter au plus pres, comme le fait vecnet, plutot
    # que de stopper des que l'eventail effleure le reseau a pleine portee.
    if (!is.null(reseau) && length(reseau) && any(!is.finite(cout))) {
      while (portee_c > 4 * resolution && any(!is.finite(cout))) {
        portee_c <- portee_c / 2
        angles <- .dsr_angles(resolution, portee_c, fov)
        ends <- .dsr_extremites(position, angles, portee_c, cap)
        cout <- terra::extract(champ, ends)[, 1]
      }
      if (any(!is.finite(cout))) { arret <- "reseau_rejoint"; break }
    }
    if (all(!is.finite(cout))) { arret <- "aucune_direction"; break }

    mins <- .dsr_minima_cout(cout, cout_max * portee_c / portee)
    if (is.null(mins)) { arret <- "aucune_direction"; break }

    cible <- ends[mins$idx[1], ]
    chemin <- tryCatch(
      dsr_pathfinder(fen, position, cible, lambda = 0, mu = 0, sigma_min = seuil / 10),
      error = function(e) NULL
    )
    if (is.null(chemin)) { arret <- "chemin_introuvable"; break }

    xy <- sf::st_coordinates(chemin$trace)[, 1:2, drop = FALSE]
    garde <- max(2L, floor(nrow(xy) * avance))
    xy <- xy[seq_len(garde), , drop = FALSE]

    # Les autres creux du profil sont des embranchements : on ne les suit pas,
    # on les memorise comme amorces. Ecartes de moins de 15 degres de la
    # direction principale, ce sont des doublons du meme axe.
    if (nrow(mins) > 1L) {
      ecart <- abs(angles[mins$idx[-1]] - angles[mins$idx[1]]) * 180 / pi
      autres <- mins$idx[-1][ecart > 15]
      for (j in autres) {
        amorces[[length(amorces) + 1L]] <- sf::st_linestring(
          rbind(position, position + 0.35 * portee_c *
                  c(cos(cap + angles[j]), sin(cap + angles[j])))
        )
      }
    }

    # Rouler au-dessus du cout maximal est tolere, mais pas indefiniment : c'est
    # ce qui permet de franchir une trouee sans partir dans le hors-piste.
    if (mins$cout_relatif[1] > 1) {
      trouee <- trouee + portee_c
      n_surcout <- n_surcout + 1L
      if (trouee > trouee_max * portee) {
        segments[[length(segments) + 1L]] <- xy[-1, , drop = FALSE]
        arret <- "trouee_trop_longue"
        break
      }
    } else {
      trouee <- 0
      n_surcout <- 0L
    }

    segments[[length(segments) + 1L]] <- xy[-1, , drop = FALSE]
    n_xy <- nrow(xy)
    position <- xy[n_xy, ]
    ref <- xy[max(1L, n_xy - 3L), ]
    cap <- atan2(position[2] - ref[2], position[1] - ref[1])
  }

  # Les derniers pas roules en surcout n'ont mene nulle part : c'est la trouee
  # dans laquelle l'agent s'est engage avant d'abandonner. Les garder ferait
  # sortir une route la ou la donnee n'en montre pas. L'amorce est toujours
  # conservee.
  if (n_surcout > 0L && length(segments) > 1L) {
    segments <- segments[seq_len(max(1L, length(segments) - n_surcout))]
  }
  route <- sf::st_sfc(sf::st_linestring(do.call(rbind, segments)), crs = crs)
  am <- if (length(amorces)) sf::st_sfc(amorces, crs = crs) else NULL
  # `n_troncons` compte ce qui a REELLEMENT ete parcouru, amorce exclue. Un
  # agent qui n'a jamais pu avancer rend son amorce telle quelle : ce n'est pas
  # une route decouverte, et l'appelant doit pouvoir le distinguer.
  list(route = route, amorces = am, n_pas = pas, arret = arret,
       n_troncons = length(segments) - 1L)
}


#' Amorces d'exploration pour l'agent conducteur
#'
#' Fabrique les amorces orientees dont [dsr_conduire()] a besoin pour demarrer,
#' a partir de deux sources complementaires.
#'
#' @details
#' **Depuis la reference (recommande).** Les extremites libres du reseau deja
#' connu -- typiquement la BD TOPO -- sont les meilleures amorces qui soient :
#' elles pointent exactement la ou la desserte cartographiee s'arrete, donc la
#' ou commence celle qui manque. C'est le cas d'usage central du paquet, et il
#' n'a pas d'equivalent dans vecnet, qui ne dispose d'aucune reference.
#'
#' **Depuis la bordure.** A defaut de reference, on cherche les endroits ou une
#' conductivite forte touche le bord de l'emprise : une route qui entre dans la
#' dalle. vecnet obtient le meme resultat en faisant rouler un agent le long
#' d'un contour interieur ; le balayage direct du bord donne la meme chose sans
#' le detour.
#'
#' Les routes entierement interieures a l'emprise et sans lien avec la reference
#' ne sont atteintes par aucune des deux sources : elles le seront par
#' propagation, l'agent rendant a chaque pas les embranchements rencontres.
#'
#' @param p Conductivite (`SpatRaster` mono-couche).
#' @param reference Reseau connu (`sf`/`sfc`), ou `NULL`.
#' @param seuil Conductivite minimale pour qu'un point de bordure amorce une
#'   exploration. Defaut 0.6.
#' @param longueur Longueur des amorces produites, en metres. Defaut 20.
#' @param bordure Chercher aussi les entrees de route sur le bord de l'emprise.
#'   Defaut `TRUE`.
#'
#' @return Un `sfc` de `LINESTRING` orientes vers l'interieur, ou `NULL`.
#' @seealso [dsr_conduire()], [dsr_vectoriser()].
#' @examples
#' r <- terra::rast(nrows = 50, ncols = 50, xmin = 0, xmax = 100, ymin = 0,
#'   ymax = 100, crs = "EPSG:2154")
#' terra::values(r) <- 0.1
#' xy <- terra::xyFromCell(r, seq_len(terra::ncell(r)))
#' r[abs(xy[, 2] - 50) < 3] <- 1
#' length(dsr_amorces(r))
#' @export
dsr_amorces <- function(p, reference = NULL, seuil = 0.6, longueur = 20,
                        bordure = TRUE) {
  if (!inherits(p, "SpatRaster")) dsr_abort("{.arg p} doit etre un {.cls SpatRaster}.")
  if (terra::nlyr(p) > 1L) p <- p[[1]]
  crs <- sf::st_crs(terra::crs(p))
  e <- terra::ext(p)
  res <- terra::res(p)[1]
  out <- list()

  # 1. Extremites libres de la reference : les bouts de route connus.
  if (!is.null(reference) && length(sf::st_geometry(reference))) {
    g <- sf::st_geometry(reference)
    for (i in seq_along(g)) {
      co <- sf::st_coordinates(g[i])[, 1:2, drop = FALSE]
      n <- nrow(co)
      if (n < 2L) next
      # Une amorce a chaque bout, orientee vers l'exterieur du troncon.
      for (bout in list(list(p = co[1, ], q = co[min(2L, n), ]),
                        list(p = co[n, ], q = co[max(1L, n - 1L), ]))) {
        d <- bout$p - bout$q
        nd <- sqrt(sum(d^2))
        if (!is.finite(nd) || nd == 0) next
        d <- d / nd
        out[[length(out) + 1L]] <- sf::st_linestring(
          rbind(bout$p - longueur * d, bout$p))
      }
    }
  }

  # 2. Entrees de route sur le bord de l'emprise.
  if (isTRUE(bordure)) {
    marge <- 2 * res
    cotes <- list(
      list(fixe = "y", v = e[3] + marge, sens = c(0, 1)),   # bas  -> vers le nord
      list(fixe = "y", v = e[4] - marge, sens = c(0, -1)),  # haut -> vers le sud
      list(fixe = "x", v = e[1] + marge, sens = c(1, 0)),   # ouest -> vers l'est
      list(fixe = "x", v = e[2] - marge, sens = c(-1, 0))   # est  -> vers l'ouest
    )
    for (co in cotes) {
      s <- if (co$fixe == "y") {
        seq(e[1] + marge, e[2] - marge, by = res)
      } else {
        seq(e[3] + marge, e[4] - marge, by = res)
      }
      pts <- if (co$fixe == "y") cbind(s, co$v) else cbind(co$v, s)
      val <- terra::extract(p, pts)[, 1]
      fort <- !is.na(val) & val >= seuil
      if (!any(fort)) next
      # Une amorce par plage contigue : une route large ne doit pas en produire
      # une par cellule.
      grp <- cumsum(c(1L, diff(which(fort)) != 1L))
      for (k in unique(grp)) {
        idx <- which(fort)[grp == k]
        c0 <- pts[idx[length(idx) %/% 2L + 1L], ]
        out[[length(out) + 1L]] <- sf::st_linestring(
          rbind(c0 - longueur * co$sens, c0))
      }
    }
  }

  if (!length(out)) return(NULL)
  g <- sf::st_sfc(out, crs = crs)

  # Une amorce dont le point de depart tombe hors donnee (hors emprise, hors
  # corridor, hors dalle) n'est pas conduisible. Le cas n'est pas theorique :
  # un troncon de reference qui deborde de l'emprise d'analyse a son extremite
  # au-dela, et produirait une amorce inerte.
  depart <- t(vapply(g, function(l) l[nrow(l), 1:2], numeric(2)))
  dedans <- !is.na(terra::extract(p, depart)[, 1])
  if (!any(dedans)) return(NULL)
  g[dedans]
}


# Sinuosite : longueur parcourue rapportee a la distance a vol d'oiseau. Une
# route qui serpente exagerement est le signe que l'agent a suivi du bruit et
# non un lineaire.
#' @noRd
.dsr_sinuosite <- function(g) {
  co <- sf::st_coordinates(g)[, 1:2, drop = FALSE]
  n <- nrow(co)
  if (n < 2L) return(Inf)
  direct <- sqrt(sum((co[n, ] - co[1, ])^2))
  if (direct <= 0) return(Inf)
  as.numeric(sf::st_length(g)) / direct
}


# Exploration de proche en proche : on conduit depuis chaque amorce, on retient
# les routes assez longues et pas trop sinueuses, et les embranchements
# rencontres deviennent les amorces du tour suivant. Le reseau deja trouve est
# passe a l'agent, qui s'y arrete : c'est ce qui fait converger la boucle et
# garantit qu'un axe n'est pas parcouru deux fois.
#' @noRd
.dsr_vectoriser_agent <- function(p, long_min, reference, seuil = 0.6,
                                  sinuosite_max = 1.8, max_tours = 10L, ...) {
  amorces <- dsr_amorces(p, reference, seuil = seuil)
  if (is.null(amorces)) return(list())

  reseau <- if (is.null(reference)) NULL else sf::st_geometry(reference)
  trouve <- list()

  for (tour in seq_len(max_tours)) {
    suivantes <- list()
    for (i in seq_along(amorces)) {
      a <- tryCatch(dsr_conduire(p, amorces[i], reseau = reseau, ...),
        error = function(e) NULL)
      if (is.null(a)) next
      # L'agent n'a pas bouge : il rend son amorce, qui n'est pas une decouverte.
      if (a$n_troncons < 1L) next
      lg <- as.numeric(sf::st_length(a$route))
      if (!is.finite(lg) || lg < long_min) next
      if (.dsr_sinuosite(a$route) > sinuosite_max) next

      trouve[[length(trouve) + 1L]] <- a$route[[1]]
      reseau <- if (is.null(reseau)) a$route else c(reseau, a$route)
      if (!is.null(a$amorces)) {
        suivantes <- c(suivantes, lapply(seq_along(a$amorces),
          function(j) a$amorces[[j]]))
      }
    }
    if (!length(suivantes)) break
    amorces <- sf::st_sfc(suivantes, crs = sf::st_crs(amorces))
  }

  trouve
}
