# Detection de la desserte ABSENTE de la reference (BRIEF section 3.9, v2). Le
# gisement le plus important : pistes, cloisonnements, anciennes RF que la
# BD TOPO ne porte pas.
#
# Trois etages separes, chacun utilisable seul :
#   1. dsr_indice_detection() : fusionne les signaux en une carte de probabilite
#      `p_desserte`, hors du corridor de reference. Le nuage change la donne ici
#      (BRIEF 3.9) : un cloisonnement se voit surtout par la DISCONTINUITE du
#      sous-etage (sigma_surf) et l'orniere, pas par la geomorphologie seule --
#      d'ou le poids majoritaire donne au canal de surface.
#   2. dsr_vectoriser() : passe de la carte a des LINESTRING. Vectoriseur
#      enfichable : agent conducteur natif (defaut, voir agent.R),
#      squelettisation interne, ou l'ACP historique.
#   3. dsr_detecter() : enchaine les deux.
#
# Sur le choix du vectoriseur : les methodes apprises (SAM-Road, RNGDet++,
# GLD-Road) dominent sur les jeux satellite mais supposent GPU, PyTorch et un
# corpus annote massif -- hors d'atteinte ici et contraire au parti pris « pas
# de Python en Imports » (BRIEF section 6). La squelettisation Zhang-Suen suivie
# d'un tracage de graphe est deterministe, sans dependance, et gere les
# embranchements (peignes de cloisonnements) que l'ACP ecrase en une seule ligne.


#' Indice de detection de desserte hors reference
#'
#' Fusionne les signaux disponibles en une carte de probabilite `p_desserte`
#' dans `[0, 1]`, **hors du corridor du reseau de reference** (BRIEF section
#' 3.9). C'est l'entree de [dsr_vectoriser()].
#'
#' @details
#' La fusion est une **moyenne geometrique ponderee**, comme
#' [dsr_conductivite()]. Le poids par defaut privilegie le canal de surface :
#' pistes de debardage et cloisonnements se lisent d'abord dans la
#' **discontinuite du sous-etage** — une trouee lineaire persistante — et non
#' dans le terrain, ou leur empreinte est faible ou noyee dans les traces
#' fossiles (BRIEF section 3.9 et risque n.1).
#'
#' `vesselness` n'entre pas en dur mais via une rampe croissante a partir de
#' `seuil_vessel` ([dsr_appartenance()]), pour ne pas annuler brutalement une
#' cellule par ailleurs convaincante.
#'
#' @param sigma_geo Conductivite geomorphologique ([dsr_conductivite()]),
#'   `SpatRaster`.
#' @param sigma_surf Conductivite de surface ([dsr_sigma_surf()]) ; `NULL` pour
#'   se passer du canal nuage (detection nettement moins sure).
#' @param vesselness Raster de linearite ([dsr_layers_dtm()]) ; `NULL` pour
#'   l'ignorer.
#' @param poids Vecteur nomme des poids `geo`, `surf` et `vessel`. Defaut
#'   `c(geo = 1, surf = 2, vessel = 1)`. Un poids nul ou un canal absent retire
#'   simplement le terme.
#' @param seuil_vessel Debut de la rampe d'appartenance sur `vesselness`. Defaut
#'   0.3.
#' @param reference `sf`/`sfc` du reseau de reference (BD TOPO) a exclure ;
#'   `NULL` pour ne rien exclure.
#' @param buffer_ref Demi-largeur (m) du corridor de reference a exclure. Defaut
#'   15.
#' @param emprise `sf`/`sfc` polygonal restreignant la zone balayee (regime
#'   `corridor`) ; `NULL` pour balayer toute la grille (regime `complet`).
#'
#' @return Un `SpatRaster` mono-couche `p_desserte`, `NA` hors emprise et dans
#'   le corridor de reference.
#' @seealso [dsr_vectoriser()], [dsr_detecter()], [dsr_conductivite()].
#' @examples
#' \donttest{
#' sg <- terra::rast(
#'   nrows = 40, ncols = 40, xmin = 0, xmax = 40, ymin = 0, ymax = 40,
#'   crs = "EPSG:2154"
#' )
#' terra::values(sg) <- 0.2
#' p <- dsr_indice_detection(sg)
#' }
#' @export
dsr_indice_detection <- function(sigma_geo, sigma_surf = NULL, vesselness = NULL,
                                 poids = c(geo = 1, surf = 2, vessel = 1),
                                 seuil_vessel = 0.3, reference = NULL,
                                 buffer_ref = 15, emprise = NULL) {
  if (!inherits(sigma_geo, "SpatRaster")) {
    dsr_abort("{.arg sigma_geo} doit etre un {.cls SpatRaster}.")
  }
  if (terra::nlyr(sigma_geo) != 1L) {
    dsr_abort("{.arg sigma_geo} doit etre mono-couche ({terra::nlyr(sigma_geo)} bandes fournies).")
  }
  eps <- 1e-6
  log_acc <- rep(0, terra::ncell(sigma_geo))
  poids_tot <- 0

  w <- .dsr_poids(poids, "geo")
  if (w > 0) {
    mu <- pmin(pmax(terra::values(sigma_geo, mat = FALSE), 0), 1)
    log_acc <- log_acc + w * log(pmax(mu, eps))
    poids_tot <- poids_tot + w
  }
  if (!is.null(sigma_surf)) {
    w <- .dsr_poids(poids, "surf")
    if (w > 0) {
      mu <- pmin(pmax(terra::values(sigma_surf, mat = FALSE), 0), 1)
      log_acc <- log_acc + w * log(pmax(mu, eps))
      poids_tot <- poids_tot + w
    }
  }
  if (!is.null(vesselness)) {
    w <- .dsr_poids(poids, "vessel")
    if (w > 0) {
      mu <- terra::values(
        dsr_appartenance(vesselness, "croissante", a = seuil_vessel, b = 1),
        mat = FALSE
      )
      log_acc <- log_acc + w * log(pmax(mu, eps))
      poids_tot <- poids_tot + w
    }
  }
  if (poids_tot <= 0) {
    dsr_abort(c(
      "Aucun canal ne contribue a l'indice de detection.",
      "i" = "Verifier {.arg poids} : au moins un poids doit etre strictement positif."
    ))
  }

  out <- terra::rast(sigma_geo)
  terra::values(out) <- exp(log_acc / poids_tot)
  names(out) <- "p_desserte"

  if (!is.null(emprise)) {
    emp <- sf::st_as_sf(sf::st_union(sf::st_geometry(emprise)))
    out <- terra::mask(out, terra::vect(emp))
  }
  if (!is.null(reference) && buffer_ref > 0) {
    buf <- sf::st_buffer(sf::st_union(sf::st_geometry(reference)), buffer_ref)
    out <- terra::mask(out, terra::vect(sf::st_as_sf(buf)), inverse = TRUE)
  }
  out
}


