# Emprise routiere normative (Certu / CETE, fiche 1.7, 09/2013)
# ------------------------------------------------------------------------------
#  Surfaces occupees par les infrastructures routieres  : estimation de
# l'emprise d'une voie a partir des seuls attributs de la BD TOPO, par des
# largeurs STANDARD tirees des instructions techniques (ARP, ICTAAL, ICTAVRU).
#
# CE QUE CETTE METHODE EST, ET CE QU'ELLE N'EST PAS
#
# Ce n'est pas une mesure. C'est une table de correspondance entre une classe de
# voie et une largeur reglementaire. Pour toute la desserte forestiere -- Chemin,
# Route empierree, Sentier -- elle rend une CONSTANTE de 2 m, quelle que soit la
# route. S'en servir pour caler dessertR reviendrait a forcer la mesure a 2 m
# partout, c'est-a-dire a detruire le signal meme que le paquet produit.
#
# La fiche pose elle-meme ses limites, et elles sont explicites :
#   - elle a ECARTE le champ de largeur de la BD TOPO,  la largeur des voies
#     n'est pas renseignee de facon homogene sur le territoire  ;
#   -  les valeurs calculees sont approchantes et ne delimitent pas avec une
#     precision decimetrique la largeur d'emprise  ;
#   - la methode  surestime la largeur d'emprise  sur la voirie locale.
#
# A quoi elle sert donc ici :
#   1. VOCABULAIRE. Elle donne la decomposition normative du profil en travers
#      -- chaussee, bande deraseee/d'arret, berme, zone de securite, emprise --
#      qui permet de dire enfin ce que `LARGEUR_ROULABLE` mesure exactement :
#      la chaussee, pas l'emprise.
#   2. CONTROLE DE PLAUSIBILITE. Un ordre de grandeur, pas une cible.
#   3. ECART A LA NORME. C'est la lecture interessante : dessertR mesure ce que
#      la fiche ne peut que supposer.  Cette piste fait 3,2 m la ou la norme en
#      suppose 2  est une information utile au gestionnaire.
#
# Reference : Certu, CETE Nord-Picardie et Mediterranee (2013). Mesure de la
# consommation d'espace : methodes et indicateurs, fiche 1.7.


