#' Decoder le nom d'une dalle Lidar HD
#'
#' Les produits du programme Lidar HD sont diffuses en dalles de 1 km x 1 km
#' dont le nom porte les coordonnees kilometriques du coin nord-ouest, par
#' exemple `LHD_FXX_0186_6834_PTS_C_LAMB93_IGF69.copc.laz` ou
#' `LHD_FXX_0186_6834_MNT_O_0M50_LAMB93_IGF69.tif`.
#'
#' La fonction extrait le premier couple de nombres a quatre chiffres et en
#' derive l'emprise. Elle ne lit pas le fichier : c'est un decodage purement
#' textuel, tres rapide, utilise pour construire l'index avant toute I/O.
#'
#' @param x Chemins ou noms de fichiers.
#' @param taille Cote de la dalle en metres. Defaut 1000.
#'
#' @return Un `data.table` avec les colonnes `fichier`, `cle`, `xmin`, `ymin`,
#'   `xmax`, `ymax`. Les lignes non decodables ont des emprises `NA`.
#'
#' @details
#' ATTENTION : la convention de nommage a varie entre les blocs et les
#' millesimes. Verifier le resultat sur un echantillon de vos dalles avant de
#' faire confiance a l'index, et comparer avec les emprises reelles retournees
#' par [dsr_catalog()] avec `entetes = TRUE`.
#'
#' @export
dsr_parse_dalle <- function(x, taille = DSR_TAILLE_DALLE) {
  base <- basename(x)

  # regmatches() ne renvoie que les correspondances : on repere d'abord
  # lesquelles ont abouti, sinon les indices se decalent silencieusement.
  r  <- regexpr("_(\\d{4})_(\\d{4})_", base)
  ok <- r != -1L
  coords <- rep(NA_character_, length(base))
  coords[ok] <- regmatches(base, r)

  km <- do.call(rbind, lapply(coords, function(s) {
    if (is.na(s)) return(c(NA_integer_, NA_integer_))
    as.integer(strsplit(gsub("^_|_$", "", s), "_", fixed = TRUE)[[1]])
  }))

  cle <- rep(NA_character_, length(base))
  cle[ok] <- sprintf("%04d_%04d", km[ok, 1], km[ok, 2])

  xmin <- as.numeric(km[, 1]) * 1000
  ymax <- as.numeric(km[, 2]) * 1000

  data.table::data.table(
    fichier = as.character(x),
    cle     = cle,
    xmin    = xmin,
    ymin    = ymax - taille,
    xmax    = xmin + taille,
    ymax    = ymax
  )
}


#' Cataloguer un jeu de dalles Lidar HD
#'
#' Construit un index spatial des dalles LAZ, MNT et MNH et les apparie sur la
#' grille kilometrique. C'est le socle de tout le reste : les traitements se
#' font *par dalle*, jamais par troncon.
#'
#' @param laz,mnt,mnh Repertoires ou vecteurs de chemins. `NULL` si absent.
#' @param crs Code EPSG. Defaut 2154 (RGF93 / Lambert-93).
#' @param entetes Lire les en-tetes LAS pour recuperer les emprises reelles,
#'   le nombre de points et les metadonnees de production. Peu couteux (aucun
#'   point n'est decompresse) mais suppose un acces disque a chaque fichier.
#'
#' @return Un objet `sf` de classe `dsr_catalog`, une ligne par dalle.
#'
#' @examples
#' \dontrun{
#' cat <- dsr_catalog(
#'   laz = "~/lidarhd/laz",
#'   mnt = "~/lidarhd/mnt",
#'   mnh = "~/lidarhd/mnh"
#' )
#' plot(sf::st_geometry(cat))
#' }
#'
#' @export
dsr_catalog <- function(laz = NULL, mnt = NULL, mnh = NULL,
                        crs = DSR_CRS_DEFAUT, entetes = TRUE) {

  collecter <- function(chemin, motif) {
    if (is.null(chemin)) return(character(0))
    if (length(chemin) == 1L && dir.exists(chemin)) {
      list.files(chemin, pattern = motif, full.names = TRUE, ignore.case = TRUE)
    } else {
      chemin
    }
  }

  f_laz <- collecter(laz, "\\.(laz|las)$")
  f_mnt <- collecter(mnt, "\\.tif{1,2}$")
  f_mnh <- collecter(mnh, "\\.tif{1,2}$")

  if (length(f_laz) + length(f_mnt) + length(f_mnh) == 0L) {
    dsr_abort("Aucun fichier trouve. Verifier les chemins fournis.")
  }

  parts <- list(laz = f_laz, mnt = f_mnt, mnh = f_mnh)
  tab <- data.table::rbindlist(lapply(names(parts), function(nm) {
    if (length(parts[[nm]]) == 0L) return(NULL)
    d <- dsr_parse_dalle(parts[[nm]])
    d[, type := nm]
    d
  }))

  n_ko <- sum(is.na(tab$cle))
  if (n_ko > 0L) {
    dsr_inform(c(
      "!" = "{n_ko} fichier{?s} dont le nom n'a pas pu etre decode et {?a/ont} ete ignore{?s}.",
      "i" = "Voir {.fun dsr_parse_dalle} : la convention de nommage varie selon les blocs."
    ))
    tab <- tab[!is.na(cle)]
  }

  # Tout ecarter laisse une table vide, et data.table::dcast y repond par une
  # erreur interne indiagnosticable. Le cas n'est pas theorique : il suffit
  # qu'un bloc soit stocke sous une autre convention de nommage.
  if (nrow(tab) == 0L) {
    exemples <- utils::head(basename(c(f_laz, f_mnt, f_mnh)), 3L)
    dsr_abort(c(
      "Aucun nom de fichier n'a pu etre decode : catalogue vide.",
      "i" = "Attendu : la cle kilometrique {.val _XXXX_YYYY_} dans le nom, convention Lidar HD.",
      "x" = "Vu : {.file {exemples}}",
      "i" = "Voir {.fun dsr_parse_dalle} pour la convention attendue."
    ))
  }

  # Une ligne par dalle, une colonne de chemin par type de produit
  large <- data.table::dcast(tab, cle + xmin + ymin + xmax + ymax ~ type,
                             value.var = "fichier", fun.aggregate = function(z) z[1])

  if (isTRUE(entetes) && "laz" %in% names(large)) {
    meta <- dsr_lire_entetes(large$laz)
    large <- cbind(large, meta)
    # L'emprise reelle prime sur celle deduite du nom
    ok <- !is.na(meta$h_xmin)
    large[ok, `:=`(xmin = meta$h_xmin[ok], ymin = meta$h_ymin[ok],
                   xmax = meta$h_xmax[ok], ymax = meta$h_ymax[ok])]
  }

  geom <- sf::st_sfc(lapply(seq_len(nrow(large)), function(i) {
    sf::st_polygon(list(cbind(
      c(large$xmin[i], large$xmax[i], large$xmax[i], large$xmin[i], large$xmin[i]),
      c(large$ymin[i], large$ymin[i], large$ymax[i], large$ymax[i], large$ymin[i])
    )))
  }), crs = crs)

  out <- sf::st_sf(as.data.frame(large), geometry = geom)
  class(out) <- c("dsr_catalog", class(out))
  out
}


