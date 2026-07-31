# Le canal de surface se calibre-t-il, lui aussi ? --- banc sur deux massifs
# ------------------------------------------------------------------------------
# dsr_calibrer_specs() a montre que les regles GEOMORPHOLOGIQUES par defaut
# reposaient sur une intuition fausse : la rugosite marque les routes par le
# HAUT, pas par le bas. Signe corrige, sigma_geo passe de 0,52 a 0,79 sur wsfi.
#
# Le banc dev/04 vient de poser la question suivante, et elle est genante :
#
#     sigma_geo         AUC 0,713
#     sigma_surf        AUC 0,594
#     indice_detection  AUC 0,689     <- SOUS sigma_geo seul
#
# Autrement dit, combiner le canal de surface a un sigma_geo calibre DEGRADE
# l'entree. Or le BRIEF (section 3.9) ponderE le canal de surface 2 contre 1 en
# faveur du nuage, au motif qu'une piste se lit d'abord dans la discontinuite du
# sous-etage. C'est la MEME forme d'erreur que la rugosite : une intuition
# physique jamais mesuree, figee en ponderation par defaut.
#
# CE QUE CE SCRIPT MESURE
#
#   1. canal par canal, l'AUC orientee des couches de dsr_layers_pc() sur DEUX
#      massifs -- donc avec le test de stabilite du SENS, celui qui avait
#      ecarte la pente du jeu geomorphologique ;
#   2. l'AUC de sigma_surf sous les regles par defaut contre les regles
#      calibrees, massif par massif ;
#   3. l'AUC de l'indice de detection sous chaque jeu, pour repondre a la seule
#      question qui compte : le canal de surface AJOUTE-t-il quelque chose ?
#
# CE QUI EST EXCLU DE LA CALIBRATION, ET POURQUOI
#
#   densite_sol       couche de CONFIANCE du MNT (BRIEF 3.3 : « pas de
#                     detection »). Elle est forte sur route parce que la
#                     canopee y est ouverte, pas parce qu'il y a une route :
#                     la calibrer ferait entrer la trouee dans les regles, soit
#                     exactement le faux positif « trouee sans route » que la
#                     table de divergence du BRIEF 3.4 cherche a ecarter.
#   masque_exclusion  binaires. Un masque n'est pas une intensite ; son AUC est
#   masque_pont       un artefact de prevalence.
#
#   h_couvert reste DANS la mesure : c'est une hauteur, donc une intensite, et
#   le BRIEF le donne comme contexte -- s'il discrimine, autant le savoir.
#
# Usage :  Rscript dev/06_calibrer_surface.R
#
#   DSR_WSFI / DSR_LTCP   caches des deux projets
#   DSR_OUT               repertoire de sortie
#   DSR_COTE              cote de la fenetre par massif (defaut 1000)

suppressMessages({library(terra); library(sf)})

if (file.exists("DESCRIPTION") && requireNamespace("pkgload", quietly = TRUE)) {
  suppressMessages(pkgload::load_all(".", quiet = TRUE))
} else {
  library(dessertR)
}

caches <- c(
  wsfi = Sys.getenv("DSR_WSFI",
    "/home/pascal/.local/share/nemeton/projects/20260717_101641_wsfi/cache"),
  ltcp = Sys.getenv("DSR_LTCP",
    "/home/pascal/.local/share/nemeton/projects/20260701_204501_ltcp/cache"))
out <- Sys.getenv("DSR_OUT", "dev/out/surface")
cote <- as.numeric(Sys.getenv("DSR_COTE", "1000"))
dir.create(out, recursive = TRUE, showWarnings = FALSE)

# Les couches a ecarter de la calibration. Voir l'en-tete : ce ne sont pas des
# canaux de detection, et les laisser entrer calibrerait autre chose que ce
# qu'on croit mesurer.
HORS_CALIBRATION <- c("theta", "densite_sol", "masque_exclusion", "masque_pont")


