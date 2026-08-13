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
# OU VIT LE CLIENT OVERPASS. Quatre paquets de l'ecosysteme consomment OSM par
# deux implementations qui avaient chacune raison la ou l'autre se trompait :
# celle d'ici sur le TRANSPORT (borne au niveau du socket, test du `<remark>`),
# celle de `foretaccess` sur la STRATEGIE (une requete par emprise, et un cache).
# ADR-010 de `foretaccess` tranche : le client canonique vit la-bas, et ce
# fichier le consomme quand il est installe -- sinon il retombe sur la copie
# interne ci-dessous, qui applique le MEME contrat. `dsr_osm()` doit continuer
# de fonctionner sans `foretaccess` : la delegation est une deduplication, pas
# une dependance.
#
# SUGGESTS ET NON IMPORTS : `dsr_osm()` doit tourner sans `foretaccess`. La
# reciproque n'est pas possible -- ils ne peuvent pas nous declarer, `rlas`
# etant archive du CRAN, ce qui a fait echouer quatre jobs de leur CI en 90 s.
# C'est aussi ce qui a fait pencher ADR-010 vers eux plutot que vers nous.
#
# ET `getExportedValue()` PLUTOT QUE `foretaccess::` : la version publiee
# n'exporte pas encore `osm_overpass()`. Resoudre le symbole a l'execution, en
# testant sa presence, evite qu'une version installee plus ancienne fasse
# echouer l'appel au lieu de le faire retomber sur le repli.

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

# Corps de reponse en deca duquel une instance ne peut rien avoir rendu d'utile
# (un XML Overpass vide legitime fait deja plus). Garde-fou au cas ou le
# `<remark>` manquerait.
#' @noRd
DSR_OSM_TAILLE_MIN <- 100L

# Profondeur maximale de bissection : 4^3 = 64 sous-emprises au pire. Au-dela,
# ce n'est plus une emprise interactive et Overpass n'est plus le bon outil --
# c'est un extrait Geofabrik qu'il faut (voir NEWS et le brief d'unification).
#' @noRd
DSR_BISSECTION_MAX <- 3L


# --- Requete -----------------------------------------------------------------

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


# --- Transport ---------------------------------------------------------------

# POURQUOI curl ET NON `osmdata` : une instance saturee ne rend pas d'erreur,
# elle fait ATTENDRE. `osmdata::osmdata_sf()` boucle alors en backoff sans
# jamais rendre la main -- 16 reprises consecutives mesurees, soit 16 minutes
# d'attente pure --, et une rotation qui ne bascule que sur erreur n'est jamais
# atteinte : le premier serveur sature gele tout l'appel. `setTimeLimit()` n'y
# change rien, il n'interrompt qu'aux points de controle R, pas un socket bloque
# dans du C. Le `timeout` de libcurl, lui, borne l'appel dans le C de libcurl.
#
# POURQUOI LE PAQUET curl ET NON `system2("curl")` : l'executable n'est pas
# garanti (Windows, conteneur minimal) et la dependance n'etait declaree nulle
# part ; il impose du `shQuote` sur une requete pleine de guillemets ; et il ne
# donne acces NI au code HTTP NI aux en-tetes -- dont on a besoin pour lire
# `Retry-After` et pour distinguer un 429 (quota : on tourne) d'un 504 (duree :
# on bissecte).
#' @noRd
.dsr_overpass_curl <- function(url, ql, timeout) { # nocov start : acces reseau
  h <- curl::new_handle()
  curl::handle_setopt(h, timeout = timeout, connecttimeout = min(timeout, 20),
    postfields = ql, useragent = "dessertR/R (+GPL-3)")
  tryCatch(curl::curl_fetch_memory(url, handle = h),
    error = function(e) list(status_code = -1L, content = raw(0),
      headers = raw(0), erreur = conditionMessage(e)))
} # nocov end

