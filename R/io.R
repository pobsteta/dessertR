# Entrees / sorties : export GeoPackage, styles QGIS, rapport (BRIEF section 3).
# C'est ce qui rend les sorties consommables par un gestionnaire, pas un tas
# d'objets R. Le GPKG regroupe toutes les couches vectorielles d'un massif ; les
# styles QML donnent une lecture immediate de l'etat et de l'aptitude dans QGIS.

#' Exporter les couches d'un massif en GeoPackage
#'
#' Ecrit un jeu de couches vectorielles `sf` dans un unique GeoPackage, une
#' couche par element nomme (BRIEF section 3). Ecrit optionnellement les styles
#' QGIS accompagnant les couches reconnues (`etat`, `aptitude`).
#'
#' @param couches Liste **nommee** d'objets `sf` (p. ex. `list(trace = ...,
#'   stations = ..., etat = ..., reseau = ...)`).
#' @param fichier Chemin du GeoPackage de sortie.
#' @param styles Ecrire les fichiers `.qml` pour les couches stylables. Defaut
#'   `TRUE`.
#' @param overwrite Ecraser un GeoPackage existant. Defaut `TRUE`.
#'
#' @return Le chemin du GeoPackage, invisiblement.
#' @seealso [dsr_qml_categorise()], [dsr_rapport()].
#' @examples
#' \donttest{
#' tr <- sf::st_sf(id = 1, geometry = sf::st_sfc(
#'   sf::st_linestring(cbind(c(0, 10), c(0, 0))), crs = 2154))
#' f <- tempfile(fileext = ".gpkg")
#' dsr_export_gpkg(list(trace = tr), f)
#' sf::st_layers(f)$name
#' }
#' @export
dsr_export_gpkg <- function(couches, fichier, styles = TRUE, overwrite = TRUE) {
  if (!is.list(couches) || length(couches) == 0L ||
        is.null(names(couches)) || any(!nzchar(names(couches)))) {
    dsr_abort("{.arg couches} doit etre une liste nommee non vide d'objets {.cls sf}.")
  }
  non_sf <- names(couches)[!vapply(couches, inherits, logical(1), "sf")]
  if (length(non_sf)) {
    dsr_abort(c(
      "Couches non vectorielles : {.val {non_sf}}.",
      "i" = "Seuls les objets {.cls sf} sont exportes ; pour un raster, utiliser {.fun terra::writeRaster}."
    ))
  }
  if (file.exists(fichier) && overwrite) unlink(fichier)

  for (nm in names(couches)) {
    sf::st_write(couches[[nm]], fichier, layer = nm, append = TRUE, quiet = TRUE)
  }

  if (isTRUE(styles)) {
    if ("etat" %in% names(couches)) {
      dsr_qml_categorise(
        sub("\\.gpkg$", "_etat.qml", fichier), champ = "etat",
        valeurs = DSR_ETAT_NIVEAUX$etat,
        couleurs = c("34,139,34", "220,20,20", "255,165,0", "150,150,150"),
        geometrie = "line"
      )
    }
    if ("aptitude" %in% names(couches) || "APTE_GRUMIER" %in%
          unlist(lapply(couches, names))) {
      lyr <- if ("aptitude" %in% names(couches)) "aptitude" else
        names(couches)[vapply(couches, function(x) "APTE_GRUMIER" %in% names(x), logical(1))][1]
      dsr_qml_categorise(
        sub("\\.gpkg$", "_aptitude.qml", fichier), champ = "APTE_GRUMIER",
        valeurs = c("true", "false"), couleurs = c("34,139,34", "220,20,20"),
        labels = c("apte", "inapte"), geometrie = "point"
      )
    }
  }
  invisible(fichier)
}


#' Ecrire un style QGIS categorise (.qml)
#'
#' Genere un fichier de style QGIS `.qml` a rendu categorise sur un champ, avec
#' une couleur par valeur (BRIEF section 3 : styles QGIS). Compatible QGIS 3.x
#' (format `prop`). Un fichier `.qml` place a cote d'une couche est charge
#' automatiquement par QGIS.
#'
#' @param fichier Chemin du `.qml` a ecrire.
#' @param champ Nom du champ portant les categories.
#' @param valeurs Valeurs des categories.
#' @param couleurs Couleurs `"r,g,b"` (une par valeur).
#' @param labels Libelles affiches ; defaut = `valeurs`.
#' @param geometrie `"line"` (defaut), `"point"` ou `"fill"`.
#' @return Le chemin du `.qml`, invisiblement.
#' @seealso [dsr_export_gpkg()].
#' @export
dsr_qml_categorise <- function(fichier, champ, valeurs, couleurs, labels = NULL,
                               geometrie = c("line", "point", "fill")) {
  geometrie <- match.arg(geometrie)
  if (length(couleurs) != length(valeurs)) {
    dsr_abort("{.arg couleurs} doit avoir autant d'elements que {.arg valeurs}.")
  }
  if (is.null(labels)) labels <- valeurs
  classe <- c(line = "SimpleLine", point = "SimpleMarker", fill = "SimpleFill")[geometrie]

  cats <- paste0(sprintf(
    '      <category value="%s" label="%s" symbol="%d" render="true"/>',
    valeurs, labels, seq_along(valeurs) - 1L), collapse = "\n")

  prop_couleur <- if (geometrie == "line") "line_color" else "color"
  syms <- paste0(vapply(seq_along(valeurs), function(i) {
    sprintf(paste0(
      '    <symbol type="%s" name="%d">\n',
      '      <layer class="%s">\n',
      '        <prop k="%s" v="%s,255"/>\n',
      '        <prop k="line_width" v="0.6"/>\n',
      '        <prop k="size" v="2"/>\n',
      '      </layer>\n    </symbol>'),
      geometrie, i - 1L, classe, prop_couleur, couleurs[i])
  }, character(1)), collapse = "\n")

  qml <- paste0(
    '<!DOCTYPE qgis>\n',
    '<qgis version="3.34" styleCategories="Symbology">\n',
    sprintf('  <renderer-v2 type="categorizedSymbol" attr="%s">\n', champ),
    '    <categories>\n', cats, '\n    </categories>\n',
    '    <symbols>\n', syms, '\n    </symbols>\n',
    '  </renderer-v2>\n</qgis>\n'
  )
  writeLines(qml, fichier)
  invisible(fichier)
}