# --- Preparation d'un massif --------------------------------------------------
# Meme fenetre que dev/04 : centroide du reseau de reference, cote x cote. Le
# choix reste reproductible et comparable d'un script a l'autre.
preparer <- function(nom, cache) {
  f_mnt <- file.path(cache, "layers", "lidar_mnt_mosaic.tif")
  f_roads <- file.path(cache, "layers", "roads.gpkg")
  d_nuage <- file.path(cache, "layers", "lidar_nuage")
  stopifnot(file.exists(f_mnt), file.exists(f_roads), dir.exists(d_nuage))

  mnt_full <- terra::rast(f_mnt)
  roads_full <- sf::st_zm(sf::st_geometry(sf::st_read(f_roads, quiet = TRUE)),
    drop = TRUE)
  centre <- sf::st_coordinates(sf::st_centroid(sf::st_union(roads_full)))[1, 1:2]
  fen <- terra::intersect(
    terra::ext(centre[1] - cote / 2, centre[1] + cote / 2,
               centre[2] - cote / 2, centre[2] + cote / 2),
    terra::ext(mnt_full))
  mnt <- terra::crop(mnt_full, fen)

  emprise <- sf::st_as_sfc(sf::st_bbox(fen))
  sf::st_crs(emprise) <- sf::st_crs(roads_full)
  roads <- suppressWarnings(sf::st_cast(
    sf::st_intersection(roads_full, emprise), "LINESTRING"))
  roads <- roads[!sf::st_is_empty(roads)]
  km <- sum(as.numeric(sf::st_length(roads))) / 1000
  cat(sprintf("[%s] fenetre %.0f m, reference %d troncons / %.2f km\n",
    nom, terra::xmax(fen) - terra::xmin(fen), length(roads), km))
  if (km < 0.5) stop(sprintf("[%s] trop peu de reference dans la fenetre.", nom))

  # Ne lire que les dalles utiles : ltcp en porte 25, la fenetre en touche 1 a 4.
  cat_nuage <- suppressMessages(dsr_catalog(laz = d_nuage, entetes = FALSE))
  dalles <- suppressMessages(dsr_dalles_requises(cat_nuage, emprise))
  cat(sprintf("[%s] %d dalle(s) sur %d lue(s)\n", nom, nrow(dalles),
    nrow(cat_nuage)))

  # Les canaux nuage coutent 250 a 320 s par massif. Les mettre en cache rend
  # les essais de ponderation instantanes, ce qui est la difference entre
  # balayer un parametre et le supposer.
  f_pc <- file.path(out, sprintf("pc_%s.tif", nom))
  if (file.exists(f_pc) && !identical(Sys.getenv("DSR_REFAIRE"), "1")) {
    pc <- terra::rast(f_pc)
    cat(sprintf("[%s] canaux nuage : cache\n", nom))
  } else {
    grille <- dsr_grille_reference(mnt, res = 1)
    t0 <- Sys.time()
    pc <- dsr_layers_pc(as.character(dalles$laz), res = 1, grille = grille,
      emprise = emprise)
    terra::writeRaster(pc, f_pc, overwrite = TRUE)
    cat(sprintf("[%s] canaux nuage : %.0f s\n", nom,
      as.numeric(difftime(Sys.time(), t0, units = "secs"))))
  }

  list(nom = nom, mnt = mnt, roads = roads, emprise = emprise, pc = pc,
       dtm = dsr_layers_dtm(mnt, res = 1))
}

massifs <- lapply(names(caches), function(n) preparer(n, caches[[n]]))
names(massifs) <- names(caches)


# --- 1. Pouvoir discriminant canal par canal ---------------------------------
cat("\n== Canaux de surface, massif par massif ==\n")
for (m in massifs) {
  d <- dsr_calibrer_specs(m$pc, m$roads, exclure = HORS_CALIBRATION)$diagnostic
  cat(sprintf("\n[%s]\n", m$nom))
  print(d[, c("canal", "auc", "sens", "retenu", "poids")], row.names = FALSE,
    digits = 3)
  utils::write.csv(d, file.path(out, sprintf("canaux_surface_%s.csv", m$nom)),
    row.names = FALSE)
}

