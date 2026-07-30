# Acquisition de donnees externes : OpenStreetMap et ortho IGN.
#
# Deux sources que le paquet ne produit pas mais dont il a besoin :
#
#   - OSM, comme REFERENCE COMPLEMENTAIRE. La question posee par dsr_detecter()
#     -- « quelle desserte la BD TOPO ignore-t-elle ? » -- est structurellement
#     invalidable : par construction il n'existe pas de verite pour ce que la
#     reference ne porte pas. Les `highway=track` d'OSM en couvrent une partie.
#     Mesure sur le bloc wsfi (4 km2) : OSM porte 32,1 km contre 15,5 km a la
#     BD TOPO, et 56 % de ce lineaire (~18 km) est a plus de 20 m de toute route
#     de la reference. C'est la seule verite partielle disponible pour le rappel
#     de la detection.
#
#   - l'ortho IGN IRC, comme CANAL OPTIQUE. Seule source independante du lidar
#     (voir canopee.R). dsr_ndvi() la suppose a 20 cm : c'est la seule
#     resolution a l'echelle d'une chaussee forestiere.
#
# La rotation d'instances Overpass est reprise de `foretaccess` (GPL-3, Pascal
# Obstetar), qui l'a etablie sur le meme constat que celui rencontre ici.

# Instances Overpass, essayees dans l'ordre. L'instance principale limite
# agressivement le debit et rend alors une reponse COURTE MAIS VALIDE, sans
# code d'erreur : 695 octets d'XML bien forme et zero entite. Un appelant qui ne
# distingue pas ce cas conclut « aucune donnee ici » -- erreur commise pendant
# la validation wsfi, ou la meme requete relancee a rendu 194 ko.
#' @noRd
DSR_SERVEURS_OVERPASS <- c(
  "https://overpass-api.de/api/interpreter",
  "https://overpass.kumi.systems/api/interpreter",
  "https://overpass.osm.ch/api/interpreter",
  "https://overpass.private.coffee/api/interpreter"
)


# Une requete OSM sur une bbox WGS84, avec bascule d'instance.
#
# POURQUOI curl ET NON `osmdata` : une instance saturee ne rend pas d'erreur,
# elle fait ATTENDRE. `osmdata::osmdata_sf()` boucle alors en backoff sans
# jamais rendre la main, et une rotation qui ne bascule que sur erreur n'est
# jamais atteinte -- le premier serveur sature gele tout l'appel. `setTimeLimit()`
# n'y change rien : il n'interrompt qu'aux points de controle R, pas un socket
# bloque dans du C. `--max-time` de curl, lui, borne l'appel au niveau du
# processus, ce qui rend la rotation effectivement atteignable.
#
# DISTINGUER « VIDE » DE « REFUSE », l'erreur commise pendant la validation
# wsfi : une instance saturee rend un XML BIEN FORME de quelques centaines
# d'octets, sans code d'erreur HTTP. Overpass y place un element `<remark>`.
# Sans ce test, on conclut « aucune donnee ici » -- la meme requete relancee
# rendait 194 ko.
#' @noRd
.dsr_requete_overpass <- function(bbox_wgs, cle, valeur = NULL, timeout = 90) {
  filtre <- if (is.null(valeur)) {
    sprintf('["%s"]', cle)
  } else {
    sprintf('["%s"~"%s"]', cle, paste(valeur, collapse = "|"))
  }
  sprintf("[out:xml][timeout:%d];(way%s(%.6f,%.6f,%.6f,%.6f););(._;>;);out body;",
    timeout, filtre, bbox_wgs[2], bbox_wgs[1], bbox_wgs[4], bbox_wgs[3])
}

