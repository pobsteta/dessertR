# Classement des lineaires apres detection
# ------------------------------------------------------------------------------
# Ce que dsr_detecter() remonte hors reference, en foret geree, n'est pas
# majoritairement de la desserte : ce sont des cloisonnements d'exploitation et
# des layons. Les traiter comme du bruit serait faux ; les traiter comme des
# routes le serait autant. D'ou une classe a part entiere pour « ceci n'est pas
# une voie de circulation ».
#
# LE BALISAGE VISE. Fil OSM-fr « Layons, cloisonnements d'exploitation en forets
# publiques » (juillet 2026), ou l'ONF decrit exactement notre methode (MNT
# Lidar HD + heatmap) et demande comment baliser. Trois regles en sortent :
#
#   1. un layon n'est pas une voie : `man_made=cutline` (+ sous-type
#      `cutline=loggingmachine|section|border|firebreak|...`), pas `highway=*` ;
#   2. `highway=path` seulement si un sentier s'est REELLEMENT trace dessus, et
#      alors sur le MEME objet -- pas de geometrie dupliquee ;
#   3. `access=*` seulement si une source l'atteste.
#
# SUR LE POINT 3. La regle n'est pas « jamais d'access », elle est « jamais
# INFERE ». Un panneau ne se lit pas dans un MNT : tant que la seule entree est
# le lidar, aucun tag d'acces n'est defendable. Mais une acquisition ulterieure
# -- releve terrain, jumeau numerique portant des photos de panneaux -- fournit
# precisement cette attestation. D'ou l'argument `panneaux` : la fonction sait
# deja emettre `access=*`, elle exige seulement qu'on lui montre la preuve, et
# elle en trace la provenance dans `source:access`.
#
# CE QUI N'EST PAS CLASSE AUTOMATIQUEMENT.
#   - La place de depot. Voir plus bas ; le pare-feu, lui, est desormais classe
#     des lors qu'on fournit `tpi` ET `ndvi` -- jamais sur le seul relief.
#   - La place de depot. Ce n'est pas un lineaire ([dsr_places()] rend des
#     points), et le fil OSM ne donne aucun tag consensuel pour elle.


# Composantes connexes d'une matrice d'adjacence logique.
#' @noRd
.dsr_composantes_adj <- function(adj) {
  n <- nrow(adj)
  lab <- integer(n)
  k <- 0L
  for (i in seq_len(n)) {
    if (lab[i] != 0L) next
    k <- k + 1L
    pile <- i
    while (length(pile)) {
      j <- pile[1]; pile <- pile[-1]
      if (lab[j] != 0L) next
      lab[j] <- k
      pile <- c(pile, which(adj[j, ] & lab == 0L))
    }
  }
  lab
}