#' Vectoriser une carte de desserte
#'
#' Passe d'une carte de probabilite ([dsr_indice_detection()], ou toute
#' conductivite) a une collection de `LINESTRING`. Le vectoriseur est
#' **enfichable** : la porte reste ouverte a un backend appris sans changer
#' l'interface.
#'
#' @details
#' Trois methodes :
#'
#' * `"squelette"` — binarisation a `seuil`, amincissement de
#'   **Zhang-Suen**, puis tracage du graphe du squelette : chaque chaine entre
#'   deux noeuds (extremite ou embranchement) devient une arete. Deterministe,
#'   sans dependance, et surtout **il conserve les embranchements** : un peigne
#'   de cloisonnements sort en autant de lignes, la ou `"acp"` l'ecrase en une.
#'   Le graphe est ensuite nettoye (`elaguer`) : contraction des grappes de
#'   jonction, elagage des barbules, fusion des chaines. Sans cette etape, les
#'   bavures de bord d'une emprise binarisee reelle hachent une piste de 190 m en
#'   plusieurs dizaines de troncons dont aucun n'atteint `long_min`.
#' * `"agent"` (defaut) — **agent conducteur** ([dsr_conduire()]) : la route est
#'   vectorisee en la parcourant, l'agent avancant par pas vers la direction la
#'   moins couteuse de son champ de vision. Reimplementation terra/sf de
#'   l'algorithme de vecnet (Roussel *et al.* 2023) sur le noyau Rust du paquet.
#'   Deux atouts sur le squelette : il **franchit les trouees** de detection, et
#'   il rend des lignes lisses sans passer par un escalier de pixels. Il exige
#'   en revanche des **amorces** ([dsr_amorces()]) : fournir `reference` est de
#'   loin le meilleur amorcage, les extremites du reseau connu pointant la ou
#'   commence la desserte qui manque.
#' * `"acp"` — methode historique : composantes connexes, puis centre-ligne par
#'   analyse en composantes principales. Rapide, mais une composante donne une
#'   seule ligne ; ne convient qu'aux axes isoles et bien allonges.
#'
#' **Lissage de la centre-ligne.** Le squelette d'une emprise rasterisee est un
#' escalier : chaque virage y est un ressaut de 0 ou 45 degres. Ce n'est pas
#' cosmetique — [dsr_measure()] en tire `RAYON_COURBURE` et `SINUOSITE`, et
#' [dsr_trafficability()] en deduit l'aptitude grumier. `lissage` corrige cela :
#'
#' * `"savitzky-golay"` (defaut) — ajustement polynomial local sur `x(t)` et
#'   `y(t)` (Wang *et al.* 2025). Filtre local : conserve la longueur et ne
#'   rabote pas les virages francs.
#' * `"bezier"` — ajustement de Bezier cubiques par morceaux aux moindres
#'   carres, avec decoupe recursive sur l'erreur maximale, puis
#'   reechantillonnage. C'est la representation de DOGE (Sun *et al.* 2025)
#'   ramenee a un ajustement direct, sans optimisation differentiable. Elle
#'   donne une courbe **C1 par morceaux**, analytiquement derivable, dont le pas
#'   de reechantillonnage se choisit librement. Deux reserves mesurees sur un arc
#'   de reference : elle est moins fidele que Savitzky-Golay (ecart median a la
#'   courbe vraie 0,39 m contre 0,13 m), et sa compacite reside dans les points
#'   de controle — le `LINESTRING` rendu etant reechantillonne, il n'a pas moins
#'   de sommets que l'escalier d'origine. A choisir pour la continuite, pas pour
#'   la precision.
#' * `"aucun"` — l'escalier brut.
#'
#' Dans les deux cas **les extremites sont figees** : elles portent la topologie
#' que [dsr_reseau()] reconstruit ensuite.
#'
#' **Raccordement des trouees.** `raccorder` relie deux extremites de
#' composantes distinctes separees par une trouee de conductivite (couvert
#' dense, franchissement). Au critere de distance de Wang *et al.* on ajoute un
#' critere d'alignement, faute de quoi une piste serait soudee au cloisonnement
#' voisin qu'elle croise sans le rejoindre. Cette etape **invente de la
#' geometrie la ou la donnee ne montre rien** : elle est desactivee par defaut.
#'
#' `"auto"` prend `"agent"`. Si l'agent echoue -- ou si aucune amorce n'est
#' exploitable, faute de reference et de route touchant le bord de l'emprise --
#' le repli sur le squelette est signale. Demande explicitement, son echec est
#' une erreur et l'absence d'amorce rend un resultat vide.
#'
#' `"vecnet"` reste accepte et vaut `"agent"` : le paquet externe du meme nom a
#' ete remplace par une implementation native, sans dependance.
#'
#' Le cout de l'amincissement croit avec la demi-largeur des taches : sur une
#' carte tres bruitee, relever `seuil` avant d'elargir la grille.
#'
#' @param p `SpatRaster` mono-couche de probabilite / conductivite.
#' @param seuil Seuil de binarisation pour `"squelette"` et `"acp"`. Defaut 0.6.
#' @param methode `"auto"`, `"agent"`, `"squelette"` ou `"acp"`. `"vecnet"` est
#'   accepte comme synonyme de `"agent"`.
#' @param long_min Longueur minimale (m) d'un axe retenu. Defaut 30.
#' @param ratio_min Rapport d'allongement minimal d'une composante
#'   (methode `"acp"` seulement). Defaut 3.
#' @param pas_bin Pas d'echantillonnage (m) le long de l'axe principal
#'   (methode `"acp"` seulement). Defaut 5.
#' @param elaguer Longueur (m) en deca de laquelle une barbule ou un micro-lien
#'   de carrefour est retire du graphe du squelette ; `0` ou `NULL` pour ne rien
#'   nettoyer. Defaut 5. Methode `"squelette"` seulement.
#' @param lissage Lissage de la centre-ligne, methode `"squelette"` seulement :
#'   `"savitzky-golay"` (defaut), `"bezier"` ou `"aucun"`.
#' @param lissage_par Parametre du lissage, `NULL` pour le defaut de la
#'   methode : demi-largeur exprimee en metres pour `"savitzky-golay"`
#'   (defaut 7), tolerance d'ajustement en metres pour `"bezier"` (defaut : la
#'   resolution de `p`).
#' @param raccorder Distance (m) en deca de laquelle deux extremites de
#'   composantes distinctes et **alignees** sont reliees, pour franchir une
#'   trouee de conductivite. `0` (defaut) pour ne rien raccorder.
#' @param simplifier Tolerance (m) de simplification Douglas-Peucker des lignes
#'   produites ; `0` ou `NULL` pour ne pas simplifier. Defaut 1.
#' @param reference `sf`/`sfc` du reseau deja connu. Pour `"agent"`, il sert
#'   deux fois : ses extremites amorcent l'exploration, et il est infranchissable
#'   (l'agent s'y arrete au lieu de le revectoriser). Ignore par les autres
#'   methodes.
#' @param ... Arguments supplementaires transmis a [dsr_conduire()].
#'
#' @return Un `sf` `LINESTRING` (colonnes `id`, `longueur`), vide si rien n'est
#'   retenu. L'attribut `"methode"` porte le vectoriseur reellement employe.
#' @references
#' Roussel, J.-R., Bourdon, J.-F., Morley, I. D., Coops, N. C., &
#'   Achim, A. (2023). Vectorial and topologically valid segmentation of
#'   forestry road networks from ALS data. *IJAEOG*, 118, 103267.
#'   \doi{10.1016/j.jag.2023.103267}
#'
#' Wang, X., Ibrahim, M., Mansoor, A., Tareque, H., & Mian, A. (2025).
#'   Automated Road Extraction and Centreline Fitting in LiDAR Point Clouds.
#'   \emph{arXiv:2502.07486}.
#'
#' Sun, J., Lu, J., Yin, J., Xu, Y., Li, Y., & Guo, Y. (2025). DOGE:
#'   Differentiable Bezier Graph Optimization for Road Network Extraction.
#'   \emph{arXiv:2511.19850}.
#' @seealso [dsr_indice_detection()], [dsr_detecter()], [dsr_reseau()].
#' @export
dsr_vectoriser <- function(p, seuil = 0.6,
                           methode = c("auto", "agent", "squelette", "vecnet", "acp"),
                           long_min = 30, ratio_min = 3, pas_bin = 5,
                           elaguer = 5,
                           lissage = c("savitzky-golay", "bezier", "aucun"),
                           lissage_par = NULL, raccorder = 0,
                           simplifier = 1, reference = NULL, ...) {
  methode <- match.arg(methode)
  lissage <- match.arg(lissage)
  if (!inherits(p, "SpatRaster")) {
    dsr_abort("{.arg p} doit etre un {.cls SpatRaster}.")
  }
  if (terra::nlyr(p) != 1L) {
    dsr_abort("{.arg p} doit etre mono-couche ({terra::nlyr(p)} bandes fournies).")
  }
  crs <- sf::st_crs(terra::crs(p))
  demande <- methode
  # `"vecnet"` designait le paquet externe du meme nom, remplace par l'agent
  # conducteur natif ([dsr_conduire()]). Le nom reste accepte pour ne pas casser
  # le code existant, mais il ne charge plus aucune dependance.
  if (methode == "vecnet") {
    dsr_inform(c(
      "i" = "{.code methode = \"vecnet\"} vaut desormais {.code \"agent\"} : le vectoriseur est natif.",
      "i" = "Voir {.fn dsr_conduire}."
    ))
    methode <- demande <- "agent"
  }
  if (methode == "auto") methode <- "agent"

  if (methode == "agent") {
    res <- tryCatch(.dsr_vectoriser_agent(p, long_min, reference, seuil = seuil, ...),
      error = function(e) e)
    if (inherits(res, "error")) {
      if (demande == "agent") {
        cli::cli_abort("Le vectoriseur par agent a echoue.", parent = res)
      }
      dsr_inform(c(
        "!" = "Le vectoriseur par agent a echoue ; repli sur le squelette interne.",
        "i" = "Forcer {.code methode = \"agent\"} pour voir l'erreur d'origine."
      ))
      methode <- "squelette"
    } else if (length(res) > 0L) {
      return(.dsr_finaliser_lignes(res, crs, long_min, simplifier, "agent"))
    } else {
      # Aucune amorce exploitable (ni reference, ni route touchant le bord).
      # Le squelette, lui, n'a pas besoin d'amorce : c'est le bon repli.
      if (demande == "agent") {
        return(.dsr_finaliser_lignes(list(), crs, long_min, simplifier, "agent"))
      }
      dsr_inform(c(
        "!" = "Aucune amorce exploitable pour l'agent ; repli sur le squelette interne.",
        "i" = "Fournir {.arg reference} pour amorcer l'exploration depuis le reseau connu."
      ))
      methode <- "squelette"
    }
  }

  lignes <- if (methode == "acp") {
    .dsr_lignes_acp(p, seuil, long_min, ratio_min, pas_bin)
  } else {
    .dsr_lignes_squelette(p, seuil, elaguer, lissage, lissage_par, raccorder)
  }
  .dsr_finaliser_lignes(lignes, crs, long_min, simplifier, methode)
}