#' Rapport de synthese d'un traitement
#'
#' Assemble en un texte Markdown les metriques cles d'un traitement de desserte
#' (BRIEF section 3 : rapport) : geometrie mesuree, praticabilite, etat, reseau.
#' Chaque entree est optionnelle.
#'
#' @param mesure Sortie de [dsr_measure()] (`$resume`), ou son `resume`.
#' @param praticabilite Sortie de [dsr_trafficability()] (`$resume`).
#' @param etat Sortie de [dsr_etat_trace()] (`$resume`, `data.frame`).
#' @param reseau Sortie de [dsr_reseau()] (`$resume`).
#' @param norme Sortie de [dsr_ecart_norme()] : l'ecart entre la largeur mesuree
#'   et la largeur normative de la fiche Certu. La section se lit dans **un
#'   seul sens** -- la mesure informe sur ce que la norme suppose, jamais
#'   l'inverse (voir [dsr_emprise_certu()]).
#' @param fichier Chemin d'un `.md` a ecrire ; `NULL` pour seulement renvoyer le
#'   texte.
#' @return Le texte Markdown (caractere), invisiblement si `fichier` est fourni.
#' @seealso [dsr_export_gpkg()], [dsr_ecart_norme()].
#' @export
dsr_rapport <- function(mesure = NULL, praticabilite = NULL, etat = NULL,
                        reseau = NULL, norme = NULL, fichier = NULL) {
  get_resume <- function(x) if (is.list(x) && !is.null(x$resume)) x$resume else x
  m <- get_resume(mesure); p <- get_resume(praticabilite)
  e <- get_resume(etat); r <- get_resume(reseau)

  l <- c("# Rapport de desserte", "")
  if (!is.null(m)) {
    l <- c(l, "## Geometrie",
      sprintf("- Largeur roulable mediane : %.1f m", m$LARGEUR_ROULABLE_MED),
      sprintf("- Pente longitudinale : moyenne %.1f %%, maximale %.1f %%",
        100 * m$PENTE_LONG_MOY, 100 * m$PENTE_LONG_MAX),
      sprintf("- Rayon de courbure minimal : %.0f m", m$RAYON_COURBURE_MIN),
      sprintf("- Sinuosite : %.2f", m$SINUOSITE), "")
  }
  if (!is.null(p)) {
    motifs <- paste(names(p$par_motif), p$par_motif, sep = " = ", collapse = ", ")
    l <- c(l, "## Praticabilite grumier",
      sprintf("- Part apte : %.0f %% des stations", 100 * p$part_apte),
      sprintf("- Stations bloquees par critere : %s", motifs), "")
  }
  if (!is.null(e)) {
    lignes <- sprintf("- %s : %.0f m (%.0f %%)", e$etat, e$longueur, e$pourcentage)
    l <- c(l, "## Etat le long du trace", lignes, "")
  }
  if (!is.null(r)) {
    l <- c(l, "## Reseau",
      sprintf("- %d aretes, %d noeuds, %d composante(s)", r$n_aretes, r$n_noeuds, r$n_composants),
      if (!is.na(r$longueur_deconnectee))
        sprintf("- Longueur non rattachee au reseau public : %.0f m", r$longueur_deconnectee),
      "")
  }
  if (!is.null(norme)) {
    if (!"ECART_NORME" %in% names(norme)) {
      dsr_abort(c(
        "{.arg norme} ne porte pas la colonne {.field ECART_NORME}.",
        "i" = "Attendu : la sortie de {.fun dsr_ecart_norme}."
      ))
    }
    ok <- !is.na(norme$ECART_NORME)
    lignes <- if (!any(ok)) {
      # Cas courant sur donnee forestiere : la fiche n'apparie rien (classement
      # administratif vide). On le dit plutot que de rendre une section muette.
      "- Aucun troncon apparie a la fiche : pas d'ecart calculable."
    } else {
      e <- norme$ECART_NORME[ok]
      c(sprintf("- Troncons apparies a la fiche : %d sur %d", sum(ok), nrow(norme)),
        sprintf("- Ecart median a la norme : %+.1f m (mesure - norme)",
          stats::median(e)),
        sprintf("- Au-dessus de la norme : %d troncon(s) ; en dessous : %d",
          sum(e > 0), sum(e < 0)),
        if ("BORDS_RESOLUS" %in% names(norme) &&
            any(!is.na(norme$BORDS_RESOLUS[ok]))) {
          # Sans bord de chaussee resolu, la mesure est une PLATEFORME : l'ecart
          # est alors un majorant, et le taire le ferait lire comme un ecart de
          # chaussee a chaussee.
          sprintf(paste0("- Bords de chaussee resolus : %.0f %% des stations",
            " -- en deca, l'ecart compare une plateforme a une largeur de",
            " chaussee et se lit comme un majorant"),
            100 * mean(norme$BORDS_RESOLUS[ok], na.rm = TRUE))
        })
    }
    l <- c(l, "## Ecart a la norme Certu", lignes, "")
  }
  txt <- paste(l, collapse = "\n")
  if (!is.null(fichier)) {
    writeLines(txt, fichier)
    return(invisible(txt))
  }
  txt
}