#' Regrouper les traces en peignes de paralleles
#'
#' Repere les faisceaux de lineaires **paralleles et regulierement espaces** --
#' la signature d'un cloisonnement d'exploitation, qui n'existe jamais seul.
#'
#' @details
#' **Pourquoi une structure plutot qu'une largeur.** Un cloisonnement se
#' reconnait a son peigne, pas a sa section : les largeurs de cloisonnement
#' varient avec le peuplement et le materiel, et la largeur que mesure
#' [dsr_measure()] est souvent une plateforme (voir `BORDS_CHAUSSEE`). La
#' periodicite, elle, est **estimee sur la donnee** : aucune valeur d'espacement
#' n'est posee a priori, seules les bornes de recherche le sont.
#'
#' La direction d'une trace est prise entre ses extremites, modulo 180 degres.
#' Les traces de direction voisine sont regroupees, projetees sur la normale a
#' la direction moyenne du groupe, puis triees : un peigne est une suite d'au
#' moins `n_min` traces dont les ecarts successifs tiennent dans
#' `[espacement_min, espacement_max]` et ne s'ecartent pas de plus de
#' `regularite` de leur mediane.
#'
#' **Limite assumee** : deux traces colineaires (bout a bout) se projettent au
#' meme endroit ; `espacement_min` les ecarte du peigne plutot que de les
#' compter comme deux dents.
#'
#' @param traces `sf` de `LINESTRING`.
#' @param tol_angle Ecart de direction admis dans un groupe, en degres. Defaut
#'   15.
#' @param espacement_min,espacement_max Bornes de recherche de l'espacement
#'   entre dents, en metres. Defauts 4 et 40.
#' @param n_min Nombre minimal de dents. Defaut 3.
#' @param regularite Ecart relatif maximal a l'espacement median. Defaut 0.5.
#'
#' @return Le `sf` d'entree, augmente de `PEIGNE` (identifiant, `NA` hors
#'   peigne), `PEIGNE_N` (nombre de dents) et `PEIGNE_ESPACEMENT` (m, median).
#' @seealso [dsr_classer()], [dsr_dedupe_paralleles()].
#' @examples
#' g <- lapply(seq(0, 60, by = 20), function(y)
#'   sf::st_linestring(cbind(c(0, 100), c(y, y))))
#' tr <- sf::st_sf(geometry = sf::st_sfc(g, crs = 2154))
#' dsr_peignes(tr)$PEIGNE
#' @export
dsr_peignes <- function(traces, tol_angle = 15, espacement_min = 4,
                        espacement_max = 40, n_min = 3, regularite = 0.5) {
  if (!inherits(traces, "sf")) dsr_abort("{.arg traces} doit etre un {.cls sf}.")
  if (espacement_min >= espacement_max) {
    dsr_abort("{.arg espacement_min} doit etre inferieur a {.arg espacement_max}.")
  }
  g <- sf::st_geometry(traces)
  n <- length(g)
  traces$PEIGNE <- NA_integer_
  traces$PEIGNE_N <- NA_integer_
  traces$PEIGNE_ESPACEMENT <- NA_real_
  if (n < n_min) return(traces)

  co <- lapply(g, function(l) sf::st_coordinates(l)[, 1:2, drop = FALSE])
  ang <- vapply(co, function(m) {
    v <- m[nrow(m), ] - m[1, ]
    ((atan2(v[2], v[1]) * 180 / pi) %% 180 + 180) %% 180
  }, numeric(1))
  cen <- do.call(rbind, lapply(co, colMeans))

  # Distance angulaire modulo 180 : 179 et 1 degres designent la meme direction.
  d <- outer(ang, ang, function(a, b) {
    x <- abs(a - b) %% 180
    pmin(x, 180 - x)
  })
  grp <- .dsr_composantes_adj(d <= tol_angle)

  k <- 0L
  for (gg in unique(grp)) {
    idx <- which(grp == gg)
    if (length(idx) < n_min) next
    # Direction moyenne par angles doubles : la moyenne arithmetique de 179 et
    # 1 vaudrait 90, soit la perpendiculaire exacte de la direction cherchee.
    a2 <- 2 * ang[idx] * pi / 180
    dir <- atan2(mean(sin(a2)), mean(cos(a2))) / 2
    nvec <- c(-sin(dir), cos(dir))          # normale a la direction du groupe
    off <- as.numeric(cen[idx, , drop = FALSE] %*% nvec)
    o <- order(off)
    idx <- idx[o]; off <- off[o]
    ecarts <- diff(off)

    # Suites d'ecarts admissibles, puis SOUS-suites regulieres maximales. On
    # etend tant que la regularite tient et l'on repart la ou elle casse : une
    # trace intruse pres d'un peigne -- doublon, piste de debardage -- en retire
    # une dent, elle ne fait pas disparaitre le peigne entier.
    ok <- ecarts >= espacement_min & ecarts <= espacement_max
    a <- 1L
    while (a <= length(ok)) {
      if (!ok[a]) { a <- a + 1L; next }
      b <- a
      while (b < length(ok) && ok[b + 1L]) {
        e <- ecarts[a:(b + 1L)]
        med <- stats::median(e)
        if (any(abs(e - med) > regularite * med)) break
        b <- b + 1L
      }
      if ((b - a + 2L) >= n_min) {
        k <- k + 1L
        membres <- idx[a:(b + 1L)]
        traces$PEIGNE[membres] <- k
        traces$PEIGNE_N[membres] <- length(membres)
        traces$PEIGNE_ESPACEMENT[membres] <- stats::median(ecarts[a:b])
      }
      a <- b + 1L
    }
  }
  traces
}


