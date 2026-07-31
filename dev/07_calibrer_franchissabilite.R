# Ou placer le plancher de franchissabilite de l'agent ? --- balayage fin
# ------------------------------------------------------------------------------
# dsr_conduire(franchissabilite=) a ete introduit avec un defaut de 0,4, regle
# sur trois valeurs seulement (0,40 / 0,50 / 0,55) et optimal sur un seul des
# deux massifs. NEWS le consigne comme dette. Ce script la solde.
#
# CE QU'ON NE FAIT PAS, ET POURQUOI
#
#   On ne cherche PAS une verite d'etat (« cette route est-elle abandonnee ? »)
#   pour caler le seuil dessus. Elle n'existe pas dans les donnees disponibles :
#   la BD TOPO ne porte que la position, et OSM -- verifie par comptage sur les
#   deux fenetres -- ne porte AUCUN tag de cycle de vie (abandoned:/disused:/
#   razed:highway : zero sur les deux) et quasiment aucun attribut de
#   praticabilite (surface 0 et 1 voie, tracktype 0 et 5).
#
#   On n'en a pas besoin. Le parametre se regle contre la metrique qui compte
#   reellement -- ce que l'agent retrouve de la reference -- et cette metrique,
#   elle, est mesurable.
#
# LA QUESTION SUBSIDIAIRE : VALEUR ABSOLUE OU QUANTILE ?
#
#   0,4 tombe juste au-dessus du mode de sigma_surf (0,368 sur les DEUX
#   massifs). Un massif dont la distribution se deplace un peu ferait basculer
#   le defaut. Exprimer le seuil en quantile le rendrait robuste par
#   construction -- SI la position optimale est stable en quantile. C'est a
#   verifier et non a supposer : avec une masse ponctuelle a 0,368, la
#   correspondance quantile -> valeur est PLATE autour de la mediane, et la
#   parametrisation par quantile pourrait tres bien y etre degeneree. Le script
#   rend donc, pour chaque seuil, le quantile correspondant dans chaque massif.
#
# Usage :  Rscript dev/07_calibrer_franchissabilite.R
#
#   DSR_WSFI / DSR_LTCP   caches des deux projets
#   DSR_OUT               repertoire de sortie (defaut dev/out/franchissabilite)
#   DSR_PC                cache des canaux nuage (defaut dev/out/surface)
#
# SECOND PASSAGE (1.1.0.9000)
#
#   Le premier passage a conclu au maintien de 0,4. Deux lots l'ont invalide
#   depuis, et il faut le rejouer plutot que de s'y fier :
#
#     - dsr_calibrer_specs() rend desormais des bornes ABSOLUES, donc sigma_geo
#       n'est plus le meme et le seuil derive de sa distribution non plus ;
#     - dsr_conduire() ne tue plus les amorces posees sur le reseau deja
#       decouvert. Le premier passage mesurait un agent qui perdait 19 amorces
#       sur 26 sur ltcp -- et l'ordre de traitement decidait du resultat, ce qui
#       rendait ce massif instable d'un passage a l'autre.
#
#   Autrement dit, le premier passage a compare des seuils sur un agent
#   defaillant. Ses conclusions sur ltcp sont a jeter ; celles sur le mecanisme
#   (le mode de sigma_surf vient du calcul) restent valides, elles ne dependent
#   pas de l'agent.

suppressMessages({library(terra); library(sf)})

if (file.exists("DESCRIPTION") && requireNamespace("pkgload", quietly = TRUE)) {
  suppressMessages(pkgload::load_all(".", quiet = TRUE))
} else {
  library(dessertR)
}
set.seed(20260731)

caches <- c(
  wsfi = Sys.getenv("DSR_WSFI",
    "/home/pascal/.local/share/nemeton/projects/20260717_101641_wsfi/cache"),
  ltcp = Sys.getenv("DSR_LTCP",
    "/home/pascal/.local/share/nemeton/projects/20260701_204501_ltcp/cache"))
out <- Sys.getenv("DSR_OUT", "dev/out/franchissabilite")
d_pc <- Sys.getenv("DSR_PC", "dev/out/surface")
cote <- 1000; tol <- 5
dir.create(out, recursive = TRUE, showWarnings = FALSE)

