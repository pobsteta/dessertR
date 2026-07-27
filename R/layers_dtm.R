# Canal geomorphologique (MNT). Voir BRIEF section 3.2.
#
# Ce fichier expose pour l'instant deux briques :
#   - dsr_grille_reference() : la grille metrique unique sur laquelle TOUTES les
#     sorties raster sont alignees (section 3.1). Derivee du MNT, a 1 m par defaut.
#   - dsr_canaux_externes() : ingestion de canaux morphometriques deja calcules
#     ailleurs (openness, SVF, SLRM, vesselness...) et alignement sur cette grille.
#
# L'ingestion couvre le cas ou l'openness/SVF sont produits par un outil externe
# valide plutot que recalcules ici : le paquet 'foretaccess' expose micro_relief()
# (noyau Rust rvt_svf_opns, portage RVT valide) qui rend exactement les bandes
# brutes svf / openness_pos / openness_neg attendues. Le BRIEF (section 6) prevoit
# ce pre-traitement optionnel documente au lieu d'une dependance Python (RVT).
#
# ATTENTION : on ingere les BANDES BRUTES CONTINUES (openness en degres, SVF en
# 0-1), jamais un composite de visualisation etire 8 bits (CVAT / VAT). Le
# byte-scale et le melange d'un CVAT detruisent le signal continu dont les
# fonctions d'appartenance de conductivity.R ont besoin. Un tel raster est
# refuse par defaut (voir refuser_composite).

# Vocabulaire canonique des canaux geomorphologiques (BRIEF section 3.2). Les
# variantes multi-echelles se suffixent par le rayon en metres, p. ex.
# "openness_neg_5" ; la verification tolere ce suffixe. Les noms svf,
# openness_pos et openness_neg coincident avec ceux de foretaccess::micro_relief.
#' @noRd
DSR_CANAUX_DTM <- c(
  "pente", "rugosite", "openness_neg", "openness_pos", "svf",
  "slrm", "mstp", "vesselness", "theta"
)


#' Construire la grille de reference d'une dalle
#'
#' Toutes les sorties raster du paquet, quelle que soit leur origine (MNT via
#' `terra`, nuage via `lasR`, canaux importes), doivent partager une **grille
#' unique** ; sans cela l'empilement final est bancal (BRIEF section 3.1). Cette
#' grille est derivee du MNT et calee a 1 m par defaut : le MNT Lidar HD a 50 cm
#' est trop fin pour les couches morphometriques multi-echelles, ou il n'apporte
#' que du bruit d'interpolation pour un cout multiplie par quatre (section 3.2).
#'
#' L'emprise est calee sur des multiples de la resolution, pour que deux dalles
#' voisines produisent des grilles jointives.
#'
#' @param mnt Un `SpatRaster` (le MNT), ou un chemin vers un GeoTIFF.
#' @param res Resolution de la grille en metres. Defaut 1
#'   (`DSR_RES_MULTIECHELLE`). Descendre a 0.5 uniquement pour la mesure fine.
#'
#' @return Un `SpatRaster` **sans valeurs** servant de gabarit d'alignement.
#'
#' @seealso [dsr_canaux_externes()] qui aligne des canaux sur cette grille.
#' @export
dsr_grille_reference <- function(mnt, res = DSR_RES_MULTIECHELLE) {
  if (is.character(mnt)) mnt <- terra::rast(mnt)
  if (!inherits(mnt, "SpatRaster")) {
    dsr_abort("{.arg mnt} doit etre un {.cls SpatRaster} ou un chemin de fichier.")
  }
  if (terra::nlyr(mnt) > 1L) mnt <- mnt[[1]]

  e <- terra::ext(mnt)
  # Caler l'emprise sur des multiples de `res` : grille jointive entre dalles.
  xmin <- floor(e[1] / res) * res
  ymin <- floor(e[3] / res) * res
  xmax <- ceiling(e[2] / res) * res
  ymax <- ceiling(e[4] / res) * res

  terra::rast(
    xmin = xmin, xmax = xmax, ymin = ymin, ymax = ymax,
    resolution = res, crs = terra::crs(mnt)
  )
}