#' Lire les en-tetes LAS d'un ensemble de dalles
#'
#' Ne decompresse aucun point. Sert a recuperer l'emprise reelle, le volume et
#' surtout les metadonnees de production, indispensables pour reperer les
#' melanges de millesimes ou de versions de classification.
#'
#' @param fichiers Chemins vers des fichiers LAS/LAZ.
#' @return Un `data.table`, une ligne par fichier.
#' @noRd
dsr_lire_entetes <- function(fichiers) {
  lire_un <- function(f) {
    if (is.na(f) || !file.exists(f)) {
      return(list(h_xmin = NA_real_, h_ymin = NA_real_, h_xmax = NA_real_,
                  h_ymax = NA_real_, n_points = NA_real_, version_las = NA_character_,
                  logiciel = NA_character_, systeme = NA_character_,
                  jour = NA_integer_, annee = NA_integer_))
    }
    h <- try(rlas::read.lasheader(f), silent = TRUE)
    if (inherits(h, "try-error")) {
      dsr_inform(c("!" = "En-tete illisible : {.file {basename(f)}}"))
      return(lire_un(NA_character_))
    }
    list(
      h_xmin      = h[["Min X"]],
      h_ymin      = h[["Min Y"]],
      h_xmax      = h[["Max X"]],
      h_ymax      = h[["Max Y"]],
      n_points    = as.numeric(h[["Number of point records"]]),
      version_las = paste0(h[["Version Major"]], ".", h[["Version Minor"]]),
      logiciel    = h[["Generating Software"]],
      systeme     = h[["System Identifier"]],
      jour        = h[["File Creation Day of Year"]],
      annee       = h[["File Creation Year"]]
    )
  }
  data.table::rbindlist(lapply(fichiers, lire_un))
}


#' Verifier l'homogeneite d'un catalogue
#'
#' Les blocs Lidar HD s'etalent sur plusieurs annees et plusieurs versions de
#' classification. Melanger des dalles heterogenes rend les metriques non
#' comparables et la validation ininterpretable. Cette fonction ne tranche pas
#' a votre place : elle signale.
#'
#' @param catalogue Sortie de [dsr_catalog()].
#' @return Le catalogue, invisiblement.
#'
#' @details
#' A COMPLETER (lot 0) : determiner empiriquement ou se lit la version de
#' classification (V5 ou anterieure). Candidats a inspecter sur vos dalles :
#' le champ `Generating Software`, le `System Identifier`, les VLR, ou la
#' presence des attributs supplementaires identifiant les points retenus pour
#' le calcul du MNT et du MNS. Tant que la regle n'est pas etablie, on se
#' contente de remonter l'annee de creation et le logiciel.
#'
#' @noRd
dsr_verifier_homogeneite <- function(catalogue) {
  if (!"annee" %in% names(catalogue)) return(invisible(catalogue))
  annees <- sort(unique(stats::na.omit(catalogue$annee)))
  logs   <- sort(unique(stats::na.omit(catalogue$logiciel)))
  if (length(annees) > 1L) {
    dsr_inform(c("!" = "Catalogue heterogene : {length(annees)} annees de production ({annees})."))
  }
  if (length(logs) > 1L) {
    dsr_inform(c("!" = "Catalogue heterogene : {length(logs)} chaines de production distinctes."))
  }
  invisible(catalogue)
}