# Grille resserree autour du mode (0,368) : c'est la que le comportement bascule.
# 0,55 ajoute au second passage : c'est vers la que l'optimum de ltcp semblait
# se deplacer une fois les bornes absolues en place.
SEUILS <- c(0.30, 0.35, 0.365, 0.375, 0.40, 0.45, 0.50, 0.55, 0.60)


# --- Preparation ---------------------------------------------------------------
preparer <- function(nom, cache, cache_autre) {
  mnt_full <- terra::rast(file.path(cache, "layers", "lidar_mnt_mosaic.tif"))
  roads_full <- sf::st_zm(sf::st_geometry(sf::st_read(
    file.path(cache, "layers", "roads.gpkg"), quiet = TRUE)), drop = TRUE)
  ctr <- unname(sf::st_coordinates(sf::st_centroid(sf::st_union(roads_full)))[1, 1:2])
  fen <- terra::intersect(terra::ext(ctr[1] - cote/2, ctr[1] + cote/2,
    ctr[2] - cote/2, ctr[2] + cote/2), terra::ext(mnt_full))
  mnt <- terra::crop(mnt_full, fen)
  emprise <- sf::st_as_sfc(sf::st_bbox(fen)); sf::st_crs(emprise) <- sf::st_crs(roads_full)
  roads <- suppressWarnings(sf::st_cast(sf::st_intersection(roads_full, emprise),
    "LINESTRING"))
  roads <- roads[!sf::st_is_empty(roads)]

  # sigma_geo calibre sur l'AUTRE massif : hors echantillon, comme dev/04.
  cm <- terra::rast(file.path(cache_autre, "layers", "lidar_mnt_mosaic.tif"))
  cr <- sf::st_zm(sf::st_geometry(sf::st_read(
    file.path(cache_autre, "layers", "roads.gpkg"), quiet = TRUE)), drop = TRUE)
  cc <- unname(sf::st_coordinates(sf::st_centroid(sf::st_union(cr)))[1, 1:2])
  cf <- terra::intersect(terra::ext(cc[1] - cote/2, cc[1] + cote/2,
    cc[2] - cote/2, cc[2] + cote/2), terra::ext(cm))
  cemp <- sf::st_as_sfc(sf::st_bbox(cf)); sf::st_crs(cemp) <- sf::st_crs(cr)
  crd <- suppressWarnings(sf::st_cast(sf::st_intersection(cr, cemp), "LINESTRING"))
  specs <- dsr_calibrer_specs(dsr_layers_dtm(terra::crop(cm, cf), res = 1), crd)$specs
  sigma <- dsr_conductivite(dsr_layers_dtm(mnt, res = 1), specs = specs)

  f_pc <- file.path(d_pc, sprintf("pc_%s.tif", nom))
  if (!file.exists(f_pc)) {
    stop(sprintf("Canaux nuage absents (%s). Lancer dev/06_calibrer_surface.R d'abord.", f_pc))
  }
  ss <- dsr_sigma_surf(terra::rast(f_pc))
  ss <- terra::resample(ss, sigma, method = "bilinear")

  list(nom = nom, roads = roads, sigma = sigma, sigma_surf = ss)
}


# --- Metriques (identiques a dev/04) -------------------------------------------
points_le_long <- function(g, pas = 2) {
  g <- g[!sf::st_is_empty(g)]; if (!length(g)) return(NULL)
  lg <- as.numeric(sf::st_length(g)); ok <- which(is.finite(lg) & lg > pas)
  if (!length(ok)) return(NULL)
  sf::st_cast(do.call(c, lapply(ok, function(i)
    sf::st_line_sample(g[i], sample = seq(0, 1, length.out = max(2L, ceiling(lg[i]/pas)))))),
    "POINT")
}
part <- function(depuis, vers, tol) {
  p <- points_le_long(depuis); if (is.null(p) || !length(vers)) return(NULL)
  d <- as.numeric(sf::st_distance(p, sf::st_union(vers)))
  list(part = mean(d <= tol), med = stats::median(d))
}