# Table de la fiche : cl_admin | nature | franchissement | nb_voies |
# largeur_corrigee | largeur_bande_arret | largeur_berme | largeur_buffer.
# Transcrite telle quelle, sans interpolation ni extrapolation.
#' @noRd
.dsr_certu_table <- function() {
  brut <- c(
    "Autoroute|Autoroute|NC|0|3.5|3|1|12",
    "Autoroute|Autoroute|NC|2|7|3|1|12",
    "Autoroute|Autoroute|NC|3|10.5|3|1|12",
    "Autoroute|Autoroute|NC|4|14|3|1|12",
    "Autoroute|Autoroute|Pont|2|7|3|0|6.5",
    "Autoroute|Autoroute|Pont|3|10.5|3|0|6.5",
    "Autre|Bretelle|NC|0|3|2|1|4.5",
    "Autre|Bretelle|NC|1|3|2|1|4.5",
    "Autre|Bretelle|NC|2|6|2|1|6",
    "Autre|Bretelle|Pont|0|3|2|0|3.5",
    "Autre|Bretelle|Pont|1|3|2|0|3.5",
    "Autre|Bretelle|Pont|2|6|2|0|5",
    "Autre|Chemin|Gue ou radier|0|2|0|0|1",
    "Autre|Chemin|NC|0|2|0|0|1",
    "Autre|Chemin|Pont|0|2|0|0|1",
    "Autre|Chemin|Tunnel|0|2|0|0|1",
    "Autre|Escalier|NC|0|2|0|0|1",
    "Autre|Escalier|Pont|0|2|0|0|1",
    "Autre|Piste cyclable|NC|0|2|0|0|1",
    "Autre|Piste cyclable|Pont|0|2|0|0|1",
    "Autre|Piste cyclable|Tunnel|0|2|0|0|1",
    "Autre|Route a 1 chaussee|Gue ou radier|0|2|0|0.75|1.75",
    "Autre|Route a 1 chaussee|Gue ou radier|1|2|0|0.75|1.75",
    "Autre|Route a 1 chaussee|Gue ou radier|2|4|0.5|0.75|3.25",
    "Autre|Route a 1 chaussee|NC|0|2|0.5|0.75|3.25",
    "Autre|Route a 1 chaussee|NC|1|2|0.5|0.75|3.25",
    "Autre|Route a 1 chaussee|NC|2|4|0.5|0.75|3.25",
    "Autre|Route a 1 chaussee|NC|3|6|0.5|0.75|3.25",
    "Autre|Route a 1 chaussee|NC|4|8|0.5|0.75|3.25",
    "Autre|Route a 1 chaussee|NC|5|10|0.5|0.75|3.25",
    "Autre|Route a 1 chaussee|Pont|0|2|0.5|0|1.5",
    "Autre|Route a 1 chaussee|Pont|1|2|0.5|0|1.5",
    "Autre|Route a 1 chaussee|Pont|2|4|0.5|0|2.5",
    "Autre|Route a 1 chaussee|Pont|3|6|0.5|0|2.5",
    "Autre|Route a 1 chaussee|Pont|4|8|0.5|0|2.5",
    "Autre|Route a 1 chaussee|Tunnel|0|2|0.5|0|1.5",
    "Autre|Route a 1 chaussee|Tunnel|1|2|0.5|0|1.5",
    "Autre|Route a 1 chaussee|Tunnel|2|4|0.5|0|2.5",
    "Autre|Route a 2 chaussees|NC|0|2.5|1.5|1|4",
    "Autre|Route a 2 chaussees|NC|1|2.5|1.5|1|4",
    "Autre|Route a 2 chaussees|NC|2|5|1|1|4.5",
    "Autre|Route a 2 chaussees|NC|3|7.5|1|1|4.5",
    "Autre|Route a 2 chaussees|Pont|2|5|1|1|4.5",
    "Autre|Route empierree|Gue ou radier|0|2|0|0|1",
    "Autre|Route empierree|NC|0|2|0|0|1",
    "Autre|Route empierree|Pont|0|2|0|0|1",
    "Autre|Route empierree|Tunnel|0|2|0|0|1",
    "Autre|Sentier|NC|0|2|0|0|1",
    "Autre|Sentier|Pont|0|2|0|0|1",
    "Autre|Sentier|Tunnel|0|2|0|0|1",
    "Departementale|Bretelle|NC|0|3.5|1|1|3.75",
    "Departementale|Bretelle|NC|1|3.5|1|1|3.75",
    "Departementale|Bretelle|NC|2|7|1|1|5.5",
    "Departementale|Bretelle|Pont|1|3.5|1|0|2.75",
    "Departementale|Route a 1 chaussee|NC|0|3|0.5|1|3",
    "Departementale|Route a 1 chaussee|NC|1|3|0.5|1|3",
    "Departementale|Route a 1 chaussee|NC|2|6|1|1|5",
    "Departementale|Route a 1 chaussee|NC|3|9|1|1|5",
    "Departementale|Route a 1 chaussee|NC|4|12|1|1|5",
    "Departementale|Route a 1 chaussee|Pont|0|3|0.5|0|2",
    "Departementale|Route a 1 chaussee|Pont|1|3|0.5|0|2",
    "Departementale|Route a 1 chaussee|Pont|2|6|1|0|4",
    "Departementale|Route a 1 chaussee|Pont|3|9|1|0|4",
    "Departementale|Route a 1 chaussee|Pont|4|12|1|0|4",
    "Departementale|Route a 1 chaussee|Tunnel|2|6|1|0|4",
    "Departementale|Route a 2 chaussees|NC|0|3.5|1.5|1|4.5",
    "Departementale|Route a 2 chaussees|NC|1|3.5|1.5|1|4.5",
    "Departementale|Route a 2 chaussees|NC|2|7|2.5|1|7",
    "Departementale|Route a 2 chaussees|NC|3|10.5|2.5|1|7",
    "Departementale|Route a 2 chaussees|Pont|0|3.5|1.5|0|3.5",
    "Departementale|Route a 2 chaussees|Pont|1|3.5|1.5|0|3.5",
    "Departementale|Route a 2 chaussees|Pont|2|7|2|0|5.5",
    "Departementale|Route a 2 chaussees|Pont|3|10.5|2|0|5.5",
    "Departementale|Route empierree|NC|0|0|0|0|1",
    "Departementale|Sentier|NC|0|0|0|0|1",
    "Nationale|Bretelle|NC|1|3.5|2.5|1|5.25",
    "Nationale|Bretelle|NC|2|7|2.5|1|7",
    "Nationale|Bretelle|Pont|1|3.5|2.5|0|4.25",
    "Nationale|Quasi-autoroute|NC|1|3.5|2.5|1|5.25",
    "Nationale|Quasi-autoroute|NC|2|7|2.5|1|7",
    "Nationale|Quasi-autoroute|Pont|1|3.5|2.5|0|4.25",
    "Nationale|Quasi-autoroute|Pont|2|7|2.5|0|6",
    "Nationale|Route a 1 chaussee|NC|1|3.5|2.5|1|5.25",
    "Nationale|Route a 1 chaussee|NC|2|7|2.5|1|7",
    "Nationale|Route a 1 chaussee|NC|3|10.5|2.5|1|7",
    "Nationale|Route a 1 chaussee|NC|4|14|2.5|1|7",
    "Nationale|Route a 1 chaussee|Pont|1|3.5|2.5|0|4.25",
    "Nationale|Route a 1 chaussee|Pont|2|7|2.5|0|6",
    "Nationale|Route a 1 chaussee|Pont|3|10.5|2.5|0|6",
    "Nationale|Route a 1 chaussee|Pont|4|14|2.5|0|6",
    "Nationale|Route a 1 chaussee|Tunnel|2|7|2.5|0|6",
    "Nationale|Route a 2 chaussees|NC|0|3.5|2.5|1|7",
    "Nationale|Route a 2 chaussees|NC|1|3.5|2.5|1|5.25",
    "Nationale|Route a 2 chaussees|NC|2|7|2.5|1|7",
    "Nationale|Route a 2 chaussees|NC|3|10.5|2.5|1|7",
    "Nationale|Route a 2 chaussees|Pont|1|3.5|2.5|0|4.25",
    "Nationale|Route a 2 chaussees|Pont|2|7|2.5|0|6"
  )
  ch <- do.call(rbind, strsplit(brut, "|", fixed = TRUE))
  data.frame(
    cl_admin = ch[, 1], nature = ch[, 2], franchissement = ch[, 3],
    nb_voies = as.integer(ch[, 4]),
    largeur_corrigee = as.numeric(ch[, 5]),
    largeur_bande_arret = as.numeric(ch[, 6]),
    largeur_berme = as.numeric(ch[, 7]),
    largeur_buffer = as.numeric(ch[, 8]),
    stringsAsFactors = FALSE
  )
}


