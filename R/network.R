# Coherence topologique du reseau (BRIEF section 3.8). Point faible structurel
# d'ALSroads : chaque troncon corrige independamment, donc les jonctions ne
# coincident plus et des doublons paralleles apparaissent. On corrige ici :
#   - coincidence aux noeuds partages (collage des extremites proches) ;
#   - deduplication des traces paralleles a moins d'une largeur d'ecart ;
#   - verification de la connectivite au reseau public (une desserte qui ne
#     debouche nulle part est un artefact) ;
#   - sortie d'un graphe valide (sfnetworks en option), pas une collection de
#     LINESTRING independants.

#' Coller les extremites proches sur des noeuds partages
#'
#' Les traces corriges independamment ont des extremites qui devraient coincider
#' mais different de quelques decimetres. Cette fonction regroupe les extremites
#' distantes de moins de `tol` et les ramene sur un noeud commun (BRIEF section
#' 3.8), condition d'un graphe valide.
#'
#' @param traces Un `sf` de `LINESTRING`.
#' @param tol Distance de collage des extremites, en metres. Defaut 1.
#' @return Le meme `sf`, extremites collees.
#' @seealso [dsr_reseau()].
#' @export
dsr_coller_noeuds <- function(traces, tol = 1) {
  if (!inherits(traces, "sf")) dsr_abort("{.arg traces} doit etre un {.cls sf}.")
  g <- sf::st_geometry(traces)
  coords <- lapply(g, function(l) sf::st_coordinates(l)[, 1:2, drop = FALSE])
  ends <- do.call(rbind, lapply(coords, function(co) rbind(co[1, ], co[nrow(co), ])))

  cl <- dsr_cluster_points(ends, tol)
  cent <- t(vapply(split(seq_len(nrow(ends)), cl),
    function(idx) colMeans(ends[idx, , drop = FALSE]), numeric(2)))

  newg <- lapply(seq_along(coords), function(i) {
    co <- coords[[i]]
    co[1, ] <- cent[cl[2 * i - 1], ]
    co[nrow(co), ] <- cent[cl[2 * i], ]
    sf::st_linestring(co)
  })
  sf::st_set_geometry(traces, sf::st_sfc(newg, crs = sf::st_crs(traces)))
}


#' Dedupliquer les traces paralleles
#'
#' Supprime les traces qui longent une autre a moins d'une largeur d'ecart --
#' les doublons paralleles qu'engendre une correction troncon par troncon (BRIEF
#' section 3.8). On conserve les traces les plus longues et l'on ecarte celles
#' largement recouvertes par le tampon des traces deja retenues.
#'
#' @param traces Un `sf` de `LINESTRING`.
#' @param largeur Ecart (m) en deca duquel deux traces sont consideres doublons.
#'   Defaut 3.
#' @param recouvrement Fraction de longueur recouverte au-dela de laquelle une
#'   trace est ecartee. Defaut 0.7.
#' @return Le sous-ensemble `sf` conserve.
#' @seealso [dsr_reseau()].
#' @export
dsr_dedupe_paralleles <- function(traces, largeur = 3, recouvrement = 0.7) {
  if (!inherits(traces, "sf")) dsr_abort("{.arg traces} doit etre un {.cls sf}.")
  g <- sf::st_geometry(traces)
  ord <- order(as.numeric(sf::st_length(g)), decreasing = TRUE)

  garde <- integer(0)
  tampon <- NULL
  for (i in ord) {
    li <- g[i]
    if (is.null(tampon)) {
      garde <- c(garde, i)
      tampon <- sf::st_union(sf::st_buffer(li, largeur / 2))
      next
    }
    inter <- suppressWarnings(sf::st_intersection(li, tampon))
    frac <- if (length(inter) == 0L) 0 else
      as.numeric(sum(sf::st_length(inter))) / as.numeric(sf::st_length(li))
    if (frac < recouvrement) {
      garde <- c(garde, i)
      tampon <- sf::st_union(tampon, sf::st_buffer(li, largeur / 2))
    }
  }
  traces[sort(garde), ]
}