#' Ingerer des canaux morphometriques externes et les aligner
#'
#' Reprend des canaux geomorphologiques deja calcules ailleurs -- typiquement
#' l'openness et le SVF produits par un outil valide plutot que recalcules ici --
#' et les depose sur la grille de reference de la dalle (BRIEF sections 3.1 et 6).
#' Chaque canal est reprojete puis reechantillonne sur la grille ; un canal deja
#' cale dessus est simplement recadre, sans reechantillonnage.
#'
#' Source recommandee : `foretaccess::micro_relief()`, dont le noyau Rust est un
#' portage valide de la Relief Visualization Toolbox et qui rend directement les
#' bandes `svf`, `openness_pos` et `openness_neg` (memes noms que le vocabulaire
#' interne). Alimente-le avec la grille de reference 1 m de la dalle et
#' l'alignement est exact.
#'
#' @param couches Liste **nommee** : nom de canal -> chemin de GeoTIFF ou
#'   `SpatRaster`. Les noms attendus figurent dans [DSR_CANAUX_DTM] ; les
#'   variantes multi-echelles se suffixent par le rayon (`openness_neg_5`). Le
#'   vocabulaire connu figure dans `DSR_CANAUX_DTM` ; un nom hors vocabulaire est
#'   accepte mais signale (garde-fou anti-faute).
#' @param reference Grille de reference : un `SpatRaster` gabarit (typiquement la
#'   sortie de [dsr_grille_reference()]) ou un chemin.
#' @param methode Methode de reechantillonnage par defaut : `"bilinear"`
#'   (continu, defaut), `"near"` (categoriel ou angulaire), `"cubic"`,
#'   `"average"`.
#' @param methodes Liste nommee optionnelle pour surcharger la methode canal par
#'   canal, p. ex. `list(theta = "near")` pour une orientation angulaire.
#' @param refuser_composite Si `TRUE` (defaut), rejette un raster 8 bits
#'   (0-255) : c'est la signature d'un composite RVT etire (CVAT / VAT), un
#'   produit de visualisation incompatible avec les fonctions d'appartenance de
#'   la conductivite. Mettre `FALSE` seulement pour un fond de carte assume.
#'
#' @return Un `SpatRaster` multi-bandes aligne sur `reference`, une bande par
#'   canal, nommee comme les entrees de `couches`.
#'
#' @seealso [dsr_grille_reference()].
#'
#' @examples
#' \donttest{
#' mnt <- terra::rast(
#'   xmin = 0, xmax = 20, ymin = 0, ymax = 20, resolution = 0.5,
#'   crs = "EPSG:2154"
#' )
#' terra::values(mnt) <- runif(terra::ncell(mnt))
#' grille <- dsr_grille_reference(mnt, res = 1)
#'
#' # Un canal openness deja calcule (ici bidon) a 0.5 m, aligne sur la grille 1 m
#' opns <- terra::rast(mnt)
#' terra::values(opns) <- runif(terra::ncell(opns), 60, 90)
#' pile <- dsr_canaux_externes(list(openness_neg = opns), reference = grille)
#' names(pile)
#' }
#' @export
dsr_canaux_externes <- function(couches, reference,
                                methode = c("bilinear", "near", "cubic", "average"),
                                methodes = NULL,
                                refuser_composite = TRUE) {
  methode <- match.arg(methode)
  if (!is.list(couches) || length(couches) == 0L ||
        is.null(names(couches)) || any(!nzchar(names(couches)))) {
    dsr_abort(
      "{.arg couches} doit etre une liste nommee non vide : nom de canal -> chemin ou {.cls SpatRaster}."
    )
  }

  if (is.character(reference)) reference <- terra::rast(reference)
  if (!inherits(reference, "SpatRaster")) {
    dsr_abort("{.arg reference} doit etre un {.cls SpatRaster} ou un chemin de fichier.")
  }
  grille <- terra::rast(reference) # gabarit sans valeurs

  charger_un <- function(nom, src) {
    r <- if (is.character(src)) terra::rast(src) else src
    if (!inherits(r, "SpatRaster")) {
      dsr_abort("Canal {.val {nom}} : ni chemin ni {.cls SpatRaster}.")
    }
    if (terra::nlyr(r) > 1L) {
      dsr_inform(c(
        "!" = "Canal {.val {nom}} : {terra::nlyr(r)} bandes, seule la premiere est reprise."
      ))
      r <- r[[1]]
    }
    if (isTRUE(refuser_composite) && dsr_est_composite(r)) {
      dsr_abort(c(
        "Canal {.val {nom}} : raster 8 bits (0-255) detecte, probablement un composite RVT etire (CVAT / VAT).",
        "i" = "La conductivite exige des bandes brutes continues (openness en degres, SVF en 0-1), pas un produit de visualisation.",
        "i" = "Pour un fond de carte assume, passer {.code refuser_composite = FALSE}."
      ))
    }
    meth_r <- if (!is.null(methodes) && nom %in% names(methodes)) methodes[[nom]] else methode
    dsr_avertir_angle(nom, meth_r)
    dsr_aligner(r, grille, meth_r)
  }

  lyrs <- Map(charger_un, names(couches), couches)
  out <- terra::rast(lyrs)
  names(out) <- names(couches)

  # Signaler les noms hors vocabulaire (faute de frappe probable), sans bloquer.
  # On tolere le suffixe multi-echelle "_<rayon>".
  bases <- sub("_[0-9]+$", "", names(couches))
  inconnus <- names(couches)[!bases %in% DSR_CANAUX_DTM]
  if (length(inconnus)) {
    dsr_inform(c(
      "i" = "Canaux hors vocabulaire courant (verifier l'orthographe) : {.val {inconnus}}.",
      "i" = "Vocabulaire connu : {.val {DSR_CANAUX_DTM}}."
    ))
  }
  out
}