#' Detecter la desserte hors reference
#'
#' Repere les axes de desserte probables **absents du reseau de reference** :
#' construit la carte `p_desserte` hors du corridor de reference
#' ([dsr_indice_detection()]), puis la vectorise ([dsr_vectoriser()]).
#' Complementaire du recalage, qui lui conserve la reference
#' ([dsr_repositionner()]).
#'
#' @details
#' **Regimes.** `"complet"` balaie toute la grille (moins le corridor de
#' reference) : c'est le regime de la v2, celui qui trouve ce que la BD TOPO
#' ignore. `"corridor"` restreint a une `emprise` fournie, utile pour instruire
#' un secteur sans payer le cout d'une dalle entiere.
#'
#' **Le nuage est ici decisif.** Sans `sigma_surf`, la detection repose sur la
#' seule geomorphologie et rallume toutes les traces fossiles (chemins creux,
#' limites parcellaires, anciennes RF) — le risque n.1 du BRIEF. Fournir
#' `sigma_surf` fait la difference entre une piste reellement ouverte et une
#' cicatrice du terrain.
#'
#' Le resultat est une collection d'aretes coherentes (les embranchements
#' partagent leurs extremites) : la passer a [dsr_reseau()] donne directement un
#' graphe valide.
#'
#' @param sigma_geo Conductivite geomorphologique ([dsr_conductivite()]),
#'   `SpatRaster`.
#' @param reference `sf`/`sfc` du reseau de reference (BD TOPO) a exclure ;
#'   `NULL` pour ne rien exclure.
#' @param vesselness Raster de linearite ([dsr_layers_dtm()]) pour privilegier
#'   les structures lineaires ; `NULL` pour l'ignorer.
#' @param sigma_surf Conductivite de surface ([dsr_sigma_surf()]) — le canal qui
#'   distingue une piste ouverte d'une trace fossile ; `NULL` pour s'en passer.
#' @param seuil Seuil de binarisation de `p_desserte`. Defaut 0.6.
#' @param seuil_vessel Debut de la rampe d'appartenance sur `vesselness`. Defaut
#'   0.3.
#' @param buffer_ref Demi-largeur (m) du corridor de reference a exclure. Defaut
#'   15.
#' @param long_min Longueur minimale (m) d'un axe detecte. Defaut 30.
#' @param ratio_min Rapport d'allongement minimal d'une composante
#'   (methode `"acp"` seulement). Defaut 3.
#' @param pas_bin Pas d'echantillonnage (m) le long de l'axe principal
#'   (methode `"acp"` seulement). Defaut 5.
#' @param methode Vectoriseur : `"auto"`, `"agent"`, `"squelette"` ou `"acp"`
#'   (voir [dsr_vectoriser()]).
#' @param poids Poids des canaux dans l'indice ; voir [dsr_indice_detection()].
#' @param regime `"complet"` (toute la grille) ou `"corridor"` (restreint a
#'   `emprise`).
#' @param emprise `sf`/`sfc` polygonal ; requis en regime `"corridor"`, ignore
#'   en regime `"complet"`.
#' @param elaguer Longueur (m) en deca de laquelle une barbule ou un micro-lien
#'   de carrefour est retire du graphe du squelette ; voir [dsr_vectoriser()].
#'   Defaut 5.
#' @param lissage Lissage de la centre-ligne ; voir [dsr_vectoriser()]. Defaut
#'   `"savitzky-golay"`.
#' @param lissage_par Parametre du lissage ; voir [dsr_vectoriser()].
#' @param raccorder Distance (m) de raccordement des trouees ; voir
#'   [dsr_vectoriser()]. `0` (defaut) pour ne rien raccorder.
#' @param simplifier Tolerance (m) de simplification des lignes ; `0` pour ne
#'   pas simplifier. Defaut 1.
#'
#' @return Un `sf` `LINESTRING` des axes detectes (colonnes `id`, `longueur`),
#'   ou un `sf` vide si aucun.
#' @seealso [dsr_indice_detection()], [dsr_vectoriser()], [dsr_reseau()],
#'   [dsr_conductivite()], [dsr_repositionner()].
#' @export
dsr_detecter <- function(sigma_geo, reference = NULL, vesselness = NULL,
                         sigma_surf = NULL, seuil = 0.6, seuil_vessel = 0.3,
                         buffer_ref = 15, long_min = 30, ratio_min = 3,
                         pas_bin = 5,
                         methode = c("auto", "agent", "squelette", "vecnet", "acp"),
                         poids = c(geo = 1, surf = 2, vessel = 1),
                         regime = c("complet", "corridor"), emprise = NULL,
                         elaguer = 5,
                         lissage = c("savitzky-golay", "bezier", "aucun"),
                         lissage_par = NULL, raccorder = 0, simplifier = 1) {
  methode <- match.arg(methode)
  regime <- match.arg(regime)
  lissage <- match.arg(lissage)
  if (regime == "corridor" && is.null(emprise)) {
    dsr_abort(c(
      "Le regime {.val corridor} demande une {.arg emprise} polygonale.",
      "i" = "Utiliser {.code regime = \"complet\"} pour balayer toute la grille."
    ))
  }

  p <- dsr_indice_detection(
    sigma_geo, sigma_surf = sigma_surf, vesselness = vesselness,
    poids = poids, seuil_vessel = seuil_vessel,
    reference = reference, buffer_ref = buffer_ref,
    emprise = if (regime == "corridor") emprise else NULL
  )
  dsr_vectoriser(p, seuil = seuil, methode = methode, long_min = long_min,
    ratio_min = ratio_min, pas_bin = pas_bin, elaguer = elaguer,
    lissage = lissage, lissage_par = lissage_par, raccorder = raccorder,
    simplifier = simplifier, reference = reference)
}


