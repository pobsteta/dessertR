# Cubature deblai / remblai le long d'un trace (dev/SPEC_CUBATURE.md).
#
# Methode reimplementee d'apres CubaRoad (Sylvain Dupire, SylvaLab / ONF Pole RDI
# Chambery, 2021, GPL-3) -- reimplementee, pas portee : voir les deux ecarts
# assumes plus bas (recherche d'intersection par changement de signe, et
# vectorisation du profil theorique).
#
# Principe, par profil transversal : on ancre le profil theorique de la route non
# pas sur l'axe -- qui n'est pas a l'altitude du terrain -- mais sur le POINT DE
# NIVEAU, le point du profil ou le terrain croise l'altitude de plateforme. De
# part et d'autre on pose la plateforme, puis un talus amont et un talus aval
# prolonges jusqu'a retrouver le terrain. L'aire entre terrain et route donne les
# sections en deblai et en remblai ; multipliees par la longueur applicable,
# les volumes.
#
# Le partage deblai / remblai n'est pas fixe : c'est le RIPAGE (section 2.3 de la
# spec) qui l'arbitre selon le devers. Pente douce, on equilibre ; pente raide,
# le remblai ne tient pas et tout passe en deblai.


# Paliers de durcissement du talus, en pente (1 = 100 %). Quand un talus ne
# recoupe jamais le terrain, le prolonger indefiniment fait diverger le volume :
# on durcit par paliers jusqu'a intersection. Un talus a 400 % est un aveu
# d'echec du modele sur ce point, pas un resultat -- d'ou le drapeau `forcee`.
#' @noRd
DSR_PALIERS_TALUS <- c(0.67, 1, 1.5, 4)

# Demi-fenetre de mesure du devers de part et d'autre du point de niveau, en
# metres. Valeur de CubaRoad : assez large pour ignorer la micro-topographie du
# bord, assez etroite pour rester sur le meme versant.
#' @noRd
DSR_FENETRE_DEVERS <- 6


# Point de niveau : le point du profil dont l'altitude egale celle de la
# plateforme, cherche d'abord dans `tol_xy` autour de l'axe, puis dans
# `tol_xy + largeur / 2`. Retourne aussi la configuration (section 2.2 de la
# spec) quand il n'existe pas : la plateforme est alors entierement sous le
# terrain (tout en deblai) ou entierement au-dessus (tout en remblai).
#' @noRd
.dsr_point_niveau <- function(offsets, z, z_plat, largeur, tol_xy = NULL,
                              tol_z = 0.05) {
  if (is.null(tol_xy)) tol_xy <- 0.5 * largeur
  i_axe <- which.min(abs(offsets))

  chercher <- function(rayon) {
    dans <- which(abs(offsets - offsets[i_axe]) <= rayon & is.finite(z))
    if (!length(dans)) return(NA_integer_)
    ok <- dans[abs(z[dans] - z_plat) <= tol_z]
    if (!length(ok)) return(NA_integer_)
    # Le meilleur candidat est celui dont l'ALTITUDE colle le mieux, l'axe ne
    # servant que d'arbitre a egalite. Retenir le plus proche de l'axe parmi
    # tous les points admissibles biaiserait l'ancrage de `tol_z / pente` vers
    # l'axe -- 0,17 m sur un versant a 30 % avec la tolerance par defaut.
    ok[order(abs(z[ok] - z_plat), abs(offsets[ok] - offsets[i_axe]))[1]]
  }

  i <- chercher(tol_xy)
  elargi <- FALSE
  if (is.na(i)) {
    i <- chercher(tol_xy + 0.5 * largeur)
    elargi <- !is.na(i)
  }

  if (!is.na(i)) {
    config <- if (abs(offsets[i] - offsets[i_axe]) < 0.05) 1L else 2L
    return(list(i = i, trouve = TRUE, elargi = elargi, config = config))
  }

  # Aucun point de niveau : cas degeneres. On se rabat sur le point le plus
  # proche en altitude dans la fenetre initiale, et la configuration dit
  # pourquoi le resultat n'est pas un profil mixte ordinaire.
  dans <- which(abs(offsets - offsets[i_axe]) <= tol_xy & is.finite(z))
  if (!length(dans)) return(list(i = NA_integer_, trouve = FALSE, elargi = FALSE, config = NA_integer_))
  i <- dans[which.min(abs(z[dans] - z_plat))]
  config <- if (z[i] > z_plat) 3L else 5L
  list(i = i, trouve = FALSE, elargi = FALSE, config = config)
}