#' Canaux de micro-relief openness et SVF d'un MNT
#'
#' Derive le **sky-view factor** et l'**openness** (positive et negative) d'un
#' modele de terrain -- les canaux morphometriques qui portent la signature d'une
#' desserte (depression de plateforme, talus amont et aval, fosses lateraux) bien
#' mieux que le MNT brut (BRIEF section 3.2). Enveloppe SIG du noyau Rust
#' `rvt_svf_opns` (portage valide de la Relief Visualization Toolbox, Apache 2.0,
#' vendorise depuis le paquet `foretaccess`) : le balayage d'horizon vit dans le
#' crate, `terra` ne fait que recoller les canaux sur la grille du MNT.
#'
#' @details
#' L'**openness negative** est l'openness du MNT **inverse** (elle allume les
#' talus amont et les fosses), calculee ici en passant le noyau sur `-z`.
#'
#' Le rayon de recherche est donne en **metres** et converti en pixels selon la
#' resolution du MNT. Alimenter un MNT a **1 m ou plus grossier** (voir
#' [dsr_grille_reference()]) : a 50 cm le balayage coute ~4 fois plus et le petit
#' rayon ne capte que du bruit d'interpolation. Pour la pile multi-echelle du
#' BRIEF, appeler la fonction a plusieurs rayons (2 / 5 / 10 m).
#'
#' @param mnt Le MNT, `SpatRaster` mono-couche (cellules supposees carrees ; la
#'   premiere couche est prise si plusieurs) ou chemin de GeoTIFF.
#' @param radius_m Rayon de recherche d'horizon maximal, en **metres**. Defaut 10.
#' @param radius_min_m Rayon minimal en metres (reduction du bruit). Defaut
#'   `NULL` -> un pixel.
#' @param num_directions Nombre de directions azimutales balayees. Defaut 16.
#' @param canaux Canaux a renvoyer, parmi `"svf"`, `"openness_pos"`,
#'   `"openness_neg"`. Defaut : les trois.
#'
#' @return Un `SpatRaster` aligne sur `mnt`, une couche par canal demande
#'   (`svf` en 0..1, `openness_pos`/`openness_neg` en degres), `NA` la ou le MNT
#'   est `NA`. Les noms coincident avec le vocabulaire de [dsr_canaux_externes()].
#'
#' @seealso [dsr_grille_reference()], [dsr_canaux_externes()].
#' @examples
#' mnt <- terra::rast(
#'   nrows = 30, ncols = 30, xmin = 0, xmax = 30, ymin = 0, ymax = 30,
#'   crs = "EPSG:2154"
#' )
#' terra::values(mnt) <- 100 # terrain plat -> svf = 1, openness = 90
#' mr <- dsr_micro_relief(mnt, radius_m = 5)
#' names(mr)
#' @export
dsr_micro_relief <- function(mnt, radius_m = 10, radius_min_m = NULL,
                             num_directions = 16L,
                             canaux = c("svf", "openness_pos", "openness_neg")) {
  if (is.character(mnt)) mnt <- terra::rast(mnt)
  if (!inherits(mnt, "SpatRaster")) {
    dsr_abort("{.arg mnt} doit etre un {.cls SpatRaster} ou un chemin de fichier.")
  }
  if (terra::nlyr(mnt) > 1L) mnt <- mnt[[1]]
  canaux <- match.arg(canaux, c("svf", "openness_pos", "openness_neg"),
    several.ok = TRUE
  )

  reso <- terra::res(mnt)
  if (abs(reso[1] - reso[2]) > 1e-6 * reso[1]) {
    dsr_inform(c(
      "!" = "Cellules non carrees ({reso[1]} x {reso[2]}) : la resolution {.val {reso[1]}} (axe X) est utilisee pour l'angle vertical."
    ))
  }
  res_m <- reso[1]
  radius_max_px <- max(1, round(radius_m / res_m))
  radius_min_px <- if (is.null(radius_min_m)) 1 else max(1, round(radius_min_m / res_m))

  nr <- terra::nrow(mnt)
  nc <- terra::ncol(mnt)
  z <- terra::values(mnt, mat = FALSE) # ordre ligne-major, comme le noyau Rust

  want_svf  <- "svf" %in% canaux
  want_opos <- "openness_pos" %in% canaux
  want_oneg <- "openness_neg" %in% canaux

  couches <- list()
  # SVF et openness positive sortent du MEME balayage (sur le MNT).
  if (want_svf || want_opos) {
    r <- rvt_svf_opns(
      z, nr, nc, res_m, radius_max_px, radius_min_px,
      num_directions, want_svf, want_opos
    )
    if (want_svf) couches$svf <- r$svf
    if (want_opos) couches$openness_pos <- r$opns
  }
  # Openness negative = openness du MNT INVERSE.
  if (want_oneg) {
    r <- rvt_svf_opns(
      -z, nr, nc, res_m, radius_max_px, radius_min_px,
      num_directions, FALSE, TRUE
    )
    couches$openness_neg <- r$opns
  }

  ordre <- intersect(c("svf", "openness_pos", "openness_neg"), names(couches))
  lyrs <- lapply(ordre, function(nm) {
    rr <- terra::rast(mnt)
    terra::values(rr) <- couches[[nm]]
    names(rr) <- nm
    rr
  })
  do.call(c, lyrs)
}


