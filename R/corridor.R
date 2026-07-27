#' Construire le corridor autour d'un reseau de reference
#'
#' Le regime "corridor" est ce qui rend le traitement d'un massif entier
#' realiste : sur une dalle forestiere, un tampon de 30 a 50 m autour du reseau
#' connu ne represente typiquement qu'une petite fraction des points. Tout le
#' flux de correction et de mesure travaille dans ce corridor. Seule la
#' detection de desserte absente de la reference impose le regime complet.
#'
#' @param reseau Objet `sf` de lignes (par exemple `troncon_de_route` de la
#'   BD TOPO, filtre sur l'emprise d'etude).
#' @param tampon Demi-largeur du corridor en metres. Defaut 40, soit large
#'   devant la plus grosse erreur de position attendue sur la BD TOPO plus la
#'   largeur d'emprise maximale.
#' @param fusionner Fusionner les tampons en une geometrie unique.
#'
#' @return Un objet `sf` de polygones.
#' @export
dsr_corridor <- function(reseau, tampon = 40, fusionner = TRUE) {
  if (!inherits(reseau, "sf")) dsr_abort("{.arg reseau} doit etre un objet {.cls sf}.")
  if (is.na(sf::st_crs(reseau))) dsr_abort("{.arg reseau} n'a pas de CRS defini.")

  buf <- sf::st_buffer(sf::st_geometry(reseau), dist = tampon)
  if (isTRUE(fusionner)) {
    buf <- sf::st_union(buf)
  }
  sf::st_sf(geometry = sf::st_sfc(buf, crs = sf::st_crs(reseau)))
}


#' Selectionner les dalles intersectant une emprise
#'
#' @param catalogue Sortie de [dsr_catalog()].
#' @param emprise Objet `sf` ou `sfc`.
#' @return Le catalogue restreint aux dalles concernees.
#' @export
dsr_dalles_requises <- function(catalogue, emprise) {
  if (!inherits(catalogue, "dsr_catalog")) {
    dsr_abort("{.arg catalogue} doit provenir de {.fun dsr_catalog}.")
  }
  emprise <- sf::st_transform(sf::st_geometry(emprise), sf::st_crs(catalogue))
  idx <- lengths(sf::st_intersects(catalogue, emprise)) > 0L
  out <- catalogue[idx, ]
  dsr_inform(c("i" = "{sum(idx)} dalle{?s} sur {nrow(catalogue)} intersecte{?nt} l'emprise."))
  out
}


#' Lire les points d'une dalle restreints au corridor
#'
#' @param dalle Une ligne de catalogue (un seul enregistrement).
#' @param corridor Sortie de [dsr_corridor()].
#' @param classes Classes ASPRS a conserver. `NULL` pour tout garder.
#'   Rappel des classes Lidar HD : 2 sol, 3 vegetation basse, 4 vegetation
#'   moyenne, 5 vegetation haute, 6 batiment, 9 eau, 17 tablier de pont,
#'   64 sursol perenne, 66 points virtuels, 67 divers batis, 1 non classe.
#'   Les points virtuels (66) doivent etre exclus de tout calcul de rugosite
#'   ou de densite sol : ce sont des points synthetiques.
#'
#' @return Les points lus, format a arreter.
#'
#' @details
#' A ECRIRE (lot 0). Deux verifications a mener avant d'ecrire une ligne de
#' plus, dans l'ordre :
#'
#' 1. lasR lit-il correctement les fichiers COPC diffuses par l'IGN ? C'est le
#'    format majoritaire du Lidar HD ; un blocage ici arrete tout le projet.
#' 2. Quel est le gain reel du regime corridor ? Mesurer, sur des dalles
#'    reelles, la fraction de points retenus et le rapport des temps de lecture
#'    entre dalle complete et corridor. Le script `dev/02_bench_corridor.R`
#'    est fait pour ca. Si le gain est inferieur a un facteur 5, revoir la
#'    strategie avant d'aller plus loin.
#'
#' Le schema lasR est du type lecteur -> filtres -> etages -> exec(), avec
#' gestion native du tuilage, des buffers et du multi-threading. NE PAS
#' recopier ici une signature de fonction depuis une documentation ancienne :
#' l'API a bouge entre les versions. Ouvrir la doc de la version installee et
#' ecrire le pipeline en s'appuyant dessus.
#'
#' @noRd
dsr_lire_corridor <- function(dalle, corridor, classes = NULL) {
  dsr_verifier_lasR()
  dsr_abort(c(
    "{.fun dsr_lire_corridor} n'est pas encore implementee.",
    "i" = "Voir les notes de developpement dans {.file R/corridor.R} et le script {.file dev/02_bench_corridor.R}."
  ))
}