# --- Poids -------------------------------------------------------------------

# Lecture tolerante d'un poids nomme : canal absent du vecteur -> 0 (le terme
# disparait de la moyenne geometrique) plutot qu'une erreur d'indexation.
#' @noRd
.dsr_poids <- function(poids, nom, defaut = 0) {
  if (is.null(poids) || is.null(names(poids)) || !nom %in% names(poids)) {
    return(defaut)
  }
  v <- suppressWarnings(as.numeric(poids[[nom]]))
  if (length(v) != 1L || is.na(v)) defaut else v
}


# --- Mise en forme commune des sorties ---------------------------------------

# Liste de sfg (ou sfc) -> sf(id, longueur), simplifie et filtre en longueur.
#' @noRd
.dsr_finaliser_lignes <- function(lignes, crs, long_min, simplifier, methode) {
  vide <- sf::st_sf(id = integer(0), longueur = numeric(0),
    geometry = sf::st_sfc(crs = crs))
  attr(vide, "methode") <- methode
  if (length(lignes) == 0L) return(vide)

  g <- if (inherits(lignes, "sfc")) lignes else sf::st_sfc(lignes, crs = crs)
  if (is.na(sf::st_crs(g))) sf::st_crs(g) <- crs
  g <- suppressWarnings(sf::st_cast(g, "LINESTRING"))
  if (!is.null(simplifier) && length(simplifier) == 1L && !is.na(simplifier) &&
      simplifier > 0) {
    g <- sf::st_simplify(g, dTolerance = simplifier, preserveTopology = TRUE)
  }
  g <- g[!sf::st_is_empty(g)]
  if (length(g) == 0L) return(vide)

  lg <- as.numeric(sf::st_length(g))
  garde <- which(is.finite(lg) & lg >= long_min)
  if (length(garde) == 0L) return(vide)

  out <- sf::st_sf(id = seq_along(garde), longueur = lg[garde],
    geometry = g[garde])
  attr(out, "methode") <- methode
  out
}


