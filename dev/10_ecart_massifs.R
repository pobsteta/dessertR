# D'ou vient l'ecart entre wsfi et ltcp ?
# ------------------------------------------------------------------------------
# Constat de depart : sur les memes reglages, ltcp rendait systematiquement des
# resultats bien inferieurs a wsfi (F1 0,30 contre 0,48 ; rappel 0,21 contre
# 0,39). L'hypothese naturelle etait un massif plus difficile -- plaine, faible
# relief, empreinte geomorphologique tenue.
#
# CE QUE LA MESURE A MONTRE
#
#   L'ecart venait pour les deux tiers du PROTOCOLE DE MESURE, pas du terrain.
#
#   Le harnais calibre sur un massif DISJOINT pour eviter la circularite -- ce
#   qui est juste -- mais depuis que dsr_calibrer_specs() rend des bornes
#   absolues, il transportait aussi les BORNES. Or une borne est dans l'unite du
#   canal : celles d'une plaine appliquees a une montagne poussent tout au
#   plafond, et inversement. Le contraste route / hors-route s'effondre a +0,010
#   et +0,018 selon le sens, contre +0,176 et +0,112 avec des bornes propres.
#
#   L'AUC ne voit rien : elle est invariante d'echelle, donc elle survit a
#   l'effondrement du contraste (0,631 et 0,645, soit quelques centiemes de
#   moins). L'agent, lui, travaille sur les VALEURS -- le cout admissible vaut
#   portee / conductivite_min -- et divague des que l'echelle se deplace.
#
#   C'est le piege central de ce script : la metrique qui sert d'ordinaire a
#   juger une carte etait aveugle au defaut qui cassait tout en aval.
#
# CE QUI RESTE APRES CORRECTION
#
#   Un ecart residuel, beaucoup plus petit, et coherent avec le relief : la
#   pente mediane vaut 2,3 deg sur ltcp contre 23,3 deg sur wsfi.
#
# Usage :  Rscript dev/10_ecart_massifs.R    (reutilise le cache de dev/06)

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
d_pc <- Sys.getenv("DSR_PC", "dev/out/surface")
out <- Sys.getenv("DSR_OUT", "dev/out/ecart")
cote <- 1000; tol <- 5
dir.create(out, recursive = TRUE, showWarnings = FALSE)

preparer <- function(nom, cache) {
  mnt <- terra::rast(file.path(cache, "layers", "lidar_mnt_mosaic.tif"))
  rd <- sf::st_zm(sf::st_geometry(sf::st_read(
    file.path(cache, "layers", "roads.gpkg"), quiet = TRUE)), drop = TRUE)
  ctr <- unname(sf::st_coordinates(sf::st_centroid(sf::st_union(rd)))[1, 1:2])
  e <- terra::intersect(terra::ext(ctr[1] - cote/2, ctr[1] + cote/2,
    ctr[2] - cote/2, ctr[2] + cote/2), terra::ext(mnt))
  emp <- sf::st_as_sfc(sf::st_bbox(e)); sf::st_crs(emp) <- sf::st_crs(rd)
  roads <- suppressWarnings(sf::st_cast(sf::st_intersection(rd, emp), "LINESTRING"))
  list(nom = nom, couches = dsr_layers_dtm(terra::crop(mnt, e), res = 1),
       roads = roads[!sf::st_is_empty(roads)],
       pc = terra::rast(file.path(d_pc, sprintf("pc_%s.tif", nom))))
}

auc <- function(r, roads, pres = 3, absent = 20, n = 3000, rep = 9) {
  u <- sf::st_union(roads)
  vi <- terra::values(terra::mask(r, terra::vect(sf::st_buffer(u, pres))))
  vo <- terra::values(terra::mask(r, terra::vect(sf::st_buffer(u, absent)),
    inverse = TRUE))
  vi <- vi[is.finite(vi)]; vo <- vo[is.finite(vo)]
  mean(replicate(rep, {
    a <- sample(vi, min(n, length(vi))); b <- sample(vo, min(n, length(vo)))
    mean(outer(a, b, ">")) + 0.5 * mean(outer(a, b, "=="))
  }))
}

m <- lapply(names(caches), function(n) preparer(n, caches[[n]]))
names(m) <- names(caches)


# --- 1. Le relief, qui fonde l'hypothese naturelle ----------------------------
cat("== Relief ==\n")
for (x in m) {
  p <- terra::values(x$couches[["pente"]], mat = FALSE)
  cat(sprintf("  %-5s pente mediane %5.1f deg | P90 %5.1f deg | reference %.2f km\n",
    x$nom, stats::median(p, na.rm = TRUE), stats::quantile(p, .9, na.rm = TRUE),
    sum(as.numeric(sf::st_length(x$roads))) / 1000))
}


# --- 2. Ce que les bornes croisees font a l'echelle ---------------------------
# La demonstration centrale : meme canal, meme massif, seules les bornes
# changent. On rend le CONTRASTE (mediane sous route moins mediane globale) en
# plus de l'AUC, parce que c'est lui que l'agent consomme et que l'AUC ignore.
cat("\n== Contraste et AUC de sigma_geo selon l'origine des bornes ==\n")
lignes <- list()
for (i in seq_along(m)) {
  x <- m[[i]]; y <- m[[if (i == 1L) 2L else 1L]]
  jeux <- list(
    `bornes croisees`  = dsr_calibrer_specs(y$couches, y$roads, bornes = TRUE)$specs,
    `bornes propres`   = dsr_calibrer_specs(x$couches, x$roads, bornes = TRUE)$specs,
    `sans bornes, croise` = dsr_calibrer_specs(y$couches, y$roads, bornes = FALSE)$specs)
  for (nm in names(jeux)) {
    sg <- suppressMessages(dsr_conductivite(x$couches, specs = jeux[[nm]]))
    v <- terra::values(sg, mat = FALSE); v <- v[is.finite(v)]
    vr <- terra::values(terra::mask(sg,
      terra::vect(sf::st_buffer(sf::st_union(x$roads), 3))))
    vr <- vr[is.finite(vr)]
    lignes[[length(lignes) + 1L]] <- data.frame(massif = x$nom, bornes = nm,
      mediane = stats::median(v), sous_route = stats::median(vr),
      contraste = stats::median(vr) - stats::median(v), auc = auc(sg, x$roads))
  }
}
tab <- do.call(rbind, lignes)
print(tab, row.names = FALSE, digits = 3)
utils::write.csv(tab, file.path(out, "bornes_echelle.csv"), row.names = FALSE)

cat("\nLecture : l'AUC bouge de quelques centiemes la ou le CONTRASTE est divise\n")
cat("par six a dix. L'AUC est un critere de RANG, invariant d'echelle ; l'agent\n")
cat("consomme des VALEURS. Juger une carte a l'AUC seule masque ce defaut.\n")
cat(sprintf("\nEcrit dans %s\n", normalizePath(out)))