#' @noRd
.dsr_fetch_osm <- function(bbox_wgs, cle, valeur = NULL, timeout = 90,
                           serveurs = DSR_SERVEURS_OVERPASS) {
  req <- .dsr_requete_overpass(bbox_wgs, cle, valeur, timeout)
  f <- tempfile(fileext = ".osm")
  refuse <- NULL

  for (u in serveurs) {
    rc <- tryCatch(system2("curl", c("-s", "--max-time", as.character(timeout),
      "-X", "POST", "--data-urlencode", shQuote(paste0("data=", req)),
      shQuote(u), "-o", shQuote(f))), error = function(e) 1L)
    if (rc != 0L || !file.exists(f) || file.size(f) < 100) {
      refuse <- sprintf("%s : pas de reponse", u)
      next
    }
    txt <- paste(readLines(f, warn = FALSE), collapse = "\n")
    if (grepl("<remark>", txt, fixed = TRUE)) {
      refuse <- sprintf("%s : %s", u,
        sub(".*<remark>\\s*(.*?)\\s*</remark>.*", "\\1", txt))
      next
    }
    # Reponse legitime. Vide (aucune voie) est un resultat, pas un echec.
    if (!grepl("<way", txt, fixed = TRUE)) return(NULL)
    g <- tryCatch(sf::st_read(f, layer = "lines", quiet = TRUE), error = function(e) NULL)
    if (is.null(g) || !nrow(g)) return(NULL)
    return(g)
  }
  # Toutes les instances ont refuse : on RELAIE l'echec plutot que de rendre un
  # resultat vide, qu'un appelant confondrait avec « rien a cet endroit ».
  dsr_abort(c("Aucune instance Overpass n'a repondu.", "x" = refuse,
    "i" = "Reessayer plus tard : les quotas sont horaires."))
}


# Decoupe une emprise en tuiles alignees sur la grille kilometrique Lidar HD.
#' @noRd
.dsr_tuiles <- function(emprise, cote = DSR_TAILLE_DALLE) {
  bb <- sf::st_bbox(emprise)
  xs <- seq(floor(bb["xmin"] / cote) * cote, bb["xmax"], by = cote)
  ys <- seq(floor(bb["ymin"] / cote) * cote, bb["ymax"], by = cote)
  out <- list()
  for (x in xs) for (y in ys) {
    t <- sf::st_bbox(c(xmin = x, ymin = y, xmax = x + cote, ymax = y + cote),
      crs = sf::st_crs(emprise))
    # Pas de test de CRS ici : il n'entre pas dans le decoupage, et le lier a
    # l'appartenance faisait rendre ZERO tuile en silence sur une emprise sans
    # CRS. Le besoin de CRS est reel mais appartient a l'appelant, qui doit le
    # dire clairement (voir dsr_osm).
    if (length(sf::st_intersects(sf::st_as_sfc(t),
        sf::st_as_sfc(sf::st_bbox(emprise)))[[1]])) {
      out[[length(out) + 1L]] <- t
    }
  }
  out
}