#' Construire un reseau topologiquement coherent
#'
#' Assemble une collection de traces en un reseau valide (BRIEF section 3.8) :
#' collage des noeuds partages, deduplication des paralleles, puis analyse de
#' connectivite (composantes, rattachement au reseau public). Une desserte qui ne
#' rejoint pas le reseau public est signalee comme artefact probable.
#'
#' @param traces Un `sf` de `LINESTRING` (traces corriges).
#' @param tol_noeud Distance de collage des extremites, en metres. Defaut 1.
#' @param largeur_dedupe Ecart de deduplication des paralleles, en metres.
#'   Defaut 3.
#' @param reseau_public `sf`/`sfc` du reseau public (routes ouvertes) pour la
#'   verification de connectivite ; `NULL` pour l'omettre.
#' @param tol_public Distance (m) de rattachement d'un noeud au reseau public.
#'   Defaut 5.
#'
#' @return Une liste : `aretes` (`sf` des traces retenus, avec `composant` et,
#'   si `reseau_public`, `connecte_public`), `noeuds` (`sf` `POINT` des noeuds),
#'   `graphe` (objet `igraph`), et `resume` (nombre d'aretes, de noeuds, de
#'   composantes, longueur non rattachee au public).
#' @seealso [dsr_coller_noeuds()], [dsr_dedupe_paralleles()], [dsr_sfnetwork()].
#' @export
dsr_reseau <- function(traces, tol_noeud = 1, largeur_dedupe = 3,
                       reseau_public = NULL, tol_public = 5) {
  if (!requireNamespace("igraph", quietly = TRUE)) {
    dsr_abort(c("Le paquet {.pkg igraph} est requis.",
      "i" = 'Installation : install.packages("igraph")'))
  }
  cl <- dsr_dedupe_paralleles(dsr_coller_noeuds(traces, tol_noeud), largeur_dedupe)
  g <- sf::st_geometry(cl)

  ends <- do.call(rbind, lapply(g, function(l) {
    co <- sf::st_coordinates(l)[, 1:2, drop = FALSE]
    rbind(co[1, ], co[nrow(co), ])
  }))
  key <- paste(round(ends[, 1], 3), round(ends[, 2], 3))
  nid <- as.integer(factor(key))
  from <- nid[seq(1, length(nid), 2)]
  to <- nid[seq(2, length(nid), 2)]
  nn <- max(nid)

  graphe <- igraph::graph_from_edgelist(cbind(from, to), directed = FALSE)
  comp <- igraph::components(graphe)
  cl$composant <- comp$membership[from]

  # Noeuds (un point par identifiant unique, dans l'ordre des identifiants).
  uniq <- !duplicated(nid)
  ordre <- order(nid[uniq])
  nxy <- ends[uniq, , drop = FALSE][ordre, , drop = FALSE]
  noeuds <- sf::st_sf(
    noeud = seq_len(nn),
    geometry = sf::st_sfc(lapply(seq_len(nn), function(i) sf::st_point(nxy[i, ])),
      crs = sf::st_crs(cl))
  )

  long_deconnectee <- NA_real_
  if (!is.null(reseau_public)) {
    pub <- sf::st_union(sf::st_geometry(reseau_public))
    pres <- lengths(sf::st_is_within_distance(noeuds, pub, dist = tol_public)) > 0
    comp_pub <- unique(comp$membership[pres])
    cl$connecte_public <- cl$composant %in% comp_pub
    long_deconnectee <- as.numeric(sum(sf::st_length(g[!cl$connecte_public])))
  }

  resume <- list(
    n_aretes = nrow(cl), n_noeuds = nn, n_composants = comp$no,
    longueur_deconnectee = long_deconnectee
  )
  list(aretes = cl, noeuds = noeuds, graphe = graphe, resume = resume)
}


#' Exporter le reseau en objet sfnetworks
#'
#' Convertit les aretes d'un reseau ([dsr_reseau()]) en objet `sfnetwork` -- un
#' graphe spatial valide plutot qu'une collection de `LINESTRING` (BRIEF section
#' 3.8). Necessite le paquet `sfnetworks`.
#'
#' @param reseau La sortie de [dsr_reseau()], ou directement un `sf` d'aretes.
#' @return Un objet `sfnetwork`.
#' @seealso [dsr_reseau()].
#' @export
dsr_sfnetwork <- function(reseau) {
  if (!requireNamespace("sfnetworks", quietly = TRUE)) {
    dsr_abort(c("Le paquet {.pkg sfnetworks} est requis pour cet export.",
      "i" = 'Installation : install.packages("sfnetworks")'))
  }
  aretes <- if (is.list(reseau) && !is.null(reseau$aretes)) reseau$aretes else reseau
  sfnetworks::as_sfnetwork(aretes, directed = FALSE)
}


# Regrouper des points par proximite (lien simple, seuil `tol`). Renvoie un
# identifiant de grappe par point.
#' @noRd
dsr_cluster_points <- function(pts, tol) {
  n <- nrow(pts)
  if (n <= 1L) return(rep(1L, n))
  hc <- stats::hclust(stats::dist(pts), method = "single")
  as.integer(stats::cutree(hc, h = tol))
}