# --- Balayage ------------------------------------------------------------------
noms <- names(caches)
lignes <- list()
for (i in seq_along(noms)) {
  m <- preparer(noms[i], caches[[i]], caches[[if (i == 1L) 2L else 1L]])
  vs <- terra::values(m$sigma_surf, mat = FALSE); vs <- vs[is.finite(vs)]
  cat(sprintf("\n[%s] %d troncons de reference, sigma_surf mediane %.3f\n",
    m$nom, length(m$roads), stats::median(vs)))

  p_det <- dsr_indice_detection(m$sigma, sigma_surf = m$sigma_surf,
    reference = NULL)  # poids par defaut : surf = 0,5
  pts <- sf::st_cast(do.call(c, lapply(seq_along(m$roads), function(j) {
    lg <- as.numeric(sf::st_length(m$roads[j]))
    sf::st_line_sample(m$roads[j], sample = seq(0, 1, length.out = max(2L, ceiling(lg/5))))
  })), "POINT")
  v_ref <- terra::extract(p_det, sf::st_coordinates(pts))[, 1]; v_ref <- v_ref[is.finite(v_ref)]
  v_all <- terra::values(p_det); v_all <- v_all[is.finite(v_all)]
  seuil <- as.numeric(round(max(stats::median(v_ref), stats::quantile(v_all, 0.75)), 2))

  amorces <- dsr_amorces(p_det, reference = m$roads, seuil = seuil, bordure = FALSE)

  conduire <- function(fr, fr_min) {
    ll <- list(); deja <- NULL
    if (!is.null(amorces)) for (k in seq_along(amorces)) {
      r <- tryCatch(dsr_conduire(p_det, amorces[k], reseau = deja, portee = 60,
        conductivite_min = seuil, franchissabilite = fr,
        franchissabilite_min = fr_min), error = function(e) NULL)
      if (!is.null(r) && r$n_troncons > 0L) {
        ll[[length(ll) + 1L]] <- r$route[[1]]
        deja <- if (is.null(deja)) r$route else c(deja, r$route)
      }
    }
    if (length(ll)) sf::st_sfc(ll, crs = sf::st_crs(m$roads)) else sf::st_sfc()
  }

  mesurer <- function(etiquette, s, g) {
    rp <- part(m$roads, g, tol); pp <- part(g, m$roads, tol)
    ra <- if (is.null(rp)) NA_real_ else rp$part
    pr <- if (is.null(pp)) NA_real_ else pp$part
    data.frame(massif = m$nom, seuil = etiquette,
      quantile = if (is.na(s)) NA_real_ else mean(vs < s),
      n = length(g), km = sum(as.numeric(sf::st_length(g)))/1000,
      rappel = ra, precision = pr,
      ecart_med = if (is.null(pp)) NA_real_ else pp$med,
      f1 = if (is.na(ra) || is.na(pr) || ra + pr == 0) NA_real_ else 2*ra*pr/(ra+pr))
  }

  lignes[[length(lignes) + 1L]] <- mesurer("aucune", NA_real_, conduire(NULL, 0.4))
  cat("  .")
  for (s in SEUILS) {
    lignes[[length(lignes) + 1L]] <- mesurer(format(s), s,
      conduire(m$sigma_surf, s))
    cat(".")
  }
  cat("\n")
}

tab <- do.call(rbind, lignes)
cat("\n")
for (nm in unique(tab$massif)) {
  d <- tab[tab$massif == nm, ]
  cat(sprintf("[%s]\n", nm))
  print(d[, c("seuil", "quantile", "n", "km", "rappel", "precision",
    "ecart_med", "f1")], row.names = FALSE, digits = 3)
  best <- d[which.max(d$f1), ]
  cat(sprintf("  -> meilleur F1 a seuil %s (quantile %.2f)\n\n",
    best$seuil, best$quantile))
}
utils::write.csv(tab, file.path(out, "balayage_franchissabilite.csv"),
  row.names = FALSE)

# Le verdict qui decide de la parametrisation : l'optimum est-il au meme
# endroit en VALEUR, ou au meme endroit en QUANTILE ?
cat("Stabilite de l'optimum :\n")
for (nm in unique(tab$massif)) {
  d <- tab[tab$massif == nm & tab$seuil != "aucune", ]
  b <- d[which.max(d$f1), ]
  cat(sprintf("  %-5s  valeur %-6s  quantile %.2f  F1 %.3f\n",
    nm, b$seuil, b$quantile, b$f1))
}
cat(sprintf("\nEcrit dans %s\n", normalizePath(out)))