#' Reseau routier OpenStreetMap sur une emprise
#'
#' Telecharge les lineaires `highway` d'OpenStreetMap, **dalle par dalle**, et
#' les rend projetes et decoupes sur l'emprise.
#'
#' @details
#' **Pourquoi decouper par dalle.** Une requete unique sur un massif entier
#' depasse les quotas d'Overpass et echoue en bloc ; decoupee sur la grille
#' kilometrique du Lidar HD, elle devient une suite de requetes courtes, chacune
#' relancable, et le decoupage coincide avec celui du reste du traitement
#' ([dsr_catalog()]). Une dalle qui echoue n'emporte pas les autres.
#'
#' **Ce qu'OSM peut servir ici, et ce qu'il ne peut pas.** La question de
#' [dsr_detecter()] -- « quelle desserte la reference ignore-t-elle ? » -- n'a
#' pas de verite terrain par construction. Les `track` et `path` d'OSM en
#' couvrent une partie et fournissent donc un **rappel** mesurable. En revanche
#' OSM n'est **ni** un metre etalon de largeur (aucun attribut fiable), **ni**
#' une verite de position : une part du lineaire forestier y est tracee sur
#' trace GPS agregee (`source=strava heatmap`) ou sur fond satellite. Meme regle
#' que pour toute sortie d'un autre algorithme : comparaison, jamais calibrage.
#'
#' @param emprise `sf`/`sfc`/`SpatVector`/`SpatRaster`, ou une sortie de
#'   [dsr_catalog()]. Son emprise est decoupee en dalles.
#' @param valeurs Valeurs de la cle `highway` retenues ; `NULL` pour toutes.
#'   Defaut : les classes forestieres utiles.
#' @param cote Cote des tuiles de requete, en metres. Defaut 1000 (grille
#'   Lidar HD).
#' @param pause Secondes d'attente entre deux dalles, pour menager les quotas.
#'   Defaut 1.
#'
#' @return Un `sf` `LINESTRING` dans le CRS de `emprise`, colonnes `highway` et
#'   `osm_id`, sans doublon (une voie a cheval sur deux dalles n'est rendue
#'   qu'une fois). `NULL` si OSM ne porte rien sur l'emprise.
#' @seealso [dsr_detecter()], [dsr_vectoriser()].
#' @examples
#' \dontrun{
#' emp <- sf::st_as_sfc(sf::st_bbox(mnt))
#' osm <- dsr_osm(emp)
#' }
#' @export
dsr_osm <- function(emprise,
                    valeurs = c("track", "path", "unclassified", "service",
                                "residential", "tertiary"),
                    cote = DSR_TAILLE_DALLE, pause = 1) {
  emprise <- .dsr_emprise_sfc(emprise)
  crs <- sf::st_crs(emprise)
  # Le CRS est indispensable : la bbox de chaque dalle doit etre reprojetee en
  # WGS84 pour Overpass. Sans lui, on ne peut rien demander -- autant le dire.
  if (is.na(crs)) dsr_abort("{.arg emprise} doit porter un CRS.")
  tuiles <- .dsr_tuiles(emprise, cote)
  if (!length(tuiles)) dsr_abort("{.arg emprise} ne couvre aucune dalle.")

  morceaux <- list()
  echecs <- 0L
  for (i in seq_along(tuiles)) {
    bb <- sf::st_bbox(sf::st_transform(sf::st_as_sfc(tuiles[[i]]), 4326))
    l <- tryCatch(
      .dsr_fetch_osm(c(bb["xmin"], bb["ymin"], bb["xmax"], bb["ymax"]),
        cle = "highway", valeur = valeurs),
      error = function(e) {echecs <<- echecs + 1L; NULL})
    if (!is.null(l) && nrow(l)) {
      garde <- intersect(c("osm_id", "highway"), names(l))
      morceaux[[length(morceaux) + 1L]] <- sf::st_sf(
        sf::st_drop_geometry(l)[, garde, drop = FALSE],
        geometry = sf::st_geometry(l))
    }
    if (pause > 0 && i < length(tuiles)) Sys.sleep(pause)
  }
  if (echecs) {
    dsr_inform(c("!" = "{echecs} dalle{?s} sur {length(tuiles)} n'{?a/ont} pas pu etre interrogee{?s}."))
  }
  if (!length(morceaux)) return(NULL)

  out <- do.call(rbind, morceaux)
  # Une voie a cheval sur deux dalles est rendue par les deux requetes.
  if ("osm_id" %in% names(out)) out <- out[!duplicated(out$osm_id), ]
  out <- sf::st_transform(out, crs)
  out <- suppressWarnings(sf::st_intersection(out, sf::st_union(emprise)))
  out <- out[!sf::st_is_empty(sf::st_geometry(out)), ]
  if (!nrow(out)) return(NULL)
  suppressWarnings(sf::st_cast(out, "LINESTRING"))
}