# --- Vectoriseur squelette (Zhang-Suen + tracage de graphe) ------------------

# Binarise, amincit, elague, trace, raccorde puis lisse : renvoie une liste de
# LINESTRING (sfg).
#' @noRd
.dsr_lignes_squelette <- function(p, seuil, elaguer = 5,
                                  lissage = "savitzky-golay",
                                  lissage_par = NULL, raccorder = 0) {
  m <- terra::as.matrix(p, wide = TRUE)
  bin <- matrix(0L, nrow(m), ncol(m))
  bin[!is.na(m) & m >= seuil] <- 1L
  if (!any(bin == 1L)) return(list())

  res <- terra::res(p)[1]
  min_cells <- if (is.null(elaguer) || length(elaguer) != 1L || is.na(elaguer) ||
      elaguer <= 0) {
    0L
  } else {
    max(1L, as.integer(elaguer / res))
  }
  coords <- .dsr_tracer_squelette(.dsr_amincir(bin), p, min_cells,
    geometrie = FALSE)
  if (length(coords) == 0L) return(list())

  if (!is.null(raccorder) && length(raccorder) == 1L && !is.na(raccorder) &&
      raccorder > 0) {
    coords <- .dsr_raccorder(coords, raccorder)
  }
  coords <- .dsr_appliquer_lissage(coords, lissage, lissage_par, res)
  lapply(coords, sf::st_linestring)
}