# Devers de part et d'autre du point de niveau, et ripage qui en decoule.
# `cote` vaut -1 si l'amont est du cote des offsets decroissants, +1 s'il est du
# cote croissant, 0 si les deux versants vont dans le meme sens (croupe ou
# thalweg).
#' @noRd
.dsr_ripage <- function(offsets, z, i_niv, z_plat, ripage_min = 0.35,
                        ripage_max = 0.60, fenetre = DSR_FENETRE_DEVERS) {
  o_niv <- offsets[i_niv]
  pente_vers <- function(signe) {
    cible <- o_niv + signe * fenetre
    j <- which.min(abs(offsets - cible))
    d <- abs(offsets[j] - o_niv)
    if (d < 1e-9 || !is.finite(z[j])) return(NA_real_)
    (z[j] - z_plat) / d
  }
  p_g <- pente_vers(-1)
  p_d <- pente_vers(+1)
  if (!is.finite(p_g) || !is.finite(p_d)) {
    return(list(cote = 0L, ripage = 0, forme = "indetermine", pente_g = p_g, pente_d = p_d))
  }

  # Les deux versants descendent -> croupe, la plateforme est en remblai des deux
  # cotes. Les deux montent -> thalweg, elle est en deblai des deux cotes. Dans
  # les deux cas le ripage ne s'applique pas : rien a arbitrer.
  if (max(p_g, p_d) < 0) return(list(cote = 0L, ripage = 0, forme = "croupe", pente_g = p_g, pente_d = p_d))
  if (min(p_g, p_d) > 0) return(list(cote = 0L, ripage = 0, forme = "thalweg", pente_g = p_g, pente_d = p_d))

  # Versant : l'amont est le cote qui monte.
  cote <- if (p_g > p_d) -1L else 1L
  amont <- if (cote < 0L) abs(p_g) else abs(p_d)
  aval <- if (cote < 0L) abs(p_d) else abs(p_g)
  # Si le versant AVAL est plus raide que le seuil, c'est lui qui commande : on
  # ne peut pas y asseoir de remblai, donc tout passe en deblai. Sans cette
  # bascule, une route en corniche serait chiffree a moitie en remblai.
  devers <- if (aval < ripage_max) amont else aval

  ripage <- (devers - ripage_min) / (ripage_max - ripage_min)
  ripage <- min(max(ripage, 0), 1)
  list(cote = cote, ripage = ripage, forme = "versant", pente_g = p_g, pente_d = p_d)
}