# Calibration CONJOINTE : un canal n'est retenu que si son sens concorde sur les
# deux massifs. C'est ce test qui avait ecarte la pente du jeu geomorphologique.
cat("\n== Calibration conjointe (sens stable exige sur les deux) ==\n")
cal <- dsr_calibrer_specs(lapply(massifs, `[[`, "pc"),
  lapply(massifs, `[[`, "roads"), exclure = HORS_CALIBRATION)
print(cal$diagnostic, row.names = FALSE, digits = 3)
utils::write.csv(cal$diagnostic, file.path(out, "canaux_surface_conjoint.csv"),
  row.names = FALSE)
specs_cal <- cal$specs


# --- 2 et 3. Ce que valent les deux jeux de regles ---------------------------
# Meme mesure que dev/04, pour que les chiffres soient comparables d'un script
# a l'autre : cellules a moins de 3 m d'une route contre cellules a plus de 20 m.
auc_route <- function(r, roads, pres = 3, absent = 20, n = 3000) {
  u <- sf::st_union(roads)
  vin <- terra::values(terra::mask(r, terra::vect(sf::st_buffer(u, pres))))
  vout <- terra::values(terra::mask(r, terra::vect(sf::st_buffer(u, absent)),
    inverse = TRUE))
  vin <- vin[is.finite(vin)]; vout <- vout[is.finite(vout)]
  if (!length(vin) || !length(vout)) return(NA_real_)
  a <- sample(vin, min(n, length(vin))); b <- sample(vout, min(n, length(vout)))
  mean(outer(a, b, ">")) + 0.5 * mean(outer(a, b, "=="))
}

# sigma_geo est calibre CROISE (regles de l'autre massif) : c'est le protocole
# de dev/04, et sans lui la comparaison se ferait sur un sigma_geo au hasard.
cat("\n== Effet sur sigma_surf et sur l'indice de detection ==\n")
lignes <- list()
for (i in seq_along(massifs)) {
  m <- massifs[[i]]
  autre <- massifs[[if (i == 1L) 2L else 1L]]

  geo_specs <- dsr_calibrer_specs(autre$dtm, autre$roads)$specs
  sigma_geo <- dsr_conductivite(m$dtm, specs = geo_specs)

  s_def <- dsr_sigma_surf(m$pc)
  s_cal <- if (length(specs_cal)) dsr_sigma_surf(m$pc, specs = specs_cal) else NULL

  a_geo <- auc_route(sigma_geo, m$roads)
  a_def <- auc_route(s_def, m$roads)
  a_cal <- if (is.null(s_cal)) NA_real_ else auc_route(s_cal, m$roads)
  i_def <- auc_route(dsr_indice_detection(sigma_geo, sigma_surf = s_def,
    reference = NULL), m$roads)
  i_cal <- if (is.null(s_cal)) NA_real_ else auc_route(
    dsr_indice_detection(sigma_geo, sigma_surf = s_cal, reference = NULL),
    m$roads)

  lignes[[i]] <- data.frame(massif = m$nom, sigma_geo = a_geo,
    surf_defaut = a_def, surf_calibre = a_cal,
    indice_defaut = i_def, indice_calibre = i_cal)
}
tab <- do.call(rbind, lignes)
cat("\n")
print(tab, row.names = FALSE, digits = 3)
utils::write.csv(tab, file.path(out, "effet_regles_surface.csv"),
  row.names = FALSE)

# La lecture qui decide du lot : le canal de surface ajoute-t-il, ou retranche-t-il ?
cat("\nLecture :\n")
for (i in seq_len(nrow(tab))) {
  d_def <- tab$indice_defaut[i] - tab$sigma_geo[i]
  d_cal <- tab$indice_calibre[i] - tab$sigma_geo[i]
  cat(sprintf("  %-5s  defaut %+0.3f | calibre %+0.3f  (vs sigma_geo seul)\n",
    tab$massif[i], d_def, d_cal))
}