#' Ortho IGN (RVB ou IRC) sur une emprise
#'
#' Telecharge l'ortho de la Geoplateforme IGN a sa resolution native, en
#' tuilant la requete. Sert le canal optique du paquet ([dsr_ndvi()]).
#'
#' @details
#' Trois pieges du service, tous rencontres et tous silencieux :
#'
#' * le WMS **impose `VERSION=1.3.0`** -- toute autre valeur est rejetee ;
#' * en `EPSG:2154` l'ordre des axes est **(X, Y)**. Un BBOX inverse ne leve
#'   aucune erreur : le service rend un GeoTIFF valide et **entierement vide** ;
#' * le GeoTIFF rendu **n'a pas toujours de CRS**. Sans reaffectation, les
#'   croisements ulterieurs sortent un avertissement `CRS do not match` et,
#'   selon les cas, des valeurs fausses.
#'
#' Le tuilage n'est pas un detail : au-dela d'environ 4096 pixels de cote, un
#' appel unique force a **degrader la resolution**. Comme l'interet du canal
#' optique est precisement d'etre a l'echelle d'une chaussee, on decoupe pour
#' preserver le 20 cm natif.
#'
#' @param emprise `sf`/`sfc`/`SpatVector`/`SpatRaster` donnant l'emprise voulue.
#' @param couche Couche WMS. Defaut l'ortho IRC (PIR, Rouge, Vert), celle
#'   qu'attend [dsr_ndvi()]. `"ORTHOIMAGERY.ORTHOPHOTOS"` pour le RVB.
#' @param res Resolution demandee, en metres. Defaut 0.2.
#' @param pas Cote des tuiles de requete, en metres. Defaut 200 (soit 1000 px a
#'   20 cm, loin de la limite du service).
#'
#' @return Un `SpatRaster` trois bandes en `EPSG:2154`, ou `NULL` si le service
#'   n'a rien rendu.
#' @seealso [dsr_ndvi()], [dsr_canaux_externes()].
#' @examples
#' \dontrun{
#' irc <- dsr_ortho_ign(sf::st_as_sfc(sf::st_bbox(mnt)))
#' ndvi <- dsr_ndvi(irc)
#' }
#' @export
dsr_ortho_ign <- function(emprise,
                          couche = "ORTHOIMAGERY.ORTHOPHOTOS.IRC",
                          res = 0.2, pas = 200) {
  emprise <- .dsr_emprise_sfc(emprise)
  if (is.na(sf::st_crs(emprise))) dsr_abort("{.arg emprise} doit porter un CRS.")
  emprise <- sf::st_transform(emprise, 2154)
  bb <- as.numeric(sf::st_bbox(emprise))

  base <- paste0("https://data.geopf.fr/wms-r/wms?SERVICE=WMS&VERSION=1.3.0",
    "&REQUEST=GetMap&LAYERS=", couche,
    "&STYLES=&CRS=EPSG:2154&FORMAT=image/geotiff")

  tuiles <- list()
  for (x in seq(bb[1], bb[3] - 1e-6, by = pas)) {
    for (y in seq(bb[2], bb[4] - 1e-6, by = pas)) {
      x2 <- min(x + pas, bb[3]); y2 <- min(y + pas, bb[4])
      n <- c(max(1, round((x2 - x) / res)), max(1, round((y2 - y) / res)))
      f <- tempfile(fileext = ".tif")
      # BBOX en (X, Y) : voir @details. L'inverser rend une image vide.
      u <- sprintf("%s&BBOX=%f,%f,%f,%f&WIDTH=%d&HEIGHT=%d", base, x, y, x2, y2,
        n[1], n[2])
      ok <- tryCatch(
        system2("curl", c("-s", "--max-time", "180", shQuote(u), "-o", shQuote(f))) == 0,
        error = function(e) FALSE)
      if (!ok || !file.exists(f) || file.size(f) < 1000) next
      r <- tryCatch(terra::rast(f), error = function(e) NULL)
      if (is.null(r)) next
      # Le service omet parfois le CRS : sans cela, tout croisement ulterieur
      # avertit et peut fausser les masques.
      if (is.na(terra::crs(r)) || !nzchar(terra::crs(r))) terra::crs(r) <- "EPSG:2154"
      tuiles[[length(tuiles) + 1L]] <- r
    }
  }
  if (!length(tuiles)) return(NULL)
  out <- if (length(tuiles) == 1L) tuiles[[1]] else do.call(terra::merge, unname(tuiles))
  terra::crs(out) <- "EPSG:2154"
  names(out) <- c("pir", "rouge", "vert")[seq_len(terra::nlyr(out))]
  out
}


# Emprise, quelle qu'en soit la forme, ramenee a un `sfc` polygonal.
#' @noRd
.dsr_emprise_sfc <- function(x) {
  if (inherits(x, "SpatRaster") || inherits(x, "SpatVector")) {
    # as.vector() plutot que e[1] : le sous-ensemble d'un SpatExtent ne rend pas
    # un scalaire nomme utilisable tel quel par st_bbox, et le polygone sort NA.
    e <- as.vector(terra::ext(x)) # xmin, xmax, ymin, ymax
    g <- sf::st_as_sfc(sf::st_bbox(
      c(xmin = e[[1]], ymin = e[[3]], xmax = e[[2]], ymax = e[[4]])))
    sf::st_crs(g) <- sf::st_crs(terra::crs(x))
    return(g)
  }
  if (inherits(x, "sf") || inherits(x, "data.frame")) {
    if (!is.null(x$geometry) || inherits(x, "sf")) x <- sf::st_geometry(x)
  }
  if (!inherits(x, "sfc")) dsr_abort("{.arg emprise} : type non reconnu.")
  sf::st_as_sfc(sf::st_bbox(x))
}