# Talus depuis un bord de plateforme jusqu'a l'intersection avec le terrain.
#
# ECART ASSUME avec CubaRoad, qui retient le point ou |z_talus - z_terrain| passe
# sous une tolerance : ce critere echoue des que le croisement tombe entre deux
# echantillons, et il depend alors du pas transversal. On retient ici le premier
# CHANGEMENT DE SIGNE de (z_talus - z_terrain), qui est exact au pas pres et ne
# depend d'aucun seuil.
#
# `sens` : -1 vers les offsets decroissants, +1 vers les croissants.
# `montant` : TRUE pour un talus amont (le talus s'eleve en s'eloignant).
#' @noRd
.dsr_talus <- function(offsets, z, i_bord, z_bord, pente, sens, montant,
                       tol_z = 0.05, paliers = DSR_PALIERS_TALUS) {
  n <- length(offsets)
  vide <- list(idx = integer(0), z = numeric(0), i_fin = i_bord,
               pente = pente, forcee = FALSE)
  idx <- if (sens < 0) rev(seq_len(i_bord - 1L)) else {
    if (i_bord >= n) integer(0) else seq.int(i_bord + 1L, n)
  }
  if (!length(idx)) return(vide)
  # Le bord de plateforme est deja au niveau du terrain : il n'y a rien a
  # terrasser de ce cote. Sans ce garde-fou, un terrain plat -- ou simplement un
  # bord qui tombe au niveau -- fabrique un talus qui court jusqu'au bout du
  # profil sans jamais recouper le sol, et donc un volume entierement fictif.
  if (is.finite(z[i_bord]) && abs(z_bord - z[i_bord]) <= tol_z) return(vide)
  d <- abs(offsets[idx] - offsets[i_bord])

  essayer <- function(p, mont) {
    zt <- z_bord + (if (mont) 1 else -1) * p * d
    ecart <- zt - z[idx]
    ecart[!is.finite(ecart)] <- NA_real_
    # Premier indice ou l'ecart s'annule ou change de signe par rapport au bord.
    s0 <- sign(ecart[1])
    if (is.na(s0)) return(NULL)
    if (s0 == 0) return(list(k = 1L, zt = zt))
    k <- which(!is.na(ecart) & sign(ecart) != s0)
    if (!length(k)) return(NULL)
    list(k = k[1], zt = zt)
  }

  # Pente nominale, puis durcissement par paliers, puis -- en dernier recours --
  # inversion du sens du talus : sur un profil ou le terrain part du mauvais
  # cote, un talus amont doit devenir descendant pour retrouver le sol.
  for (p in unique(c(pente, paliers[paliers > pente]))) {
    r <- essayer(p, montant)
    if (!is.null(r)) {
      return(list(idx = idx[seq_len(r$k)], z = r$zt[seq_len(r$k)],
                  i_fin = idx[r$k], pente = p, forcee = p != pente))
    }
  }
  r <- essayer(pente, !montant)
  if (!is.null(r)) {
    return(list(idx = idx[seq_len(r$k)], z = r$zt[seq_len(r$k)],
                i_fin = idx[r$k], pente = pente, forcee = TRUE))
  }
  # Aucune intersection : le talus est tronque au bord du profil. Le volume est
  # alors minore -- `forcee` le signale, et `demi_largeur` est a elargir.
  zt <- z_bord + (if (montant) 1 else -1) * pente * d
  list(idx = idx, z = zt, i_fin = idx[length(idx)], pente = pente, forcee = TRUE)
}


# Profil theorique complet de la route sur le profil transversal.
#' @noRd
.dsr_profil_theorique <- function(offsets, z, i_niv, z_plat, largeur, ripage,
                                  cote, forme, s_amont, s_aval, tol_z = 0.05) {
  # Partage de l'assise. Ripage 0 : moitie deblai, moitie remblai. Ripage 1 :
  # tout en deblai. Le carre rend la bascule tardive (section 2.3 de la spec).
  a_deblai <- largeur / 2 * (1 + ripage^2)
  a_remblai <- largeur - a_deblai

  o_niv <- offsets[i_niv]
  if (cote < 0L) {
    o_g <- o_niv - a_deblai
    o_d <- o_niv + a_remblai
  } else if (cote > 0L) {
    o_g <- o_niv - a_remblai
    o_d <- o_niv + a_deblai
  } else {
    o_g <- o_niv - largeur / 2
    o_d <- o_niv + largeur / 2
  }

  i_g <- which.min(abs(offsets - o_g))
  i_d <- which.min(abs(offsets - o_d))

  # Sens des talus. Sur un versant, amont d'un cote et aval de l'autre. Sur une
  # croupe les deux talus descendent, dans un thalweg les deux montent.
  mont_g <- if (forme == "croupe") FALSE else if (forme == "thalweg") TRUE else cote < 0L
  mont_d <- if (forme == "croupe") FALSE else if (forme == "thalweg") TRUE else cote > 0L
  pente_g <- if (mont_g) s_amont else s_aval
  pente_d <- if (mont_d) s_amont else s_aval

  tg <- .dsr_talus(offsets, z, i_g, z_plat, pente_g, sens = -1L, montant = mont_g, tol_z = tol_z)
  td <- .dsr_talus(offsets, z, i_d, z_plat, pente_d, sens = +1L, montant = mont_d, tol_z = tol_z)

  z_route <- z
  z_route[i_g:i_d] <- z_plat
  if (length(tg$idx)) z_route[tg$idx] <- tg$z
  if (length(td$idx)) z_route[td$idx] <- td$z

  list(z_route = z_route, i_g = i_g, i_d = i_d,
       i_deb_g = tg$i_fin, i_deb_d = td$i_fin,
       assise_deblai = a_deblai, assise_remblai = a_remblai,
       talus_g = tg$pente, talus_d = td$pente,
       talus_force = tg$forcee || td$forcee)
}