# Application du lissage choisi a une liste de matrices de coordonnees.
# `lissage_par` a un sens different selon la methode -- fenetre pour
# Savitzky-Golay, tolerance d'ajustement pour Bezier -- d'ou le defaut resolu
# ici plutot que dans la signature.
#' @noRd
.dsr_appliquer_lissage <- function(coords, lissage, lissage_par, res) {
  lissage <- match.arg(lissage, c("savitzky-golay", "bezier", "aucun"))
  if (identical(lissage, "aucun")) return(coords)

  if (identical(lissage, "savitzky-golay")) {
    fenetre <- if (is.null(lissage_par)) 7 else lissage_par
    demi <- max(1L, as.integer(floor((fenetre / res) / 2)))
    return(lapply(coords, .dsr_lisser_sg, demi = demi))
  }
  # Une tolerance de l'ordre de la resolution ferait poursuivre a l'ajustement
  # le bruit de quantification du squelette (mesure : 16 courbes au lieu de 3
  # sur un arc propre). On la place au-dessus de ce plancher de bruit.
  tol <- if (is.null(lissage_par)) 2 * res else lissage_par
  lapply(coords, .dsr_lisser_bezier, tol = tol, pas = res)
}


# Decalage d'une matrice avec remplissage a 0 : o[r, c] = m[r + dr, c + dc].
# dr < 0 remonte (voisin nord, la ligne 1 etant le haut de la grille terra).
#' @noRd
.dsr_decale <- function(m, dr, dc) {
  nr <- nrow(m); nc <- ncol(m)
  o <- matrix(0L, nr, nc)
  r1 <- max(1L, 1L - dr); r2 <- min(nr, nr - dr)
  c1 <- max(1L, 1L - dc); c2 <- min(nc, nc - dc)
  if (r1 > r2 || c1 > c2) return(o)
  o[r1:r2, c1:c2] <- m[(r1 + dr):(r2 + dr), (c1 + dc):(c2 + dc)]
  o
}


# Amincissement de Zhang-Suen (1984) : erode les bords sans rompre la
# connexite ni raccourcir les extremites, jusqu'a un squelette d'un pixel
# d'epaisseur. Entierement vectorise sur la matrice ; le nombre d'iterations
# necessaires vaut environ la demi-largeur de la tache la plus epaisse.
#' @noRd
.dsr_amincir <- function(bin, max_iter = 200L) {
  m <- bin
  storage.mode(m) <- "integer"
  for (it in seq_len(max_iter)) {
    n_sup <- 0L
    for (sous in 1:2) {
      p2 <- .dsr_decale(m, -1L,  0L); p3 <- .dsr_decale(m, -1L,  1L)
      p4 <- .dsr_decale(m,  0L,  1L); p5 <- .dsr_decale(m,  1L,  1L)
      p6 <- .dsr_decale(m,  1L,  0L); p7 <- .dsr_decale(m,  1L, -1L)
      p8 <- .dsr_decale(m,  0L, -1L); p9 <- .dsr_decale(m, -1L, -1L)

      # B : nombre de voisins allumes. A : nombre de transitions 0 -> 1 sur le
      # tour des 8 voisins ; A == 1 garantit que retirer le pixel ne coupe pas
      # la composante.
      b <- p2 + p3 + p4 + p5 + p6 + p7 + p8 + p9
      tour <- list(p2, p3, p4, p5, p6, p7, p8, p9, p2)
      a <- matrix(0L, nrow(m), ncol(m))
      for (k in seq_len(8L)) {
        a <- a + (tour[[k]] == 0L & tour[[k + 1L]] == 1L)
      }

      cond <- m == 1L & b >= 2L & b <= 6L & a == 1L
      cond <- if (sous == 1L) {
        cond & (p2 * p4 * p6 == 0L) & (p4 * p6 * p8 == 0L)
      } else {
        cond & (p2 * p4 * p8 == 0L) & (p2 * p6 * p8 == 0L)
      }
      if (any(cond)) {
        m[cond] <- 0L
        n_sup <- n_sup + sum(cond)
      }
    }
    if (n_sup == 0L) break
  }
  m
}