# Stations d'un troncon : appariement par colonne si `aretes` la porte, par
# indice de ligne sinon (meme regle que dsr_ecart_norme()).
#' @noRd
.dsr_stations_par_arete <- function(stations, aretes, id) {
  if (is.null(stations)) return(vector("list", nrow(aretes)))
  st <- if (inherits(stations, "sf")) sf::st_drop_geometry(stations) else stations
  if (!id %in% names(st)) {
    dsr_abort(c(
      "{.arg stations} ne porte pas la colonne {.field {id}}.",
      "i" = "L'ajouter avant d'empiler les sorties de {.fun dsr_measure}."
    ))
  }
  cles <- if (id %in% names(aretes)) aretes[[id]] else seq_len(nrow(aretes))
  lapply(cles, function(k) {
    if (is.na(k)) return(NULL)
    s <- st[!is.na(st[[id]]) & st[[id]] == k, , drop = FALSE]
    if (nrow(s) == 0L) NULL else s
  })
}


# Part de la longueur d'une trace a moins de `tol` d'une geometrie de reference.
#' @noRd
.dsr_part_le_long <- function(trace, ref, tol, pas = 5) {
  lg <- as.numeric(sf::st_length(trace))
  if (!is.finite(lg) || lg <= 0) return(NA_real_)
  n <- max(2L, ceiling(lg / pas))
  pts <- sf::st_cast(sf::st_line_sample(trace, sample = seq(0, 1, length.out = n)),
    "POINT")
  d <- suppressWarnings(as.numeric(sf::st_distance(pts, sf::st_union(ref))))
  mean(d <= tol, na.rm = TRUE)
}