# LES TROIS ISSUES DU CONTRAT, decidees ICI et nulle part ailleurs :
#
#   donnees      XML contenant `<way`                        -> le `sf`
#   vide legitime XML valide, pas de `<way`, PAS de `<remark>` -> un `sf` vide
#   refus        `<remark>`, 429/504, timeout, corps < 100 o   -> une ERREUR
#
# DISTINGUER « VIDE » DE « REFUSE » est l'erreur commise pendant la validation
# wsfi : une instance saturee rend un XML BIEN FORME de quelques centaines
# d'octets, sans code d'erreur HTTP, ou Overpass place un `<remark>`. Sans ce
# test on conclut « aucune donnee ici » -- la meme requete relancee rendait
# 194 ko. Un refus ne devient JAMAIS une couche vide.
#' @noRd
.dsr_overpass_verdict <- function(rep) {
  code <- as.integer(rep$status_code %||% -1L)
  if (!is.null(rep$erreur)) {
    st <- if (grepl("time.?d? ?out|timeout", rep$erreur, ignore.case = TRUE)) {
      "timeout"
    } else {
      "reseau"
    }
    return(list(statut = st, message = rep$erreur, retry = NA_real_))
  }
  if (identical(code, 429L)) {
    return(list(statut = "quota", message = "HTTP 429 (quota)",
      retry = .dsr_retry_after(rep$headers)))
  }
  # 504 : la passerelle a coupe parce que la requete etait trop longue. C'est
  # une duree, pas un quota -- donc bissectable, contrairement au 429.
  if (identical(code, 504L)) {
    return(list(statut = "timeout", message = "HTTP 504 (passerelle)",
      retry = .dsr_retry_after(rep$headers)))
  }
  if (code < 200L || code >= 300L) {
    return(list(statut = "http", message = paste("HTTP", code), retry = NA_real_))
  }
  corps <- rep$content %||% raw(0)
  if (length(corps) < DSR_OSM_TAILLE_MIN) {
    return(list(statut = "tronque",
      message = sprintf("corps de %d octets", length(corps)), retry = NA_real_))
  }
  txt <- rawToChar(corps)
  Encoding(txt) <- "UTF-8"
  if (grepl("<remark>", txt, fixed = TRUE)) {
    rk <- sub(".*<remark>\\s*(.*?)\\s*</remark>.*", "\\1", txt)
    # Le remark dit POURQUOI, et cela change la suite : « out of memory » ou
    # « timed out » se traitent en decoupant l'emprise, un « rate_limited » en
    # changeant d'instance. Decouper sur un quota AGGRAVE le probleme.
    st <- if (grepl("rate_limited|too many|slot", rk, ignore.case = TRUE)) {
      "quota"
    } else if (grepl("out of memory|timed out|runtime error", rk, ignore.case = TRUE)) {
      "volume"
    } else {
      "remark"
    }
    return(list(statut = st, message = paste("remark Overpass :", rk),
      retry = NA_real_))
  }
  list(statut = "ok", message = NA_character_, retry = NA_real_)
}

#' @noRd
.dsr_retry_after <- function(headers) {
  if (is.null(headers) || !length(headers)) return(NA_real_)
  h <- tryCatch(curl::parse_headers(headers), error = function(e) character(0))
  v <- grep("^retry-after:", tolower(h), value = TRUE)
  if (!length(v)) return(NA_real_)
  suppressWarnings(as.numeric(trimws(sub("^[^:]*:", "", v[1]))))
}