# Graphe d'un squelette : les pixels de degre != 2 sont des noeuds (extremite ou
# embranchement) ; chaque chaine de pixels de degre 2 reliant deux noeuds est une
# arete. C'est ce qui conserve les embranchements, la ou une centre-ligne par ACP
# ecrase toute la composante en une ligne unique.
# Renvoie les indices des pixels, la table de voisinage, les degres et les
# aretes (suites d'indices), ou NULL si le squelette est vide.
#' @noRd
.dsr_graphe_squelette <- function(sq) {
  idx <- which(sq == 1L)
  if (length(idx) < 2L) return(NULL)

  etiq <- matrix(0L, nrow(sq), ncol(sq))
  etiq[idx] <- seq_along(idx)
  # Voisins ordonnes N, NE, E, SE, S, SO, O, NO : la direction opposee de k est
  # ((k + 3) %% 8) + 1.
  decalages <- list(c(-1L, 0L), c(-1L, 1L), c(0L, 1L), c(1L, 1L),
    c(1L, 0L), c(1L, -1L), c(0L, -1L), c(-1L, -1L))
  vois <- matrix(0L, length(idx), 8L)
  for (k in seq_len(8L)) {
    vois[, k] <- .dsr_decale(etiq, decalages[[k]][1], decalages[[k]][2])[idx]
  }
  degre <- rowSums(vois > 0L)
  visite <- matrix(FALSE, length(idx), 8L)

  avancer <- function(depart, dir) {
    chemin <- depart
    courant <- depart; k <- dir
    repeat {
      suivant <- vois[courant, k]
      if (suivant == 0L) break
      retour <- ((k + 3L) %% 8L) + 1L
      visite[courant, k] <<- TRUE
      visite[suivant, retour] <<- TRUE
      chemin <- c(chemin, suivant)
      if (degre[suivant] != 2L) break
      libres <- which(vois[suivant, ] > 0L)
      libres <- libres[libres != retour]
      if (length(libres) == 0L) break
      courant <- suivant; k <- libres[1]
      if (visite[courant, k]) break
    }
    chemin
  }

  chemins <- list()
  for (depart in which(degre != 2L)) {
    for (k in which(vois[depart, ] > 0L)) {
      if (visite[depart, k]) next
      chemins[[length(chemins) + 1L]] <- avancer(depart, k)
    }
  }
  # Boucles fermees : aucune cellule de degre != 2, donc aucun point de depart
  # ci-dessus. On amorce sur une arete encore libre jusqu'a epuisement.
  repeat {
    reste <- which(vois > 0L & !visite)
    if (length(reste) == 0L) break
    i <- reste[1]
    depart <- ((i - 1L) %% nrow(vois)) + 1L
    k <- ((i - 1L) %/% nrow(vois)) + 1L
    chemins[[length(chemins) + 1L]] <- avancer(depart, k)
  }

  list(idx = idx, vois = vois, degre = degre, chemins = chemins)
}


# Nettoyage du graphe. C'est l'etape qui decide de la qualite du resultat, et
# elle n'est pas cosmetique. Sur une emprise binarisee reelle, les bavures de
# bord font apparaitre le long d'une meme piste des dizaines de pixels de degre
# 3 : chacun COUPE la chaine, et une route de 190 m ressort en soixante tronçons
# dont aucun n'atteint `long_min`. Trois operations, repetees jusqu'a stabilite :
#
#   1. Contraction des grappes de jonction — les pixels de degre != 2 adjacents
#      ne sont pas plusieurs carrefours mais un seul, epaissi par l'escalier.
#   2. Elagage des barbules — une arete courte finissant en cul-de-sac sur un
#      carrefour est un artefact d'amincissement, pas une desserte.
#   3. Fusion aux noeuds de degre 2 — une fois la barbule retiree, le carrefour
#      redevient un simple point de passage : les deux chaines se recollent.
#
# L'ordre compte : sans (1) l'elagage ne trouve aucune barbule (les micro-aretes
# relient deux pixels de jonction, aucun n'est une extremite libre) ; sans (3)
# l'elagage laisserait la piste coupee la ou la barbule s'inserait.
#' @noRd
.dsr_simplifier_graphe <- function(g, min_cells) {
  # (1) Grappes de jonction : composantes connexes parmi les pixels de degre != 2.
  est_noeud <- g$degre != 2L
  grappe <- integer(length(g$degre))
  ng <- 0L
  for (p in which(est_noeud)) {
    if (grappe[p] != 0L) next
    ng <- ng + 1L
    grappe[p] <- ng
    pile <- p
    while (length(pile) > 0L) {
      q <- pile[length(pile)]; pile <- pile[-length(pile)]
      vs <- g$vois[q, ]
      vs <- vs[vs > 0L]
      vs <- vs[est_noeud[vs] & grappe[vs] == 0L]
      if (length(vs) > 0L) {
        grappe[vs] <- ng
        pile <- c(pile, vs)
      }
    }
  }
  # Boucles fermees : leurs extremites sont de degre 2, donc sans grappe.
  for (ch in g$chemins) {
    for (bout in c(ch[1], ch[length(ch)])) {
      if (grappe[bout] == 0L) {
        ng <- ng + 1L
        grappe[bout] <- ng
      }
    }
  }

  # Une grappe qui contient un pixel de degre >= 3 est un vrai carrefour epaissi ;
  # une grappe faite de deux extremites libres est un fragment isole, qu'il ne
  # faut pas confondre avec un micro-lien interne.
  carrefour <- logical(ng)
  jonctions <- which(g$degre >= 3L)
  if (length(jonctions) > 0L) carrefour[grappe[jonctions]] <- TRUE

  aretes <- lapply(g$chemins, function(ch) {
    list(ch = ch, a = grappe[ch[1]], b = grappe[ch[length(ch)]])
  })
  # Micro-boucles internes a un carrefour : les liens d'un pixel de jonction a
  # son voisin de jonction. Ils n'ont pas d'existence geographique.
  aretes <- aretes[!vapply(aretes, function(e) {
    e$a == e$b && carrefour[e$a] && length(e$ch) <= min_cells + 1L
  }, logical(1))]

  repeat {
    if (length(aretes) == 0L) break
    bouts <- c(vapply(aretes, function(e) e$a, integer(1)),
      vapply(aretes, function(e) e$b, integer(1)))
    degre <- tabulate(bouts, nbins = ng)

    # (2) Elagage des barbules.
    garde <- vapply(aretes, function(e) {
      if (length(e$ch) - 1L > min_cells) return(TRUE)
      da <- degre[e$a]; db <- degre[e$b]
      !((da == 1L && db >= 3L) || (db == 1L && da >= 3L))
    }, logical(1))
    if (!all(garde)) {
      aretes <- aretes[garde]
      next
    }

    # (3) Fusion aux noeuds de degre 2, par balayage complet : on tient a jour
    # une table d'incidence plutot que de rebalayer la liste a chaque fusion,
    # sinon le nettoyage d'une dalle entiere serait quadratique.
    incidence <- vector("list", ng)
    for (i in seq_along(aretes)) {
      incidence[[aretes[[i]]$a]] <- c(incidence[[aretes[[i]]$a]], i)
      incidence[[aretes[[i]]$b]] <- c(incidence[[aretes[[i]]$b]], i)
    }
    vivant <- rep(TRUE, length(aretes))
    fusion <- FALSE

    for (n in which(degre == 2L)) {
      ii <- incidence[[n]]
      ii <- ii[vivant[ii]]
      if (length(ii) != 2L || ii[1] == ii[2]) next
      e1 <- aretes[[ii[1]]]; e2 <- aretes[[ii[2]]]
      c1 <- if (e1$b == n) e1$ch else rev(e1$ch)
      c2 <- if (e2$a == n) e2$ch else rev(e2$ch)
      suite <- if (identical(c1[length(c1)], c2[1])) c2[-1] else c2
      loin <- if (e2$a == n) e2$b else e2$a

      aretes[[ii[1]]] <- list(
        ch = c(c1, suite),
        a = if (e1$b == n) e1$a else e1$b,
        b = loin
      )
      vivant[ii[2]] <- FALSE
      incidence[[loin]] <- c(incidence[[loin]], ii[1])
      fusion <- TRUE
    }
    aretes <- aretes[vivant]
    if (!fusion) break
  }
  aretes
}