#' Classer les lineaires detectes et proposer un balisage OSM
#'
#' Attribue a chaque lineaire une classe forestiere -- desserte, cloisonnement
#' d'exploitation, layon parcellaire -- a partir de ce que le paquet a mesure,
#' et propose le balisage OpenStreetMap correspondant. La sortie est une
#' **proposition auditable**, pas un jeu pret a televerser.
#'
#' @details
#' **La decision porte sur des structures, pas sur des seuils de largeur.** Sur
#' MNT 50 cm sous couvert, la rupture chaussee/accotement n'est le plus souvent
#' pas resolue et `LARGEUR_ROULABLE` rend une plateforme (voir
#' `BORDS_CHAUSSEE`) : un seuil de largeur porterait alors sur une grandeur qui
#' n'est pas celle qu'on croit mesurer. `BORDS_CHAUSSEE` lui-meme ne sert pas de
#' critere : il dit si la mesure a REUSSI, pas si la route est construite -- une
#' route batie sous couvert dense peut n'y resoudre aucun bord. Les criteres
#' retenus sont donc structurels -- portage par la reference, appartenance a un
#' peigne ([dsr_peignes()]), presence de fosses, coincidence avec le
#' parcellaire -- et le seul seuil radiometrique, celui du NDVI, est determine
#' par Otsu sur la donnee ([dsr_largeur_ndvi()]).
#'
#' **Cascade de decision.** Les structures sont evaluees d'abord, puis l'ouvrage
#' -- reference ou fosses -- qui prime sur elles :
#' \enumerate{
#'   \item dent d'un peigne, non minerale, sans fosse -> `cloisonnement_exploitation` ;
#'   \item coincide avec une limite du parcellaire et non minerale ->
#'     `layon_parcellaire` ;
#'   \item en crete et non minerale -> `pare_feu` (prime sur le peigne) ;
#'   \item porte par la reference ou creuse de fosses, minerale ->
#'     `route_forestiere` ;
#'   \item idem, non minerale -> `piste_forestiere` ;
#'   \item idem, nature de surface inconnue -> `desserte` ;
#'   \item sinon `indetermine`.
#' }
#'
#' **Le pare-feu exige DEUX canaux.** Un tronçon en crete non minerale sort en
#' `pare_feu` ; en crete et minerale, il reste une desserte. La conjonction n'est
#' pas une precaution mais le critere lui-meme : beaucoup de routes forestieres
#' suivent des cretes -- c'est une pratique de trace, le terrain y est plat en
#' travers et le drainage naturel -- et le seul relief les classerait toutes en
#' pare-feu. Sans `ndvi`, la classe n'est jamais posee.
#'
#' `desserte` n'est pas une classe de repli commode : c'est le refus de trancher
#' entre route et piste sans le canal optique. Sans NDVI, aucun `surface=` ni
#' `tracktype=` n'est propose.
#'
#' **`connecte_public` est reporte, pas decisif.** [dsr_reseau()] l'attribue par
#' COMPOSANTE : un cloisonnement greffe sur une piste desservie herite d'un
#' `TRUE` qui ne dit rien de lui. Il figure dans `CLASSE_MOTIF` -- ou son
#' absence signale une composante isolee, donc un candidat trace fossile -- mais
#' n'entre pas dans la cascade.
#'
#' **Tags d'acces.** Aucun n'est emis par defaut : un panneau ne se lit pas dans
#' un MNT. Fournir `panneaux` -- releve terrain, ou photos geolocalisees d'un
#' jumeau numerique -- fait emettre `access=<valeur>` accompagne de
#' `source:access`, qui porte la provenance. Deux panneaux contradictoires sur
#' un meme troncon n'emettent rien et le motif le dit.
#'
#' @param aretes `sf` de `LINESTRING` : la sortie `aretes` de [dsr_reseau()], ou
#'   tout reseau classe. Les colonnes `connecte_public` ([dsr_reseau()]) et
#'   `PEIGNE` ([dsr_peignes()]) sont utilisees si presentes.
#' @param stations `sf`/`data.frame` des stations ([dsr_measure()]) portant la
#'   colonne `id` ; `NULL` pour se passer des criteres de profil.
#' @param id Colonne identifiant le troncon. Defaut `"troncon"`.
#' @param ndvi `SpatRaster` de NDVI ([dsr_ndvi()]) ; `NULL` pour ne pas juger la
#'   nature de la surface.
#' @param reference `sf`/`sfc` du reseau de reference (BD TOPO, couche
#'   interne) : ce qu'il porte est une desserte. `NULL` pour ne pas s'y
#'   rapporter -- tous les lineaires sont alors juges sur leur seule structure.
#' @param tpi `SpatRaster` de position topographique -- l'altitude moins la
#'   moyenne de son voisinage. [dsr_slrm()] le rend deja : `dsr_slrm(mnt,
#'   fenetres_m = 50)` est le TPI a 50 m. `NULL` pour ne pas juger la position,
#'   et donc ne jamais poser `pare_feu`. **Le rayon commande tout** : a 10 m on
#'   mesure la banquette de la route elle-meme, a 200 m le massif ; 50 m est un
#'   point de depart, pas une valeur calibree.
#' @param seuil_crete,part_crete Un troncon est en crete si la mediane du `tpi`
#'   le long de son axe atteint `seuil_crete` (metres) **et** si `part_crete` de
#'   ses points y sont positifs. Defauts 0.5 m et 0.6.
#' @param parcellaire `sf`/`sfc` des limites de parcelles ; `NULL` pour ne pas
#'   tester la coincidence. Le paquet n'acquiert pas cette couche : elle vient de
#'   l'amont, qui seul sait ce qu'elle porte -- d'ou `sous_type_parcelle`.
#' @param sous_type_parcelle Sous-type OSM des limites fournies :
#'   `"section"` (parcellaire de gestion forestiere -- ses limites sont les
#'   layons materialises au sol) ou `"border"` (limites de propriete, un
#'   parcellaire cadastral). Le choix n'est pas devinable depuis la geometrie :
#'   omis alors qu'un `parcellaire` est fourni, `"section"` est suppose **et la
#'   fonction le dit**.
#'
#'   En pratique, l'amont fournit des contours d'**unites de gestion** (UGF),
#'   chacune portant sa reference cadastrale. Ce sont des limites de gestion, et
#'   `"section"` leur convient. Consequence a connaitre : une unite taillee dans
#'   une PORTION de parcelle a des cotes de decoupe interne, que rien ne
#'   materialise au sol -- un lineaire qui les suit ressort en
#'   `layon_parcellaire` sans en etre un. `CLASSE_MOTIF` porte alors `parcelle`,
#'   ce qui permet de les retrouver et de trancher au cas par cas.
#' @param panneaux `sf` `POINT`/`LINESTRING` attestant une restriction d'acces,
#'   portant `champ_acces` et, si possible, `champ_source` ; `NULL` (defaut)
#'   pour n'emettre aucun tag d'acces.
#' @param tol_parcelle,part_parcelle Distance (m) et part de longueur au-dela de
#'   laquelle une trace est reputee suivre le parcellaire. Defauts 5 et 0.6.
#' @param tol_panneau Distance (m) de rattachement d'un panneau a une trace.
#'   Defaut 15.
#' @param champ_acces,champ_source Colonnes de `panneaux`. Defauts `"access"` et
#'   `"source"`.
#' @param part_minerale Part de la largeur mesuree que la plage minerale doit
#'   couvrir pour que la surface soit dite minerale. Defaut 0.5.
#' @param ... Passe a [dsr_peignes()] quand `aretes` ne porte pas `PEIGNE`.
#'
#' @return Le `sf` d'entree, augmente de `CLASSE`, `CLASSE_CONF` (part de
#'   criteres renseignes qui concordent), `CLASSE_MOTIF` (les criteres qui ont
#'   vote, en clair) et `OSM_TAGS` (proposition de balisage, `NA` si aucune).
#' @seealso [dsr_peignes()], [dsr_detecter()], [dsr_reseau()], [dsr_measure()].
#' @references Fil OSM-fr, « Layons, cloisonnements d'exploitation en forets
#'   publiques », <https://forum.openstreetmap.fr/t/44555>.
#' @examples
#' g <- lapply(seq(0, 60, by = 20), function(y)
#'   sf::st_linestring(cbind(c(0, 100), c(y, y))))
#' tr <- sf::st_sf(geometry = sf::st_sfc(g, crs = 2154))
#' dsr_classer(tr)[, c("CLASSE", "OSM_TAGS")]
#' @export
dsr_classer <- function(aretes, stations = NULL, id = "troncon",
                        ndvi = NULL, reference = NULL, parcellaire = NULL,
                        panneaux = NULL, tpi = NULL,
                        seuil_crete = 0.5, part_crete = 0.6,
                        tol_parcelle = 5, part_parcelle = 0.6,
                        tol_panneau = 15, champ_acces = "access",
                        champ_source = "source", part_minerale = 0.5,
                        sous_type_parcelle = c("section", "border"), ...) {
  # Meme regle que `regime` de dsr_cubature() : la valeur n'est pas devinable
  # depuis la geometrie, alors on ne la suppose pas en silence.
  sous_type_dit <- !missing(sous_type_parcelle)
  sous_type_parcelle <- match.arg(sous_type_parcelle)
  if (!inherits(aretes, "sf")) dsr_abort("{.arg aretes} doit etre un {.cls sf}.")
  n <- nrow(aretes)
  if (n == 0L) dsr_abort("{.arg aretes} est vide.")

  if (!"PEIGNE" %in% names(aretes)) aretes <- dsr_peignes(aretes, ...)
  g <- sf::st_geometry(aretes)
  st_par <- .dsr_stations_par_arete(stations, aretes, id)

  # --- Criteres, un vecteur par critere ---------------------------------------
  peigne <- !is.na(aretes$PEIGNE)
  connecte <- if ("connecte_public" %in% names(aretes)) {
    as.logical(aretes$connecte_public)
  } else {
    rep(NA, n)
  }

  crit_st <- function(f) vapply(st_par, function(s)
    if (is.null(s)) NA else f(s), logical(1))
  fosses <- crit_st(function(s)
    if ("FOSSES" %in% names(s)) mean(s$FOSSES > 0, na.rm = TRUE) >= 0.2 else NA)

  larg <- vapply(st_par, function(s)
    if (is.null(s) || !"LARGEUR_ROULABLE" %in% names(s)) NA_real_
    else stats::median(s$LARGEUR_ROULABLE, na.rm = TRUE), numeric(1))

  # Surface minerale : le seul canal INDEPENDANT du lidar. Sans lui, on ne
  # tranche pas entre route et piste -- on le dit au lieu de le supposer.
  part_min <- rep(NA_real_, n)
  if (!is.null(ndvi)) {
    for (i in seq_len(n)) {
      if (is.na(larg[i]) || larg[i] <= 0) next
      l <- tryCatch(dsr_largeur_ndvi(g[i], ndvi), error = function(e) NULL)
      if (is.null(l)) next
      # Une plage minerale ABSENTE n'est pas une inconnue. dsr_largeur_ndvi()
      # rend NA quand aucune plage ne se ferme autour de l'axe -- mais elle a
      # deja echoue si le raster ne couvrait pas le trace ou si le seuil d'Otsu
      # n'etait pas calculable. Un retour sans plage veut donc dire « le canal a
      # regarde, et il n'y a rien de mineral » : c'est 0, pas NA.
      med <- stats::median(l$LARGEUR_NDVI, na.rm = TRUE)
      part_min[i] <- if (!is.finite(med)) 0 else med / larg[i]
    }
  }
  minerale <- ifelse(is.na(part_min), NA, part_min >= part_minerale)

  suit <- function(cible) {
    if (is.null(cible) || !length(sf::st_geometry(cible))) return(rep(NA, n))
    ref <- sf::st_geometry(cible)
    vapply(seq_len(n), function(i)
      .dsr_part_le_long(g[i], ref, tol_parcelle) >= part_parcelle, logical(1))
  }
  # Crete : position topographique le long de l'axe. Un pare-feu suit une ligne
  # de crete -- c'est sa raison d'etre, couper la propagation.
  crete <- rep(NA, n)
  if (!is.null(tpi)) {
    if (!inherits(tpi, "SpatRaster")) {
      dsr_abort("{.arg tpi} doit etre un {.cls SpatRaster} ({.fun dsr_slrm} a large fenetre).")
    }
    if (terra::nlyr(tpi) > 1L) tpi <- tpi[[1]]
    crete <- vapply(seq_len(n), function(i) {
      lg <- as.numeric(sf::st_length(g[i]))
      if (!is.finite(lg) || lg <= 0) return(NA)
      pts <- sf::st_cast(sf::st_line_sample(g[i],
        sample = seq(0, 1, length.out = max(2L, ceiling(lg / 5)))), "POINT")
      v <- terra::extract(tpi, sf::st_coordinates(pts))[, 1]
      if (all(!is.finite(v))) return(NA)
      stats::median(v, na.rm = TRUE) >= seuil_crete &&
        mean(v > 0, na.rm = TRUE) >= part_crete
    }, logical(1))
  }

  parcelle <- suit(parcellaire)
  if (!is.null(parcellaire) && !sous_type_dit) {
    dsr_inform(c(
      "!" = "{.arg sous_type_parcelle} non precise : {.val section} est suppose.",
      "i" = "Un parcellaire de GESTION forestiere : ses limites sont les layons materialises au sol.",
      "i" = "Pour un parcellaire CADASTRAL -- limites de propriete -- passer {.code sous_type_parcelle = \"border\"}."
    ))
  }
  # La reference fait autorite pour l'EXISTENCE d'un troncon (cf.
  # dsr_repositionner) : ce qu'elle porte est une desserte, quelle que soit la
  # structure geometrique par ailleurs.
  refer <- suit(reference)

  # --- Cascade ----------------------------------------------------------------
  vrai <- function(x) !is.na(x) & x
  faux <- function(x) !is.na(x) & !x

  classe <- rep("indetermine", n)
  # Structures d'abord...
  classe[peigne & !vrai(minerale) & !vrai(fosses)] <- "cloisonnement_exploitation"
  classe[vrai(parcelle) & !vrai(minerale)] <- "layon_parcellaire"
  # Un pare-feu n'est pas un cloisonnement : il prime sur le peigne. Mais il
  # exige que la surface soit CONNUE et non minerale -- beaucoup de routes
  # forestieres suivent des cretes, c'est meme une pratique de trace, et le seul
  # critere topographique les classerait toutes en pare-feu.
  classe[vrai(crete) & faux(minerale)] <- "pare_feu"
  # ...puis l'ouvrage, qui prime : un troncon porte par la reference ou creuse
  # de fosses est une desserte, meme s'il s'aligne sur un peigne.
  ouvrage <- vrai(refer) | vrai(fosses)
  classe[ouvrage & is.na(minerale)] <- "desserte"
  classe[ouvrage & faux(minerale)] <- "piste_forestiere"
  classe[ouvrage & vrai(minerale)] <- "route_forestiere"

  # --- Motifs et confiance ----------------------------------------------------
  crits <- list(reference = refer, peigne = peigne, minerale = minerale,
    fosses = fosses, connecte = connecte, parcelle = parcelle, crete = crete)
  motif <- vapply(seq_len(n), function(i) {
    v <- vapply(crits, function(x) x[i], logical(1))
    nom <- names(crits)
    dit <- ifelse(is.na(v), paste0(nom, "?"), ifelse(v, nom, paste0("!", nom)))
    paste(dit, collapse = "+")
  }, character(1))
  conf <- vapply(seq_len(n), function(i) {
    v <- vapply(crits, function(x) x[i], logical(1))
    if (all(is.na(v))) 0 else mean(!is.na(v))
  }, numeric(1))

  # --- Balisage propose -------------------------------------------------------
  tags <- vapply(seq_len(n), function(i) {
    switch(classe[i],
      route_forestiere = "highway=track;tracktype=grade2;surface=compacted",
      piste_forestiere = "highway=track;tracktype=grade4;surface=ground",
      # Sans NDVI on ne qualifie pas la surface : `track` sans `tracktype`.
      desserte = "highway=track",
      cloisonnement_exploitation = "man_made=cutline;cutline=loggingmachine",
      layon_parcellaire = paste0("man_made=cutline;cutline=", sous_type_parcelle),
      pare_feu = "man_made=cutline;cutline=firebreak",
      NA_character_)
  }, character(1))

  # --- Acces : uniquement sur attestation -------------------------------------
  if (!is.null(panneaux)) {
    if (!champ_acces %in% names(panneaux)) {
      dsr_abort(c(
        "{.arg panneaux} ne porte pas la colonne {.field {champ_acces}}.",
        "i" = "Elle doit porter la valeur d'acces constatee sur le panneau."
      ))
    }
    pr <- suppressWarnings(sf::st_is_within_distance(g, sf::st_geometry(panneaux),
      dist = tol_panneau))
    for (i in seq_len(n)) {
      j <- pr[[i]]
      if (!length(j)) next
      val <- unique(as.character(panneaux[[champ_acces]][j]))
      val <- val[!is.na(val) & nzchar(val)]
      if (length(val) != 1L) {
        # Deux panneaux qui se contredisent : on n'arbitre pas a leur place.
        motif[i] <- paste0(motif[i], "+acces_contradictoire")
        next
      }
      src <- if (champ_source %in% names(panneaux)) {
        s <- unique(as.character(panneaux[[champ_source]][j]))
        s <- s[!is.na(s) & nzchar(s)]
        if (length(s) == 1L) s else "survey"
      } else {
        "survey"
      }
      ajout <- sprintf("access=%s;source:access=%s", val, src)
      tags[i] <- if (is.na(tags[i])) ajout else paste(tags[i], ajout, sep = ";")
      motif[i] <- paste0(motif[i], "+acces_atteste")
    }
  }

  aretes$CLASSE <- classe
  aretes$CLASSE_CONF <- conf
  aretes$CLASSE_MOTIF <- motif
  aretes$OSM_TAGS <- tags
  aretes
}
