# Cache et provenance des acquisitions distantes.
#
# TRANSPOSE de `foretaccess` (spec 027, GPL-3, Pascal Obstetar), AU MEME FORMAT :
# un sidecar `<fichier>.provenance.json` pose a cote du cache. Le format est
# repris a l'identique -- meme cles, meme place -- pour qu'un cache ecrit ici se
# relise la-bas et reciproquement : les deux paquets travaillent sur les memes
# repertoires de projet.
#
# POURQUOI UN SIDECAR ET NON UN NOM DE FICHIER ENCODE : un cache est nomme
# d'apres ce qu'il CONTIENT (`osm.gpkg`), jamais d'apres ce qui l'a produit. Le
# nom reste donc lisible et stable pour les outils SIG, et la provenance peut
# s'enrichir sans casser les chemins.
#
# CE QUE LA PROVENANCE PORTE EN PLUS DES PARAMETRES : la DATE, l'instance servie
# et la requete exacte. OSM change tous les jours ; jusqu'ici deux executions a
# un mois d'ecart rendaient des resultats differents SANS AUCUNE TRACE. Sur une
# donnee qui alimente une conception de reseau, c'est un probleme de fond et non
# de la comptabilite : une mesure de rappel de dsr_detecter() n'est citable que
# si l'on peut dire contre quel etat d'OSM elle a ete faite.

#' @noRd
DSR_POLITIQUES_CACHE <- c("reacquerir", "avertir", "echouer", "ignorer")

#' @noRd
.dsr_chemin_cache <- function(cache_dir, couche, ext = "gpkg") {
  dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
  file.path(cache_dir, paste0(couche, ".", ext))
}

#' @noRd
.dsr_chemin_provenance <- function(chemin) paste0(chemin, ".provenance.json")

# `params` ne doit contenir que ce qui CHANGE LE CONTENU : une provenance trop
# bavarde invaliderait des caches sains et pousserait a mettre
# `politique_cache = "ignorer"`, ce qui ramenerait au probleme de depart.
# `acquisition` porte le reste -- ce qui se CONSTATE et ne se compare pas.
#' @noRd
.dsr_provenance_ecrire <- function(chemin, couche, source = NULL,
                                   params = list(), acquisition = list()) {
  p <- list(
    couche = couche,
    source = source %||% NA_character_,
    version_paquet = as.character(utils::packageVersion("dessertR")),
    date = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    parametres = params,
    acquisition = acquisition
  )
  tryCatch(
    jsonlite::write_json(p, .dsr_chemin_provenance(chemin), auto_unbox = TRUE,
      pretty = TRUE, null = "null"),
    # Un cache sans sidecar reste utilisable : il sera juste traite comme
    # divergent a la relecture, ce qui est le bon defaut.
    error = function(e) invisible(NULL)
  )
  invisible(p)
}

#' @noRd
.dsr_provenance_lire <- function(chemin) {
  f <- .dsr_chemin_provenance(chemin)
  if (!file.exists(f)) return(NULL)
  tryCatch(jsonlite::read_json(f, simplifyVector = TRUE), error = function(e) NULL)
}

# Rend les noms de parametres qui DIVERGENT (vide si tout concorde). Un
# parametre absent du sidecar compte comme divergent : on ne peut pas savoir,
# donc on ne suppose pas.
#' @noRd
.dsr_provenance_diff <- function(prov, source, params) {
  if (is.null(prov)) return("sidecar_absent")
  d <- character(0)
  if (!is.null(source) && !identical(as.character(prov$source), as.character(source))) {
    d <- c(d, "source")
  }
  enr <- prov$parametres
  for (n in names(params)) {
    a <- params[[n]]
    b <- if (is.list(enr) && n %in% names(enr)) enr[[n]] else NULL
    if (is.null(b) || !isTRUE(all.equal(as.character(a), as.character(b)))) {
      d <- c(d, n)
    }
  }
  d
}

# Que faire d'un cache produit avec D'AUTRES parametres ? Defaut
# « reacquerir » : le cout d'une re-acquisition est mesurable, celui d'un
# resultat faux ne l'est pas.
#' @noRd
.dsr_cache_utilisable <- function(chemin, couche, source = NULL, params = list(),
                                  politique = "reacquerir") {
  politique <- match.arg(politique, DSR_POLITIQUES_CACHE)
  if (identical(politique, "ignorer") || !file.exists(chemin)) {
    return(file.exists(chemin))
  }
  d <- .dsr_provenance_diff(.dsr_provenance_lire(chemin), source, params)
  if (!length(d)) return(TRUE)
  absent <- identical(d, "sidecar_absent")
  msg <- if (absent) {
    "Cache {.file {basename(chemin)}} sans provenance : impossible de savoir
     avec quels parametres il a ete produit."
  } else {
    "Cache {.file {basename(chemin)}} produit avec d'autres parametres :
     {.field {d}}."
  }
  switch(politique,
    echouer = dsr_abort(c(msg,
      "i" = "Passer {.code politique_cache = \"reacquerir\"} ou purger le cache.")),
    avertir = {
      cli::cli_warn(c(msg, "!" = "Cache servi tel quel : le resultat peut ne pas
                                  refleter les parametres demandes."))
      TRUE
    },
    reacquerir = {
      dsr_inform(c(msg, "i" = "Re-acquisition."))
      FALSE
    }
  )
}
