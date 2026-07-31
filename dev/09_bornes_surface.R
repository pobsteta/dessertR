# Des bornes absolues rendent-elles de l'information a sigma_surf ?
# ------------------------------------------------------------------------------
# Piste laissee ouverte par dev/07 : avec les bornes par defaut (NULL, donc
# quantilees a la mediane et au q95), la MOITIE des cellules ont
# mu(taux_penetration) = 0 et mu(densite_sousetage) = 1. Le canal est donc
# largement une fonction en marches, et son AUC mediocre (0,578 et 0,607)
# pourrait n'etre qu'un artefact de saturation plutot qu'une limite physique.
#
# dsr_calibrer_specs(bornes = TRUE) permet desormais de le tester : les bornes
# sortent des populations presence/absence mesurees, et non des quantiles de la
# fenetre.
#
# TROIS JEUX DE REGLES COMPARES
#
#   defaut          dsr_specs_surface() : type + poids, bornes quantilees.
#   calibre nu      types et poids mesures, bornes toujours quantilees.
#                   C'est ce que dev/06 avait teste, et qui DEGRADAIT.
#   calibre + bornes  types, poids ET bornes mesures. Nouveau.
#
# DEUX PROTOCOLES, ET ILS NE DISENT PAS LA MEME CHOSE
#
#   croise   calibre sur l'AUTRE massif. Honnete (hors echantillon) mais expose
#            au probleme de transport : une borne est dans l'unite du canal, et
#            taux_penetration brut vaut 0,04 sur wsfi contre 0,31 sur ltcp.
#   propre   calibre sur le massif lui-meme. CIRCULAIRE pour l'AUC -- les regles
#            ont vu les reponses -- mais donne le plafond atteignable et isole
#            la question « la saturation coute-t-elle de l'information ? » de la
#            question « les bornes se transportent-elles ? ».
#
# Usage :  Rscript dev/09_bornes_surface.R    (reutilise le cache de dev/06)

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
out <- Sys.getenv("DSR_OUT", "dev/out/bornes_surface")
cote <- 1000
dir.create(out, recursive = TRUE, showWarnings = FALSE)

HORS_CALIBRATION <- c("theta", "densite_sol", "masque_exclusion", "masque_pont")

preparer <- function(nom, cache) {
  f_pc <- file.path(d_pc, sprintf("pc_%s.tif", nom))
  if (!file.exists(f_pc)) {
    stop(sprintf("Canaux nuage absents (%s). Lancer dev/06_calibrer_surface.R.", f_pc))
  }
  pc <- terra::rast(f_pc)
  roads_full <- sf::st_zm(sf::st_geometry(sf::st_read(
    file.path(cache, "layers", "roads.gpkg"), quiet = TRUE)), drop = TRUE)
  emprise <- sf::st_as_sfc(sf::st_bbox(terra::ext(pc)))
  sf::st_crs(emprise) <- sf::st_crs(roads_full)
  roads <- suppressWarnings(sf::st_cast(
    sf::st_intersection(roads_full, emprise), "LINESTRING"))
  list(nom = nom, pc = pc, roads = roads[!sf::st_is_empty(roads)])
}

auc_route <- function(r, roads, pres = 3, absent = 20, n = 3000, rep = 9) {
  u <- sf::st_union(roads)
  vin <- terra::values(terra::mask(r, terra::vect(sf::st_buffer(u, pres))))
  vout <- terra::values(terra::mask(r, terra::vect(sf::st_buffer(u, absent)),
    inverse = TRUE))
  vin <- vin[is.finite(vin)]; vout <- vout[is.finite(vout)]
  if (!length(vin) || !length(vout)) return(NA_real_)
  mean(replicate(rep, {
    a <- sample(vin, min(n, length(vin))); b <- sample(vout, min(n, length(vout)))
    mean(outer(a, b, ">")) + 0.5 * mean(outer(a, b, "=="))
  }))
}

# Part de la masse concentree sur le mode : c'est la grandeur que les bornes
# absolues sont censees faire tomber.
saturation <- function(r) {
  v <- terra::values(r, mat = FALSE); v <- v[is.finite(v)]
  if (!length(v)) return(NA_real_)
  d <- stats::density(v, n = 512)
  mode <- d$x[which.max(d$y)]
  100 * mean(abs(v - mode) < 0.005)
}

massifs <- lapply(names(caches), function(n) preparer(n, caches[[n]]))
names(massifs) <- names(caches)

lignes <- list()
for (i in seq_along(massifs)) {
  m <- massifs[[i]]
  autre <- massifs[[if (i == 1L) 2L else 1L]]

  jeux <- list(
    defaut = dsr_specs_surface(),
    calibre_nu_croise = dsr_calibrer_specs(autre$pc, autre$roads,
      exclure = HORS_CALIBRATION, bornes = FALSE)$specs,
    calibre_bornes_croise = dsr_calibrer_specs(autre$pc, autre$roads,
      exclure = HORS_CALIBRATION, bornes = TRUE)$specs,
    calibre_bornes_propre = dsr_calibrer_specs(m$pc, m$roads,
      exclure = HORS_CALIBRATION, bornes = TRUE)$specs)

  for (nm in names(jeux)) {
    sp <- jeux[[nm]]
    if (!length(sp)) next
    ss <- dsr_sigma_surf(m$pc, specs = sp)
    lignes[[length(lignes) + 1L]] <- data.frame(
      massif = m$nom, regles = nm,
      auc_surf = auc_route(ss, m$roads),
      saturation_pct = saturation(ss),
      n_canaux = length(sp))
    cat(".")
  }
}
cat("\n\n")
tab <- do.call(rbind, lignes)
print(tab, row.names = FALSE, digits = 3)
utils::write.csv(tab, file.path(out, "bornes_surface.csv"), row.names = FALSE)

cat("\nLecture :\n")
for (nm in unique(tab$massif)) {
  d <- tab[tab$massif == nm, ]
  ref <- d$auc_surf[d$regles == "defaut"]
  for (j in which(d$regles != "defaut")) {
    cat(sprintf("  %-5s %-24s AUC %+0.3f | saturation %.1f -> %.1f %%\n",
      nm, d$regles[j], d$auc_surf[j] - ref,
      d$saturation_pct[d$regles == "defaut"], d$saturation_pct[j]))
  }
}
cat(sprintf("\nEcrit dans %s\n", normalizePath(out)))