# Rotation d'instances. L'URL est un simple argument de boucle : contrairement a
# `osmdata::set_overpass_url()`, qui appelle `overpass_status()`, basculer ne
# coute AUCUN appel reseau. C'est ce qui rendait la rotation inatteignable
# exactement quand elle servait -- l'instance saturee faisait aussi echouer la
# bascule.
#' @noRd
.dsr_transport_overpass <- function(ql, timeout = 90,
                                    serveurs = DSR_SERVEURS_OVERPASS,
                                    max_reprises = 2) {
  derniere <- list(statut = "aucune", message = "aucune instance interrogee")
  for (i in seq_along(serveurs)) {
    u <- serveurs[i]
    for (essai in seq_len(max_reprises + 1L)) {
      rep <- .dsr_overpass_curl(u, ql, timeout)
      v <- .dsr_overpass_verdict(rep)
      if (identical(v$statut, "ok")) {
        if (i > 1L) {
          dsr_inform(c("i" = "Overpass : {.val {serveurs[1]}} indisponible,
                              repli sur {.val {u}}."))
        }
        return(list(corps = rep$content, instance = u,
          date = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")))
      }
      derniere <- v
      # `Retry-After` court : on patiente. Long : on change d'instance plutot
      # que d'attendre -- c'est le comportement d'`osmdata` (60 s en boucle,
      # sans plafond) qu'on refuse de reproduire.
      if (identical(v$statut, "quota") && !is.na(v$retry) && v$retry <= 10) {
        Sys.sleep(v$retry)
      } else {
        break
      }
    }
  }
  cli::cli_abort(c(
    "Overpass a refuse la requete sur {length(serveurs)} instance{?s}.",
    "x" = "Derniere cause : {derniere$message}.",
    "i" = "Un refus n'est PAS une absence de donnee : ne pas le lire comme une
           couche vide. Reessayer plus tard, les quotas sont horaires."
  ), class = "dsr_overpass_refus", statut = derniere$statut, call = NULL)
}


# --- Lecture -----------------------------------------------------------------

# Driver OSM de GDAL. Les tags que le driver ne promeut pas en colonne (selon
# `OSM_CONFIG_FILE`) atterrissent dans `other_tags` : on deplie explicitement
# ceux qu'on documente en sortie, sinon ils disparaissent silencieusement sur
# une machine dont la configuration GDAL differe.
#' @noRd
.dsr_lire_osm <- function(corps) {
  f <- tempfile(fileext = ".osm")
  on.exit(unlink(f), add = TRUE)
  writeBin(corps, f)
  d <- tryCatch(sf::st_read(f, layer = "lines", quiet = TRUE),
    error = function(e) NULL)
  if (is.null(d) || !nrow(d)) return(.dsr_osm_normaliser(NULL))
  .dsr_osm_normaliser(.dsr_deplier_tags(d))
}

#' @noRd
.dsr_deplier_tags <- function(d, tags = "highway") {
  if (!"other_tags" %in% names(d)) return(d)
  ot <- as.character(d$other_tags)
  ot[is.na(ot)] <- ""
  for (t in tags) {
    if (t %in% names(d) && !all(is.na(d[[t]]))) next
    motif <- paste0("\"", t, "\"=>\"([^\"]*)\"")
    v <- ifelse(grepl(motif, ot), sub(paste0(".*", motif, ".*"), "\\1", ot),
      NA_character_)
    if (t %in% names(d)) {
      d[[t]][is.na(d[[t]])] <- v[is.na(d[[t]])]
    } else if (any(!is.na(v))) {
      d[[t]] <- v
    }
  }
  d
}

# Deux colonnes, toujours les memes, quel que soit le chemin (delegation ou
# repli) et quel que soit le contenu : sans cela le `rbind` des quadrants
# echoue des qu'un quadrant ne porte pas de `highway`.
#' @noRd
.dsr_osm_normaliser <- function(d) {
  if (is.null(d) || !nrow(d)) {
    return(sf::st_sf(osm_id = character(0), highway = character(0),
      geometry = sf::st_sfc(crs = 4326)))
  }
  a <- sf::st_drop_geometry(d)
  for (n in c("osm_id", "highway")) {
    if (!n %in% names(a)) a[[n]] <- NA_character_
  }
  sf::st_sf(
    osm_id = as.character(a[["osm_id"]]),
    highway = as.character(a[["highway"]]),
    geometry = sf::st_geometry(d))
}


# --- Une requete, deleguee ou non --------------------------------------------

# Rend la fonction canonique, ou NULL s'il faut se replier. Voir l'en-tete du
# fichier pour le choix de `getExportedValue()`. L'option permet aux tests de
# forcer le repli -- les deux chemins doivent rendre exactement la meme chose.
#' @noRd
.dsr_osm_delegue <- function() {
  if (!isTRUE(getOption("dessertR.osm_delegue", TRUE))) return(NULL)
  if (!requireNamespace("foretaccess", quietly = TRUE)) return(NULL)
  if (!"osm_overpass" %in% getNamespaceExports("foretaccess")) return(NULL)
  tryCatch(getExportedValue("foretaccess", "osm_overpass"), error = function(e) NULL)
}

#' @noRd
.dsr_fetch_osm <- function(bbox_wgs, cle, valeur = NULL, timeout = 90,
                           serveurs = DSR_SERVEURS_OVERPASS, max_reprises = 2) {
  canonique <- .dsr_osm_delegue()
  if (!is.null(canonique)) {
    # Le client canonique ne prend qu'UNE valeur par filtre : plusieurs valeurs
    # deviennent une union de filtres dans la MEME requete, ce qui est
    # precisement ce pour quoi il accepte une liste.
    filtres <- if (is.null(valeur)) {
      cle
    } else {
      lapply(valeur, function(v) list(cle = cle, valeur = v))
    }
    args <- list(bbox_wgs = bbox_wgs, cle = filtres, timeout = timeout,
      serveurs = serveurs, max_reprises = max_reprises)
    if ("couches" %in% names(formals(canonique))) args$couches <- "lines"
    out <- do.call(canonique, args)
    prov <- list(instance = attr(out, "instance"),
      requete = attr(out, "requete"), date_requete = attr(out, "date_requete"))
    out <- .dsr_osm_normaliser(out)
    for (n in names(prov)) attr(out, n) <- prov[[n]]
    return(out)
  }
  ql <- .dsr_requete_overpass(bbox_wgs, cle, valeur, timeout)
  rep <- .dsr_transport_overpass(ql, timeout, serveurs, max_reprises)
  out <- .dsr_lire_osm(rep$corps)
  attr(out, "instance") <- rep$instance
  attr(out, "requete") <- ql
  attr(out, "date_requete") <- rep$date
  out
}


# --- Bissection --------------------------------------------------------------

#' @noRd
.dsr_quadrants <- function(bb) {
  xm <- (bb[["xmin"]] + bb[["xmax"]]) / 2
  ym <- (bb[["ymin"]] + bb[["ymax"]]) / 2
  list(
    c(xmin = bb[["xmin"]], ymin = bb[["ymin"]], xmax = xm, ymax = ym),
    c(xmin = xm, ymin = bb[["ymin"]], xmax = bb[["xmax"]], ymax = ym),
    c(xmin = bb[["xmin"]], ymin = ym, xmax = xm, ymax = bb[["ymax"]]),
    c(xmin = xm, ymin = ym, xmax = bb[["xmax"]], ymax = bb[["ymax"]])
  )
}

# Le statut voyage DANS la condition quand le refus vient de notre transport.
# Quand il vient du client canonique, il n'y est pas : on le relit dans le
# message. Fragile, et assume -- l'alternative serait de bissecter sur
# n'importe quel refus, y compris un 429, ou decouper aggrave le probleme.
#' @noRd
.dsr_statut_refus <- function(cnd) {
  s <- cnd$statut
  if (!is.null(s)) return(s)
  m <- paste(conditionMessage(cnd), collapse = " ")
  if (grepl("429|rate_limited|slot|quota", m, ignore.case = TRUE)) return("quota")
  if (grepl("out of memory|timed out|timeout|504", m, ignore.case = TRUE)) {
    return("timeout")
  }
  "autre"
}

# Une requete par emprise ; bissection en quadrants SEULEMENT sur un refus de
# volume ou de duree. Overpass plafonne le NOMBRE de requetes, pas la surface :
# decouper d'emblee (l'ancien tuilage kilometrique) transformait une AOI de
# 10 x 10 km en 100 requetes, soit exactement ce qui declenche le 429 que tout
# le reste du code s'efforce d'eviter.
#' @noRd
.dsr_recolter <- function(bb, crs, valeurs, timeout, cote, pause, profondeur,
                          etat) {
  g <- sf::st_as_sfc(sf::st_bbox(bb[c("xmin", "ymin", "xmax", "ymax")], crs = crs))
  bw <- sf::st_bbox(sf::st_transform(g, 4326))
  etat$n <- etat$n + 1L
  # `error` et non `condition` : le transport INFORME quand il bascule
  # d'instance, et un handler `condition` avalerait ce message comme s'il etait
  # l'issue de l'appel.
  res <- tryCatch(
    .dsr_fetch_osm(c(xmin = bw[["xmin"]], ymin = bw[["ymin"]],
      xmax = bw[["xmax"]], ymax = bw[["ymax"]]),
      cle = "highway", valeur = valeurs, timeout = timeout),
    error = function(cnd) cnd)

  if (!inherits(res, "error")) {
    etat$instances <- c(etat$instances, attr(res, "instance") %||% NA_character_)
    if (!length(etat$requetes)) {
      etat$requetes <- attr(res, "requete") %||% NA_character_
      etat$date <- attr(res, "date_requete") %||% NA_character_
    }
    return(if (nrow(res)) list(res) else list())
  }

  statut <- .dsr_statut_refus(res)
  demi <- max(bb[["xmax"]] - bb[["xmin"]], bb[["ymax"]] - bb[["ymin"]]) / 2
  # `cote` : plancher de bissection, en metres. NULL = seule la profondeur
  # borne le decoupage.
  if (!(statut %in% c("volume", "timeout")) || profondeur >= DSR_BISSECTION_MAX ||
      (!is.null(cote) && demi < cote)) {
    stop(res)
  }
  dsr_inform(c("i" = "Overpass a refuse l'emprise ({statut}) :
                      bissection en quadrants, niveau {profondeur + 1L}."))
  out <- list()
  for (q in .dsr_quadrants(bb)) {
    out <- c(out, .dsr_recolter(q, crs, valeurs, timeout, cote, pause,
      profondeur + 1L, etat))
    if (isTRUE(pause > 0)) Sys.sleep(pause)
  }
  out
}


#' Reseau routier OpenStreetMap sur une emprise
#'
#' Telecharge les lineaires `highway` d'OpenStreetMap sur l'emprise, en **une
#' requete**, et les rend projetes et decoupes.
#'
#' @details
#' **Une requete, pas cent.** Overpass plafonne le **nombre de requetes**, pas
#' la surface : le cout suit la densite de voirie, et une requete `highway` sur
#' une bbox de massif reste modeste. L'ancien tuilage kilometrique transformait
#' une emprise de 10 x 10 km en 100 requetes -- soit precisement ce qui
#' declenche le `429` que tout le reste du code s'efforce d'eviter -- et
#' retelechargeait tous les noeuds de chaque voie a chaque dalle traversee. Le
#' decoupage n'intervient plus qu'en **repli** : sur un refus de volume ou de
#' duree, l'emprise est bissectee en quadrants (profondeur maximale 3, soit 64
#' sous-emprises au pire). Jamais sur un `429`, qui appelle une rotation
#' d'instance et non un decoupage.
#'
#' **Trois issues, jamais confondues.** Des donnees, un vide legitime, ou un
#' refus. Un refus ne devient jamais une couche vide : une instance bridee rend
#' un XML **bien forme** de quelques centaines d'octets, sans code HTTP
#' d'erreur, avec un element `<remark>`. Lu naivement, cela dit « rien ici » --
#' l'erreur qui a fausse une journee de validation.
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
#' **Datez vos resultats.** OSM change tous les jours. Avec `cache_dir`, un
#' sidecar `osm.gpkg.provenance.json` enregistre la date de requete (UTC), les
#' instances servies, la requete Overpass exacte et le lineaire obtenu : sans
#' cela, deux executions a un mois d'ecart different **sans aucune trace**, ce
#' qui rend inciteable toute mesure de rappel.
#'
#' @section Performance:
#' Mesures du 2026-08-13, instance `overpass-api.de`, cache froid :
#'
#' | emprise | troncons | lineaire | requetes | duree |
#' |---|---:|---:|---:|---:|
#' | 3 x 3 km | 199 | 59,5 km | 1 | 0,8 s |
#' | 10 x 10 km | 2 116 | 562,7 km | 1 | 16,0 s |
#'
#' La seconde valait 100 requetes et 100 s de `pause` avec le tuilage
#' kilometrique, avant meme de compter les `429` qu'elle provoquait. Relecture
#' depuis `cache_dir` : 0,08 s.
#'
#' @section Duree bornee:
#' Aucun appel ne peut depasser `timeout * 4 * 3` secondes par emprise
#' interrogee -- quatre instances, trois essais chacune. Le decoupage multiplie
#' ce plafond par le nombre de sous-emprises. Baisser `timeout` resserre la
#' borne. C'est la propriete que `osmdata` ne peut pas offrir : son backoff de
#' 60 s n'a pas de plafond.
#'
#' @param emprise `sf`/`sfc`/`SpatVector`/`SpatRaster`, ou une sortie de
#'   [dsr_catalog()]. Sa bbox est interrogee d'un seul tenant.
#' @param valeurs Valeurs de la cle `highway` retenues ; `NULL` pour toutes.
#'   Defaut : les classes forestieres utiles.
#' @param cote Plancher de bissection, en metres : une sous-emprise plus petite
#'   n'est plus decoupee. Defaut `NULL` (aucun plancher). **N'est plus un pas de
#'   grille** : le decoupage ne suit plus la grille kilometrique Lidar HD.
#' @param pause Secondes d'attente entre deux sous-emprises, en mode bissection
#'   seulement. Sans effet dans le cas nominal, qui ne fait qu'une requete.
#' @param timeout Plafond par requete, en secondes. Passe a libcurl **et** a
#'   Overpass.
#' @param cache_dir Repertoire de cache. `NULL` (defaut) : aucun cache, chaque
#'   appel retape le reseau.
#' @param politique_cache Que faire d'un cache produit avec **d'autres
#'   parametres** ? `"reacquerir"` (defaut), `"avertir"`, `"echouer"` ou
#'   `"ignorer"`.
#'
#' @return Un `sf` `LINESTRING` dans le CRS de `emprise`, colonnes `highway` et
#'   `osm_id`, sans doublon. `NULL` si OSM ne porte rien sur l'emprise.
#' @seealso [dsr_detecter()], [dsr_vectoriser()], [dsr_classer()].
#' @examples
#' \dontrun{
#' emp <- sf::st_as_sfc(sf::st_bbox(mnt))
#' osm <- dsr_osm(emp, cache_dir = "cache/osm")
#' }
#' @export
dsr_osm <- function(emprise,
                    valeurs = c("track", "path", "unclassified", "service",
                                "residential", "tertiary"),
                    cote = NULL, pause = 1, timeout = 90,
                    cache_dir = NULL, politique_cache = "reacquerir") {
  emprise <- .dsr_emprise_sfc(emprise)
  crs <- sf::st_crs(emprise)
  # Le CRS est indispensable : la bbox doit etre reprojetee en WGS84 pour
  # Overpass. Sans lui, on ne peut rien demander -- autant le dire.
  if (is.na(crs)) dsr_abort("{.arg emprise} doit porter un CRS.")
  bb <- sf::st_bbox(emprise)

  # Ce qui CHANGE LE CONTENU, et rien d'autre : une provenance bavarde
  # invaliderait des caches sains.
  params <- list(
    emprise = paste(format(as.numeric(bb), digits = 12, scientific = FALSE,
      trim = TRUE), collapse = ","),
    crs = if (!is.na(crs$epsg)) paste0("EPSG:", crs$epsg) else "non-EPSG",
    valeurs = paste(sort(valeurs %||% "*"), collapse = "|"))

  chemin <- NULL
  if (!is.null(cache_dir)) {
    chemin <- .dsr_chemin_cache(cache_dir, "osm")
    if (.dsr_cache_utilisable(chemin, "osm", "overpass", params, politique_cache)) {
      cache <- tryCatch(sf::st_read(chemin, quiet = TRUE), error = function(e) NULL)
      if (!is.null(cache)) return(if (nrow(cache)) cache else NULL)
    }
  }

  etat <- new.env(parent = emptyenv())
  etat$n <- 0L
  etat$instances <- character(0)
  etat$requetes <- character(0)
  etat$date <- NA_character_
  morceaux <- .dsr_recolter(bb, crs, valeurs, timeout, cote, pause,
    profondeur = 0L, etat = etat)
  if (!length(morceaux)) return(NULL)

  out <- do.call(rbind, morceaux)
  # Une voie a cheval sur deux sous-emprises est rendue par les deux requetes.
  # Les `osm_id` absents ne se dedoublonnent pas : plusieurs NA ne sont pas
  # « la meme voie », et les confondre supprimerait de la geometrie reelle.
  out <- out[!(duplicated(out$osm_id) & !is.na(out$osm_id)), ]
  out <- sf::st_transform(out, crs)
  out <- suppressWarnings(sf::st_intersection(out, sf::st_union(emprise)))
  out <- out[!sf::st_is_empty(sf::st_geometry(out)), ]
  if (!nrow(out)) return(NULL)
  out <- suppressWarnings(sf::st_cast(out, "LINESTRING"))

  if (!is.null(chemin)) .dsr_cacher_osm(out, chemin, params, etat)
  out
}

# Le cache n'est ecrit que s'il y a quelque chose a ecrire : un `NULL` n'est pas
# mis en cache, faute de pouvoir distinguer a la relecture « OSM ne porte rien
# ici » de « le fichier n'a pas ete produit ».
#' @noRd
.dsr_cacher_osm <- function(out, chemin, params, etat) {
  tryCatch({
    sf::st_write(out, chemin, delete_dsn = TRUE, quiet = TRUE)
    .dsr_provenance_ecrire(chemin, "osm", "overpass", params, acquisition = list(
      date_requete = etat$date %||% NA_character_,
      instance = paste(unique(etat$instances[!is.na(etat$instances)]),
        collapse = " "),
      requete = if (length(etat$requetes)) etat$requetes[1] else NA_character_,
      nb_requetes = etat$n,
      nb_entites = nrow(out),
      lineaire_km = round(sum(as.numeric(sf::st_length(out))) / 1000, 3)))
  }, error = function(e) {
    dsr_inform(c("!" = "Cache OSM non ecrit : {conditionMessage(e)}"))
  })
  invisible(NULL)
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
#' preserver le 20 cm natif. Contrairement a Overpass, le WMS facture la
#' SURFACE : ici le decoupage est la bonne strategie.
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
      if (!.dsr_telecharger(u, f, timeout = 180)) next
      if (!file.exists(f) || file.size(f) < 1000) next
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

# Meme raison qu'Overpass : la borne doit vivre dans le transport, sinon un
# socket bloque gele l'appel sans plafond. Et le paquet `curl` plutot que le
# binaire, dont la presence n'etait garantie ni declaree nulle part.
#' @noRd
.dsr_telecharger <- function(url, dest, timeout = 180) { # nocov start : reseau
  h <- curl::new_handle()
  curl::handle_setopt(h, timeout = timeout, connecttimeout = min(timeout, 20))
  rep <- tryCatch(curl::curl_fetch_disk(url, dest, handle = h),
    error = function(e) NULL)
  !is.null(rep) && isTRUE(rep$status_code >= 200 && rep$status_code < 300)
} # nocov end


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