# --- 4. Quel poids donner au canal de surface dans la detection ? -------------
# Le defaut de dsr_indice_detection() est poids = c(geo = 1, surf = 2, vessel = 1),
# soit le canal de surface a DOUBLE. Ce chiffre vient du BRIEF, pas d'une mesure.
# On le balaye : w = 0 retire le canal (l'indice vaut alors sigma_geo seul), et
# la moyenne geometrique ponderee traite un poids nul proprement.
POIDS <- c(0, 0.25, 0.5, 1, 2)
# auc_route() tire un echantillon aleatoire de cellules : deux appels sur le
# MEME raster ne rendent pas le meme chiffre. Un premier balayage donnait 0,743
# a w = 0,50 contre 0,726 a w = 1,00 sur wsfi -- un ecart du meme ordre que la
# derive observee entre deux executions du script (0,719 puis 0,713 pour le
# seul sigma_geo). Changer un defaut du paquet sur un ecart qu'on n'a pas
# distingue du bruit, c'est refaire l'erreur que ce banc corrige. On repete
# donc, et on rend l'ecart-type.
REPETITIONS <- 15L
set.seed(20260731)
cat("\n== Balayage du poids de surface dans l'indice de detection ==\n")
cat(sprintf("(%d repetitions ; +- = ecart-type du tirage)\n", REPETITIONS))
balayage <- list()
for (i in seq_along(massifs)) {
  m <- massifs[[i]]
  autre <- massifs[[if (i == 1L) 2L else 1L]]
  sigma_geo <- dsr_conductivite(m$dtm,
    specs = dsr_calibrer_specs(autre$dtm, autre$roads)$specs)
  s_def <- dsr_sigma_surf(m$pc)
  for (w in POIDS) {
    # L'indice ne depend pas du tirage : on le calcule UNE fois par poids et on
    # ne repete que la mesure, qui est la seule source d'aleatoire.
    idx <- dsr_indice_detection(sigma_geo, sigma_surf = s_def,
      poids = c(geo = 1, surf = w, vessel = 1), reference = NULL)
    a <- replicate(REPETITIONS, auc_route(idx, m$roads))
    balayage[[length(balayage) + 1L]] <- data.frame(
      massif = m$nom, poids_surf = w, auc = mean(a), sd = stats::sd(a))
  }
}
bal <- do.call(rbind, balayage)
for (nm in unique(bal$massif)) {
  d <- bal[bal$massif == nm, ]
  cat(sprintf("\n[%s]\n", nm))
  for (j in seq_len(nrow(d))) {
    cat(sprintf("  w = %4.2f   AUC %.3f +- %.3f%s\n", d$poids_surf[j],
      d$auc[j], d$sd[j], if (d$auc[j] == max(d$auc)) "   <-- max" else ""))
  }
  # Le seul verdict qui resiste au bruit : le defaut actuel est-il distinguable
  # du meilleur poids ? On compare l'ecart a la somme des ecarts-types.
  best <- d[which.max(d$auc), ]
  def <- d[d$poids_surf == 2, ]
  ecart <- best$auc - def$auc
  cat(sprintf("  defaut w=2 : ecart au max %+.3f, soit %.1f ecarts-types\n",
    -ecart, ecart / (best$sd + def$sd)))
}
utils::write.csv(bal, file.path(out, "balayage_poids_surface.csv"),
  row.names = FALSE)

moy <- stats::aggregate(auc ~ poids_surf, data = bal, FUN = mean)
cat("\nMoyenne des deux massifs :\n")
print(moy, row.names = FALSE, digits = 3)
cat(sprintf("Meilleur poids moyen : %.2f\n",
  moy$poids_surf[which.max(moy$auc)]))

cat(sprintf("\nEcrit dans %s\n", normalizePath(out)))