# Aligner un raster sur la grille de reference. Reprojection si CRS different,
# recadrage exact si deja sur la grille (evite un reechantillonnage inutile),
# reechantillonnage sinon.
#' @noRd
dsr_aligner <- function(r, grille, methode) {
  if (!terra::same.crs(r, grille)) {
    return(terra::project(r, grille, method = methode))
  }
  if (dsr_meme_grille(r, grille)) {
    return(terra::crop(r, grille, extend = TRUE))
  }
  terra::resample(r, grille, method = methode)
}


# Deux rasters partagent-ils resolution ET origine (donc la meme grille) ?
#' @noRd
dsr_meme_grille <- function(a, b, tol = 1e-6) {
  all(abs(terra::res(a) - terra::res(b)) < tol) &&
    all(abs(terra::origin(a) - terra::origin(b)) < tol)
}


# Un raster est-il un composite de visualisation 8 bits (CVAT / VAT) ? Le
# type INT1U (un octet) en est la signature ; un canal brut est flottant. On
# teste aussi le nom de bande. Lecture d'en-tete uniquement, aucun pixel decode.
#' @noRd
dsr_est_composite <- function(r) {
  dt <- tryCatch(terra::datatype(r)[1], error = function(e) NA_character_)
  isTRUE(grepl("INT1U", dt, fixed = TRUE)) ||
    any(tolower(names(r)) %in% c("cvat", "vat"))
}


# Une donnee angulaire (orientation, aspect) ne s'interpole pas lineairement :
# le repli 0/360 fausse le resultat. Signaler si on la reechantillonne autrement
# qu'au plus proche voisin.
#' @noRd
dsr_avertir_angle <- function(nom, methode) {
  if (grepl("theta|orient|aspect|azimut", nom, ignore.case = TRUE) &&
        methode != "near") {
    dsr_inform(c(
      "!" = "Canal {.val {nom}} : donnee angulaire reechantillonnee en {.val {methode}} ; le repli 0/360 fausse l'interpolation.",
      "i" = 'Preferer {.code methodes = list("{nom}" = "near")}.'
    ))
  }
}