# Sections, assiettes et emprise, par integration de l'ecart terrain / route.
#' @noRd
.dsr_sections <- function(offsets, z, z_route, pas_travers) {
  ec <- z - z_route
  ec[!is.finite(ec)] <- 0
  deblai <- ec > 0
  remblai <- ec < 0
  modifie <- which(abs(ec) > 1e-9)
  list(
    section_deblai = sum(ec[deblai]) * pas_travers,
    section_remblai = -sum(ec[remblai]) * pas_travers,
    assiette_deblai = sum(deblai) * pas_travers,
    assiette_remblai = sum(remblai) * pas_travers,
    emprise = if (length(modifie)) {
      (max(modifie) - min(modifie) + 1) * pas_travers
    } else 0
  )
}


#' Cubature deblai / remblai le long d'un trace
#'
#' Chiffre, tous les `pas` metres, les volumes de deblai et de remblai qu'exige
#' la mise a un gabarit donne, par construction d'un **profil en travers
#' theorique** confronte au terrain (voir `dev/SPEC_CUBATURE.md`).
#'
#' @details
#' Le profil theorique n'est pas ancre sur l'axe du trace -- qui n'est pas a
#' l'altitude du terrain -- mais sur le **point de niveau**, point du profil ou
#' le terrain croise l'altitude de plateforme. De part et d'autre : la
#' plateforme, puis un talus amont et un talus aval prolonges jusqu'a retrouver
#' le terrain.
#'
#' Le partage de l'assise entre deblai et remblai est arbitre par le **ripage**,
#' interpolation du devers amont entre `ripage_min` et `ripage_max` :
#' `assise_deblai = largeur / 2 * (1 + ripage^2)`. Sur pente douce
#' (`ripage = 0`) deblai et remblai s'equilibrent ; sur pente raide
#' (`ripage = 1`) le remblai ne tient pas et la totalite passe en deblai.
#'
#' **Le terrain est pris tel quel.** Sur un MNT Lidar HD, une route existante est
#' deja creusee : la cubature obtenue est alors celle de l'**ecart au gabarit**
#' (elargissement), pas celle d'une construction sur terrain vierge. C'est le
#' regime utile en France -- [dsr_trafficability()] dit que le grumier ne passe
#' pas, la cubature dit combien pour qu'il passe -- mais la confusion est
#' couteuse : pour chiffrer une construction sur terrain vierge, fournir un MNT
#' dont l'emprise existante a ete comblee.
#'
#' Le **volume a evacuer** n'est pas le volume de deblai : sur un profil
#' equilibre, le deblai est reemploye en remblai sur place. Seuls les profils ou
#' ce reemploi est impossible -- devers superieur a `ripage_max`, ou plateforme
#' entierement sous ou au-dessus du terrain -- sont cumules a l'evacuation.
#'
#' @param trace Un `sf`/`sfc` `LINESTRING`, ou l'element `trace` de
#'   [dsr_pathfinder()].
#' @param mnt Le MNT (`SpatRaster`).
#' @param largeur Largeur de plateforme visee, en metres. Un scalaire, ou un
#'   vecteur d'une valeur par station.
#' @param s_amont,s_aval Pente des talus amont et aval, en pente (`1` = 100 %).
#'   Defauts 1 et 0.6.
#' @param p_rocher Pourcentage de rocher dans le deblai, pour le volume de roche.
#'   Defaut 0.
#' @param pas Espacement des points d'analyse le long du trace, en metres.
#'   Defaut 10.
#' @param demi_largeur Demi-largeur des profils, en metres. Doit couvrir
#'   l'emprise attendue, talus compris. Defaut 20.
#' @param pas_travers Pas d'echantillonnage transversal, en metres. Defaut 0.05 ;
#'   au-dela de 0.1 les sections sont sensiblement biaisees.
#' @param ripage_min,ripage_max Devers encadrant le ripage. Defauts 0.35 et 0.60.
#' @param tol_z Tolerance altimetrique de detection du point de niveau, en
#'   metres. Defaut 0.05.
#' @param tol_xy Rayon de recherche du point de niveau autour de l'axe, en
#'   metres. `NULL` (defaut) : la moitie de `largeur`.
#'
#' @return Une liste : `points` (`sf` `POINT`, une ligne par point d'analyse) et
#'   `resume` (totaux). Colonnes de `points` : `chainage`, `long_applicable`,
#'   `config`, `forme`, `ripage`, `pente_g`, `pente_d`, `assise_deblai`,
#'   `assise_remblai`, `talus_amont`, `talus_aval`, `talus_force`,
#'   `section_deblai`, `section_remblai`, `volume_deblai`, `volume_remblai`,
#'   `volume_evacuer`, `volume_roche`, `assiette_deblai`, `assiette_remblai`,
#'   `emprise`, `surface_emprise`.
#' @seealso [dsr_profils()], [dsr_measure()], [dsr_emprise_certu()].
#' @examples
#' mnt <- terra::rast(nrows = 200, ncols = 200, xmin = 0, xmax = 100,
#'   ymin = 0, ymax = 100, crs = "EPSG:2154")
#' # Versant regulier a 30 %, pente vers l'est.
#' terra::values(mnt) <- terra::xFromCell(mnt, seq_len(terra::ncell(mnt))) * 0.3
#' tr <- sf::st_sfc(sf::st_linestring(cbind(c(50, 50), c(10, 90))),
#'   crs = "EPSG:2154")
#' cub <- dsr_cubature(tr, mnt, largeur = 4, pas = 10)
#' cub$resume
#' @export
dsr_cubature <- function(trace, mnt, largeur, s_amont = 1, s_aval = 0.6,
                         p_rocher = 0, pas = 10, demi_largeur = 20,
                         pas_travers = 0.05, ripage_min = 0.35,
                         ripage_max = 0.60, tol_z = 0.05, tol_xy = NULL) {
  if (!is.numeric(largeur) || any(!is.finite(largeur)) || any(largeur <= 0)) {
    dsr_abort("{.arg largeur} doit etre un ou des nombres strictement positifs.")
  }
  if (ripage_min >= ripage_max) {
    dsr_abort("{.arg ripage_min} ({ripage_min}) doit etre inferieur a {.arg ripage_max} ({ripage_max}).")
  }
  if (pas_travers > 0.1) {
    dsr_inform(c("!" = "{.arg pas_travers} = {pas_travers} m : les sections seront biaisees.",
                 "i" = "Une valeur <= 0.05 m est recommandee."))
  }

  pr <- dsr_profils(trace, mnt, pas = pas, demi_largeur = demi_largeur,
                    pas_travers = pas_travers)
  offsets <- pr$offsets
  ns <- nrow(pr$z)
  largeur <- rep_len(largeur, ns)
  s_amont <- rep_len(s_amont, ns)
  s_aval <- rep_len(s_aval, ns)
  p_rocher <- rep_len(p_rocher, ns)

  # Longueur applicable : la moitie de la distance aux stations voisines, de
  # sorte que la somme des longueurs applicables fasse la longueur du trace.
  ch <- pr$stations$chainage
  bornes <- c(ch[1], (ch[-1] + ch[-ns]) / 2, ch[ns])
  long_app <- diff(bornes)

  # Colonnes preallouees plutot qu'un data.frame par station suivi d'un rbind :
  # sur 500 profils, l'assemblage coutait trois fois le calcul lui-meme.
  cols <- c("chainage", "long_applicable", "config", "ripage", "pente_g",
            "pente_d", "assise_deblai", "assise_remblai", "talus_amont",
            "talus_aval", "section_deblai", "section_remblai", "volume_deblai",
            "volume_remblai", "volume_evacuer", "volume_roche",
            "assiette_deblai", "assiette_remblai", "emprise", "surface_emprise")
  num <- matrix(NA_real_, ns, length(cols), dimnames = list(NULL, cols))
  forme <- rep(NA_character_, ns)
  force_talus <- rep(NA, ns)
  garde <- rep(FALSE, ns)
  i_axe <- which.min(abs(offsets))

  for (i in seq_len(ns)) {
    z <- pr$z[i, ]
    if (all(!is.finite(z))) next
    # Altitude de plateforme : le terrain sous l'axe. C'est l'hypothese du
    # regime elargissement -- la plateforme visee passe par le niveau actuel.
    z_plat <- z[i_axe]
    if (!is.finite(z_plat)) next

    pn <- .dsr_point_niveau(offsets, z, z_plat, largeur[i], tol_xy, tol_z)
    if (is.na(pn$i)) next
    rp <- .dsr_ripage(offsets, z, pn$i, z_plat, ripage_min, ripage_max)
    # Plateforme entierement sous ou au-dessus du terrain : le ripage n'a pas
    # de sens, on ne partage rien.
    ripage <- if (pn$trouve) rp$ripage else 0
    pt <- .dsr_profil_theorique(offsets, z, pn$i, z_plat, largeur[i], ripage,
                                rp$cote, rp$forme, s_amont[i], s_aval[i], tol_z)
    sec <- .dsr_sections(offsets, z, pt$z_route, pas_travers)

    # Reemploi sur place impossible -> le deblai part en evacuation.
    devers_max <- suppressWarnings(max(abs(c(rp$pente_g, rp$pente_d)), na.rm = TRUE))
    evacuer <- (!pn$trouve) || (is.finite(devers_max) && devers_max > ripage_max)
    v_deb <- sec$section_deblai * long_app[i]

    num[i, ] <- c(ch[i], long_app[i], pn$config, ripage, rp$pente_g, rp$pente_d,
                  pt$assise_deblai, pt$assise_remblai, pt$talus_g, pt$talus_d,
                  sec$section_deblai, sec$section_remblai, v_deb,
                  sec$section_remblai * long_app[i],
                  if (evacuer) v_deb else 0, v_deb * p_rocher[i] / 100,
                  sec$assiette_deblai, sec$assiette_remblai,
                  sec$emprise, sec$emprise * long_app[i])
    forme[i] <- rp$forme
    force_talus[i] <- pt$talus_force
    garde[i] <- TRUE
  }

  if (!any(garde)) dsr_abort("Aucun profil exploitable : le MNT ne couvre pas le trace.")
  tab <- as.data.frame(num[garde, , drop = FALSE])
  tab$config <- as.integer(tab$config)
  tab$forme <- forme[garde]
  tab$talus_force <- force_talus[garde]
  pts <- sf::st_sf(tab, geometry = sf::st_geometry(pr$stations)[garde])

  resume <- data.frame(
    n_points = nrow(tab),
    longueur = sum(tab$long_applicable),
    volume_deblai = sum(tab$volume_deblai),
    volume_remblai = sum(tab$volume_remblai),
    volume_evacuer = sum(tab$volume_evacuer),
    volume_roche = sum(tab$volume_roche),
    surface_emprise = sum(tab$surface_emprise),
    n_talus_force = sum(tab$talus_force)
  )
  if (resume$n_talus_force > 0) {
    dsr_inform(c("!" = "{resume$n_talus_force} profil{?s} ou le talus a ete durci pour retrouver le terrain.",
                 "i" = "Volumes sous-estimes sur ces points ; elargir {.arg demi_largeur}."))
  }

  list(points = pts, resume = resume)
}