# Correspondance des valeurs de NATURE entre les millesimes de la BD TOPO.
# La fiche est ecrite pour la v2 ; la v3 (2019) a fusionne  Autoroute  et
#  Quasi-autoroute  en  Type autoroutier  et ajoute  Rond-point .
# Cette correspondance est DEDUITE, pas issue d'un document officiel : la
# verifier contre les valeurs reellement presentes (voir la sortie de la
# fonction, qui liste les natures non appariees).
# Normalisation des libelles avant appariement : minuscules, accents retires,
# espaces normalises. Sans cela l'appariement dependrait de l'encodage du GPKG
# et du millesime --  Route empierree  et  Route empierree  s'ecrivent
# differemment selon la chaine de production, et la comparaison echouerait en
# silence sur les classes qui nous interessent le plus.
#' @noRd
.dsr_normaliser <- function(x) {
  x <- as.character(x)
  # sf/GDAL rendent les libelles BD TOPO en octets UTF-8 ; on force cette
  # lecture quelle que soit la locale de la session. Sans cela, sous une locale
  # C, un accent se scinde en deux octets et l'appariement echoue EN SILENCE --
  # precisement sur « Route empierree », l'une des classes qui nous importent.
  Encoding(x) <- "UTF-8"
  x <- chartr(
    paste0("\u00e0\u00e2\u00e4\u00e7\u00e9\u00e8\u00ea\u00eb\u00ee",
      "\u00ef\u00f4\u00f6\u00f9\u00fb\u00fc\u00c0\u00c2\u00c4\u00c7",
      "\u00c9\u00c8\u00ca\u00cb\u00ce\u00cf\u00d4\u00d6\u00d9\u00db\u00dc"),
    "aaaceeeeiioouuuAAACEEEEIIOOUUU", x)
  x <- gsub("[^A-Za-z0-9]+", " ", x)
  trimws(tolower(x))
}


#' @noRd
.dsr_certu_nature_v3 <- function() {
  c(
    "Type autoroutier" = "Autoroute",
    "Rond-point" = "Route a 1 chaussee",
    "Route a 1 chaussee" = "Route a 1 chaussee",
    "Route a 2 chaussees" = "Route a 2 chaussees",
    "Route empierree" = "Route empierree"
  )
}