# Aretes du squelette -> coordonnees (ou LINESTRING) en unites de la grille.
# `geometrie = FALSE` renvoie les matrices brutes, pour laisser le lissage et le
# raccordement travailler avant la conversion en sfg.
#' @noRd
.dsr_tracer_squelette <- function(sq, modele, min_cells = 0L, geometrie = TRUE) {
  g <- .dsr_graphe_squelette(sq)
  if (is.null(g)) return(list())
  aretes <- .dsr_simplifier_graphe(g, min_cells)
  if (length(aretes) == 0L) return(list())

  nr <- nrow(sq)
  lig <- ((g$idx - 1L) %% nr) + 1L
  col <- ((g$idx - 1L) %/% nr) + 1L
  xy <- terra::xyFromCell(modele, terra::cellFromRowCol(modele, lig, col))

  lignes <- list()
  for (e in aretes) {
    if (length(e$ch) < 2L) next
    co <- xy[e$ch, , drop = FALSE]
    co <- co[!duplicated(co), , drop = FALSE]
    if (nrow(co) < 2L) next
    lignes[[length(lignes) + 1L]] <- if (geometrie) sf::st_linestring(co) else co
  }
  lignes
}


# --- Vectoriseur ACP (historique) --------------------------------------------

# Composantes connexes, puis une centre-ligne par composante. Conserve pour les
# axes isoles et franchement allonges ; ecrase les embranchements.
#' @noRd
.dsr_lignes_acp <- function(p, seuil, long_min, ratio_min, pas_bin) {
  cand <- terra::ifel(p >= seuil, 1L, NA_integer_)
  if (all(is.na(terra::values(cand, mat = FALSE)))) return(list())

  pat <- terra::patches(cand, directions = 8L, zeroAsNA = TRUE)
  vals <- terra::values(pat, mat = FALSE)
  ids <- sort(unique(vals[!is.na(vals)]))
  min_cells <- max(5L, as.integer(long_min / terra::res(p)[1]))

  lignes <- list()
  for (id in ids) {
    cells <- which(vals == id)
    if (length(cells) < min_cells) next
    ln <- dsr_centre_ligne_acp(terra::xyFromCell(pat, cells), pas_bin, ratio_min)
    if (is.null(ln)) next
    lignes[[length(lignes) + 1L]] <- ln
  }
  lignes
}


# Centre-ligne d'un nuage de cellules par ACP : projette sur l'axe principal,
# bille le long de cet axe et prend la position transversale mediane par bille.
# Renvoie un LINESTRING (sfg) ou NULL si la tache n'est pas assez lineaire.
#' @noRd
dsr_centre_ligne_acp <- function(xy, pas_bin, ratio_min) {
  if (nrow(xy) < 5L) return(NULL)
  ctr <- colMeans(xy)
  cxy <- sweep(xy, 2, ctr)
  e <- eigen(stats::cov(cxy), symmetric = TRUE)
  sdev <- sqrt(pmax(e$values, 0))
  if (sdev[2] <= 1e-6 || sdev[1] / sdev[2] < ratio_min) return(NULL)

  axe <- e$vectors[, 1]; perp_v <- e$vectors[, 2]
  along <- as.numeric(cxy %*% axe)
  across <- as.numeric(cxy %*% perp_v)
  br <- seq(min(along), max(along), by = pas_bin)
  if (length(br) < 2L) return(NULL)
  bin <- findInterval(along, br, rightmost.closed = TRUE)

  pts <- do.call(rbind, lapply(sort(unique(bin)), function(b) {
    idx <- bin == b
    ctr + mean(along[idx]) * axe + stats::median(across[idx]) * perp_v
  }))
  if (nrow(pts) < 2L) return(NULL)
  sf::st_linestring(pts)
}