#' Emprise routiere normative (methode Certu, fiche 1.7)
#'
#' Estime la largeur de chaussee et l'emprise d'un troncon a partir des seuls
#' attributs de la BD TOPO, par les largeurs standard de la fiche Certu 1.7
#' (2013). C'est un **calcul normatif**, pas une mesure : il dit ce que la
#' reglementation suppose, pas ce que le terrain porte.
#'
#' @details
#' **Ce n'est pas une reference pour calibrer une mesure.** Pour toute la
#' desserte forestiere  `Chemin`, `Route empierree`, `Sentier`  la fiche rend
#' une **constante de 2 m**, identique quelle que soit la route. Caler
#' [dsr_measure()] dessus forcerait la mesure a 2 m partout, c'est-a-dire
#' detruirait le signal que le paquet existe pour produire. La fiche pose
#' elle-meme ses limites : elle a ecarte le champ de largeur de la BD TOPO
#' ( pas renseigne de facon homogene ), ses valeurs  ne delimitent pas avec
#' une precision decimetrique , et la methode  surestime  sur la voirie
#' locale.
#'
#' Son interet est ailleurs :
#'
#' * **le vocabulaire**  la fiche donne la decomposition normative du profil en
#'   travers, et permet de situer ce que mesure `LARGEUR_ROULABLE` : la
#'   **chaussee**, comparable a `LARGEUR_CHAUSSEE_CERTU`, et non l'emprise, qui
#'   ajoute bande derasee et berme ;
#' * **l'ecart a la norme**  c'est la lecture utile. dessertR mesure ce que la
#'   fiche ne peut que supposer :  cette piste fait 3,2 m la ou la norme en
#'   suppose 2  informe le gestionnaire, dans ce sens-la et pas l'inverse.
#'
#' **Schemas.** La fiche est ecrite pour la BD TOPO v2 (champs `cl_admin`,
#' `nature`, `franchisst`, `nb_voies`). En v3 les noms different et le
#' franchissement se deduit de `pos_sol` (negatif : tunnel, positif : pont).
#' Les correspondances de valeurs sont **deduites et non officielles** : la
#' sortie liste les combinaisons non appariees plutot que de leur affecter un
#' defaut silencieux.
#'
#' @param troncons `sf` des troncons de route (BD TOPO).
#' @param schema `"auto"` (defaut), `"v2"` ou `"v3"`.
#' @param champs Liste nommee pour forcer les noms de colonnes
#'   (`cl_admin`, `nature`, `franchissement`, `nb_voies`) ; `NULL` pour la
#'   detection automatique.
#' @param nature_map Vecteur nomme de correspondance des valeurs de nature vers
#'   celles de la fiche ; `NULL` pour le defaut du schema detecte.
#' @param emprise `TRUE` pour renvoyer en plus les polygones d'emprise
#'   (tampon de `largeur_buffer` autour de l'axe). Defaut `FALSE`.
#'
#' @return Le `sf` d'entree, augmente de `LARGEUR_CHAUSSEE_CERTU`,
#'   `LARGEUR_EMPRISE_CERTU` (= 2 x tampon), `BANDE_ARRET_CERTU`,
#'   `BERME_CERTU`. Les troncons non apparies recoivent `NA`. L'attribut
#'   `"certu"` porte le schema retenu, les champs utilises et les combinaisons
#'   non appariees. Avec `emprise = TRUE`, une liste `troncons` / `emprise`.
#' @references Certu, CETE Nord-Picardie et Mediterranee (2013). *Mesure de la
#'   consommation d'espace : methodes et indicateurs*, fiche 1.7,  Surfaces
#'   occupees par les infrastructures routieres .
#' @seealso [dsr_measure()], [dsr_calibrer_largeur()].
#' @export
dsr_emprise_certu <- function(troncons, schema = c("auto", "v2", "v3"),
                              champs = NULL, nature_map = NULL,
                              emprise = FALSE) {
  schema <- match.arg(schema)
  if (!inherits(troncons, "sf")) {
    dsr_abort("{.arg troncons} doit etre un {.cls sf}.")
  }
  nms <- names(troncons)
  trouver <- function(alias) {
    hit <- alias[tolower(alias) %in% tolower(nms)]
    if (length(hit) == 0L) return(NA_character_)
    nms[match(tolower(hit[1]), tolower(nms))]
  }

  if (identical(schema, "auto")) {
    schema <- if (!is.na(trouver("franchisst"))) "v2" else "v3"
  }
  ch <- if (is.null(champs)) {
    list(
      cl_admin = trouver(c("cl_admin", "CL_ADMIN", "classe_administrative")),
      nature = trouver(c("nature", "NATURE")),
      franchissement = trouver(c("franchisst", "FRANCHISST", "franchissement")),
      nb_voies = trouver(c("nb_voies", "NB_VOIES", "nombre_de_voies")),
      pos_sol = trouver(c("pos_sol", "POS_SOL", "position_par_rapport_au_sol"))
    )
  } else {
    utils::modifyList(list(cl_admin = NA_character_, nature = NA_character_,
      franchissement = NA_character_, nb_voies = NA_character_,
      pos_sol = NA_character_), champs)
  }

  manquants <- names(ch)[is.na(unlist(ch[c("cl_admin", "nature", "nb_voies")]))]
  if (length(manquants) > 0L) {
    dsr_abort(c(
      "Champs BD TOPO introuvables : {.val {manquants}}.",
      "i" = "Colonnes presentes : {.val {nms}}.",
      "i" = "Les forcer via {.arg champs}."
    ))
  }

  cl <- as.character(troncons[[ch$cl_admin]])
  nat <- as.character(troncons[[ch$nature]])
  nv <- suppressWarnings(as.integer(troncons[[ch$nb_voies]]))
  nv[is.na(nv)] <- 0L

  fr <- if (!is.na(ch$franchissement)) {
    as.character(troncons[[ch$franchissement]])
  } else if (!is.na(ch$pos_sol)) {
    # v3 : le franchissement se lit dans la position par rapport au sol.
    ps <- suppressWarnings(as.numeric(troncons[[ch$pos_sol]]))
    ifelse(is.na(ps) | ps == 0, "NC", ifelse(ps < 0, "Tunnel", "Pont"))
  } else {
    rep("NC", nrow(troncons))
  }
  fr[is.na(fr) | fr == ""] <- "NC"

  corr <- if (!is.null(nature_map)) nature_map else
    if (identical(schema, "v3")) .dsr_certu_nature_v3() else character(0)
  nat_n <- .dsr_normaliser(nat)
  if (length(corr) > 0L) {
    remp <- stats::setNames(.dsr_normaliser(corr), .dsr_normaliser(names(corr)))
    vu <- remp[nat_n]
    nat_n[!is.na(vu)] <- vu[!is.na(vu)]
  }

  tab <- .dsr_certu_table()
  cle <- paste(.dsr_normaliser(cl), nat_n, .dsr_normaliser(fr), nv, sep = "\r")
  cle_tab <- paste(.dsr_normaliser(tab$cl_admin), .dsr_normaliser(tab$nature),
    .dsr_normaliser(tab$franchissement), tab$nb_voies, sep = "\r")
  i <- match(cle, cle_tab)

  troncons$LARGEUR_CHAUSSEE_CERTU <- tab$largeur_corrigee[i]
  troncons$BANDE_ARRET_CERTU <- tab$largeur_bande_arret[i]
  troncons$BERME_CERTU <- tab$largeur_berme[i]
  troncons$LARGEUR_EMPRISE_CERTU <- 2 * tab$largeur_buffer[i]

  non_apparies <- sort(unique(paste(cl, nat, fr, nv, sep = " | ")[is.na(i)]))
  attr(troncons, "certu") <- list(
    schema = schema,
    champs = ch[!is.na(unlist(ch))],
    n_apparies = sum(!is.na(i)),
    n_total = nrow(troncons),
    non_apparies = non_apparies
  )
  if (length(non_apparies) > 0L) {
    dsr_inform(c(
      "!" = "{length(non_apparies)} combinaison{?s} sans correspondance dans la fiche ({sum(is.na(i))}/{nrow(troncons)} troncon{?s}).",
      "i" = "Premieres : {.val {utils::head(non_apparies, 3)}}",
      "i" = "Ajuster {.arg nature_map} si le millesime differe."
    ))
  }

  if (!isTRUE(emprise)) return(troncons)
  larg <- tab$largeur_buffer[i]
  ok <- !is.na(larg) & larg > 0
  poly <- sf::st_buffer(sf::st_geometry(troncons)[ok], larg[ok],
    endCapStyle = "FLAT")
  list(troncons = troncons, emprise = sf::st_sf(
    LARGEUR_EMPRISE_CERTU = 2 * larg[ok], geometry = poly))
}
