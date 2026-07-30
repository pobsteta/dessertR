# Agent conducteur contre squelette --- banc de vectorisation sur donnee reelle
# ------------------------------------------------------------------------------
# Le harnais dev/03_validation.R valide la MESURE (largeur, fosses, devers,
# repositionnement). Il n'exerce ni dsr_vectoriser() ni dsr_conduire() : la
# qualite de la VECTORISATION n'y est jamais mise en cause. Ce script comble ce
# trou, et il est ne d'une question precise -- l'agent conducteur, ecrit pour
# remplacer le paquet vecnet, fait-il mieux que le squelette sur une vraie dalle
# Lidar HD, ou seulement sur les cartes synthetiques de sa suite de tests ?
#
# CE QUI FAIT REFERENCE ICI
#
#   La BD TOPO, et pour sa POSITION seulement. C'est l'arbitrage de
#   dev/03_validation.R et il vaut aussi ici : la precision planimetrique de la
#   BD TOPO est metrique, sa largeur declarative ne l'est pas. On ne mesure donc
#   que des ecarts de POSITION et des taux de RECOUVREMENT, jamais une largeur.
#
#   Consequence sur le protocole : on ne masque PAS le corridor de reference,
#   contrairement a dsr_indice_detection() en usage normal. Le but n'est pas de
#   detecter ce que la BD TOPO ignore -- il n'y aurait alors aucune verite pour
#   juger -- mais de RETROUVER ce qu'elle porte, ou la verite existe. C'est un
#   banc de vectorisation, pas un banc de detection.
#
# CE QUI EST MESURE
#
#   rappel     part de la longueur BD TOPO situee a moins de `tol` d'une ligne
#              produite. Repond a : « qu'est-ce que le vectoriseur a rate ? »
#   precision  part de la longueur produite situee a moins de `tol` de la
#              BD TOPO. Repond a : « qu'a-t-il invente ? »
#   ecart_med  distance mediane des points produits a la BD TOPO, en metres.
#   n_lignes   nombre de troncons. A longueur egale, moins il y en a, moins le
#              resultat est fragmente -- le defaut connu du squelette.
#   temps      secondes.
#
#   Un vectoriseur qui produit peu et juste a une precision haute et un rappel
#   bas ; l'inverse signale du hors-piste. Les deux se lisent ensemble.
#
# Usage :  Rscript dev/04_agent_vs_squelette.R
#
#   DSR_WSFI    cache du projet (defaut : le projet wsfi de nemeton)
#   DSR_OUT     repertoire de sortie
#   DSR_COTE    cote de la fenetre d'analyse en metres (defaut 1000)
#   DSR_TOL     tolerance d'appariement en metres (defaut 5)

suppressMessages({library(terra); library(sf)})

# Charger l'ARBRE DE TRAVAIL, pas le paquet installe. Sans cela, un harnais de
# validation valide silencieusement une version perimee -- c'est arrive ici :
# le premier passage a echoue sur `methode = "agent"`, absent du paquet 1.0.0
# installe alors que la fonction existait dans les sources depuis une heure.
if (file.exists("DESCRIPTION") && requireNamespace("pkgload", quietly = TRUE)) {
  suppressMessages(pkgload::load_all(".", quiet = TRUE))
} else {
  library(dessertR)
}

cache <- Sys.getenv("DSR_WSFI",
  "/home/pascal/.local/share/nemeton/projects/20260717_101641_wsfi/cache")
out <- Sys.getenv("DSR_OUT", "dev/out/agent")
cote <- as.numeric(Sys.getenv("DSR_COTE", "1000"))
tol <- as.numeric(Sys.getenv("DSR_TOL", "5"))
dir.create(out, recursive = TRUE, showWarnings = FALSE)

f_mnt <- file.path(cache, "layers", "lidar_mnt_mosaic.tif")
f_roads <- file.path(cache, "layers", "roads.gpkg")
stopifnot(file.exists(f_mnt), file.exists(f_roads))


# --- Fenetre d'analyse --------------------------------------------------------
# On ne traite pas les 4 km2 : les canaux multi-echelles sur 16 M cellules a 50 cm
# ne servent pas le propos. Une fenetre centree sur la zone la mieux desservie
# donne le meme diagnostic pour une fraction du cout -- et le choix est
# reproductible : on prend le centroide du reseau BD TOPO, pas un coin arbitraire.
mnt_full <- terra::rast(f_mnt)
roads_full <- sf::st_read(f_roads, quiet = TRUE)
roads_full <- sf::st_zm(sf::st_geometry(roads_full), drop = TRUE)

centre <- sf::st_coordinates(sf::st_centroid(sf::st_union(roads_full)))[1, 1:2]
fen <- terra::ext(centre[1] - cote / 2, centre[1] + cote / 2,
                  centre[2] - cote / 2, centre[2] + cote / 2)
fen <- terra::intersect(fen, terra::ext(mnt_full))
mnt <- terra::crop(mnt_full, fen)

cat(sprintf("Fenetre %.0f x %.0f m a %.0f / %.0f, MNT %s m\n",
  terra::xmax(fen) - terra::xmin(fen), terra::ymax(fen) - terra::ymin(fen),
  centre[1], centre[2], format(terra::res(mnt)[1])))

emprise <- sf::st_as_sfc(sf::st_bbox(fen))
sf::st_crs(emprise) <- sf::st_crs(roads_full)
roads <- sf::st_intersection(roads_full, emprise)
roads <- roads[!sf::st_is_empty(roads)]
roads <- suppressWarnings(sf::st_cast(roads, "LINESTRING"))
km_ref <- sum(as.numeric(sf::st_length(roads))) / 1000
cat(sprintf("Reference BD TOPO dans la fenetre : %d troncons, %.2f km\n",
  length(roads), km_ref))
if (km_ref < 0.5) stop("Trop peu de reference dans la fenetre pour juger quoi que ce soit.")


# --- Conductivite geomorphologique -------------------------------------------
cat("Canaux geomorphologiques + sigma_geo...\n")
t0 <- Sys.time()
couches <- dsr_layers_dtm(mnt, res = 1)
sigma <- dsr_conductivite(couches)
cat(sprintf("  %.0f s | sigma_geo : mediane %.2f, P90 %.2f\n",
  as.numeric(difftime(Sys.time(), t0, units = "secs")),
  stats::median(terra::values(sigma), na.rm = TRUE),
  stats::quantile(terra::values(sigma), 0.9, na.rm = TRUE)))


# --- Canal de surface, depuis le nuage ----------------------------------------
# Premier passage de ce banc : construit sur sigma_geo SEUL, il ne pouvait rien
# conclure. Mesure faite apres coup, cellules a moins de 3 m d'une route contre
# cellules a plus de 20 m : AUC 0,516. Autrement dit sigma_geo ne distingue pas
# une route d'une foret sur ce bloc -- le hasard donne 0,5.
#
# Ce n'est pas une surprise : le BRIEF (section 3.9) pondere le canal de SURFACE
# a 2 contre 1 pour le geomorphologique, parce qu'une piste se lit d'abord dans
# la discontinuite du sous-etage, pas dans le terrain. Le banc partait du canal
# que le projet designe lui-meme comme le plus faible.
nuage <- list.files(file.path(cache, "layers", "lidar_nuage"),
  pattern = "\\.(copc\\.laz|laz|las)$", full.names = TRUE)
grille <- dsr_grille_reference(mnt, res = 1)
sigma_surf <- NULL
if (length(nuage) && !identical(Sys.getenv("DSR_NUAGE"), "0")) {
  cat(sprintf("Canal de surface : %d dalles, restreint a la fenetre...\n", length(nuage)))
  t0 <- Sys.time()
  sigma_surf <- tryCatch({
    pc <- dsr_layers_pc(nuage, res = 1, grille = grille, emprise = emprise)
    dsr_sigma_surf(pc)
  }, error = function(e) {cat("  echec :", conditionMessage(e), "\n"); NULL})
  if (!is.null(sigma_surf)) {
    cat(sprintf("  %.0f s\n", as.numeric(difftime(Sys.time(), t0, units = "secs"))))
  }
}

# Indice de detection : c'est l'entree pour laquelle dsr_vectoriser() est reglee.
# `reference = NULL` : on ne masque PAS le corridor connu, sans quoi il ne
# resterait aucune verite pour juger (voir l'en-tete).
p_det <- if (is.null(sigma_surf)) {
  sigma
} else {
  dsr_indice_detection(sigma, sigma_surf = sigma_surf, reference = NULL)
}


# --- Pouvoir discriminant de l'entree : le garde-fou qui manquait -------------
# A LIRE AVANT TOUT TABLEAU. Comparer des vectoriseurs sur une carte qui ne
# porte pas l'information cherchee ne mesure pas les vectoriseurs, mais la
# carte. Ce diagnostic aurait economise le premier passage.
auc_route <- function(r, roads, pres = 3, abs = 20, n = 3000) {
  u <- sf::st_union(roads)
  vin <- terra::values(terra::mask(r, terra::vect(sf::st_buffer(u, pres))))
  vout <- terra::values(terra::mask(r, terra::vect(sf::st_buffer(u, abs)), inverse = TRUE))
  vin <- vin[is.finite(vin)]; vout <- vout[is.finite(vout)]
  if (!length(vin) || !length(vout)) return(NA_real_)
  a <- sample(vin, min(n, length(vin))); b <- sample(vout, min(n, length(vout)))
  mean(outer(a, b, ">")) + 0.5 * mean(outer(a, b, "=="))
}

cat("\nPouvoir discriminant route / hors route (AUC ; 0.5 = aucun)\n")
diag_auc <- data.frame(
  canal = c("sigma_geo", "sigma_surf", "indice_detection"),
  auc = c(auc_route(sigma, roads),
          if (is.null(sigma_surf)) NA_real_ else auc_route(sigma_surf, roads),
          auc_route(p_det, roads)))
print(diag_auc, row.names = FALSE, digits = 3)

auc_entree <- diag_auc$auc[3]
if (!is.finite(auc_entree) || auc_entree < 0.60) {
  cat("\n!! AUC de l'entree < 0.60 : le tableau ci-dessous compare des vectoriseurs\n")
  cat("   sur une carte qui ne porte pas l'information. Il decrit la carte.\n")
}


# --- Seuil calibre sur la reference, et non devine ----------------------------
# Les seuils par defaut (0.6) sont ceux d'une carte de probabilite bien
# contrastee. On mesure donc ce qu'est REELLEMENT la valeur sous une route ici,
# en echantillonnant l'entree le long de la BD TOPO -- usage legitime de la
# reference, sa POSITION, pour savoir ou regarder.
#
# Le seuil est pris a la MEDIANE des routes connues et non au Q1 : au premier
# passage, le Q1 (0,10) tombait sous la mediane globale du raster (0,139), donc
# selectionnait plus de la moitie de l'image. Un seuil doit separer, pas inclure.
pts_ref <- sf::st_cast(do.call(c, lapply(seq_along(roads), function(i) {
  lg <- as.numeric(sf::st_length(roads[i]))
  sf::st_line_sample(roads[i], sample = seq(0, 1, length.out = max(2L, ceiling(lg / 5))))
})), "POINT")
v_ref <- terra::extract(p_det, sf::st_coordinates(pts_ref))[, 1]
v_ref <- v_ref[is.finite(v_ref)]
v_all <- terra::values(p_det); v_all <- v_all[is.finite(v_all)]
seuil <- as.numeric(round(max(stats::median(v_ref), stats::quantile(v_all, 0.75)), 2))
cat(sprintf("\nEntree sous la BD TOPO : mediane %.2f | entree globale : mediane %.2f, P75 %.2f\n",
  stats::median(v_ref), stats::median(v_all), stats::quantile(v_all, 0.75)))
cat(sprintf("Seuil retenu : %.2f\n", seuil))


# --- Metriques ----------------------------------------------------------------
# Rappel et precision sont ponderes par la LONGUEUR et non comptes par troncon :
# un vectoriseur qui hache un axe en vingt bouts ne doit pas peser vingt fois.
# L'echantillonnage regulier a `pas` metres realise cette ponderation.
points_le_long <- function(g, pas = 2) {
  g <- g[!sf::st_is_empty(g)]
  if (!length(g)) return(NULL)
  lg <- as.numeric(sf::st_length(g))
  ok <- which(is.finite(lg) & lg > pas)
  if (!length(ok)) return(NULL)
  pts <- lapply(ok, function(i) {
    sf::st_line_sample(g[i], sample = seq(0, 1, length.out = max(2L, ceiling(lg[i] / pas))))
  })
  sf::st_cast(do.call(c, pts), "POINT")
}

part_a_portee <- function(depuis, vers, tol) {
  p <- points_le_long(depuis)
  if (is.null(p) || !length(vers)) return(NA_real_)
  d <- as.numeric(sf::st_distance(p, sf::st_union(vers)))
  list(part = mean(d <= tol), ecart_med = stats::median(d))
}

evaluer <- function(nom, lignes, secondes) {
  g <- if (inherits(lignes, "sf")) sf::st_geometry(lignes) else lignes
  if (!length(g)) {
    return(data.frame(vectoriseur = nom, n_lignes = 0L, km = 0, rappel = NA,
      precision = NA, ecart_med = NA, temps_s = secondes))
  }
  r <- part_a_portee(roads, g, tol)      # ce que la BD TOPO voit de nous
  p <- part_a_portee(g, roads, tol)      # ce que nous voyons de la BD TOPO
  data.frame(vectoriseur = nom, n_lignes = length(g),
    km = sum(as.numeric(sf::st_length(g))) / 1000,
    rappel = r$part, precision = p$part, ecart_med = p$ecart_med,
    temps_s = secondes)
}


# --- Les deux vectoriseurs ----------------------------------------------------
# Meme carte, meme longueur minimale, meme simplification : seul le vectoriseur
# change. Le squelette recoit son seuil de binarisation habituel ; l'agent recoit
# la reference comme AMORCE (ses extremites), ce qui est son mode nominal --
# c'est precisement ce que vecnet ne sait pas faire.
resultats <- list()

cat("Squelette...\n")
t0 <- Sys.time()
sq <- dsr_vectoriser(p_det, methode = "squelette", seuil = seuil, long_min = 50,
  simplifier = 1)
resultats[[1]] <- evaluer("squelette", sq,
  as.numeric(difftime(Sys.time(), t0, units = "secs")))

cat("Agent (amorces de bordure)...\n")
t0 <- Sys.time()
ag <- dsr_vectoriser(p_det, methode = "agent", seuil = seuil, long_min = 50,
  simplifier = 1, portee = 60, conductivite_min = seuil)
resultats[[2]] <- evaluer("agent/bordure", ag,
  as.numeric(difftime(Sys.time(), t0, units = "secs")))

cat("Agent (amorce par la reference)...\n")
# Attention : `reference` rend le reseau INFRANCHISSABLE pour l'agent, qui s'y
# arrete. Amorcer par la BD TOPO tout en lui demandant de la retrouver serait
# contradictoire. On amorce donc a la main, sans passer la reference comme
# reseau : on demande a l'agent de repartir des bouts connus et de continuer.
t0 <- Sys.time()
amorces <- dsr_amorces(p_det, reference = roads, seuil = seuil, bordure = FALSE)
lignes <- list()
# Le reseau DECOUVERT est accumule et rendu infranchissable pour les agents
# suivants. Sans cela -- premier passage de ce banc -- les ~70 amorces
# reparcourent les memes axes : 52,8 km produits pour 8,85 km de reference, et
# une precision qui compte plusieurs fois les memes metres. La reference, elle,
# reste franchissable : c'est ce qu'on demande de retrouver.
deja <- NULL
if (!is.null(amorces)) {
  for (i in seq_along(amorces)) {
    a <- tryCatch(dsr_conduire(p_det, amorces[i], reseau = deja, portee = 60,
      conductivite_min = seuil), error = function(e) NULL)
    if (!is.null(a) && a$n_troncons > 0L) {
      lignes[[length(lignes) + 1L]] <- a$route[[1]]
      deja <- if (is.null(deja)) a$route else c(deja, a$route)
    }
  }
}
ag2 <- if (length(lignes)) sf::st_sfc(lignes, crs = sf::st_crs(roads)) else sf::st_sfc()
resultats[[3]] <- evaluer("agent/reference", ag2,
  as.numeric(difftime(Sys.time(), t0, units = "secs")))


# --- Sortie -------------------------------------------------------------------
tab <- do.call(rbind, resultats)
cat("\n")
print(within(tab, {
  rappel <- round(rappel, 3); precision <- round(precision, 3)
  km <- round(km, 2); ecart_med <- round(ecart_med, 2); temps_s <- round(temps_s, 1)
}), row.names = FALSE)

gpkg <- file.path(out, "agent_vs_squelette.gpkg")
if (file.exists(gpkg)) unlink(gpkg)
sf::st_write(sf::st_sf(geometry = sf::st_geometry(roads)), gpkg, "bdtopo", quiet = TRUE)
if (nrow(sq) > 0) sf::st_write(sq, gpkg, "squelette", quiet = TRUE, append = TRUE)
if (nrow(ag) > 0) sf::st_write(ag, gpkg, "agent_bordure", quiet = TRUE, append = TRUE)
if (length(ag2) > 0) {
  sf::st_write(sf::st_sf(geometry = ag2), gpkg, "agent_reference", quiet = TRUE, append = TRUE)
}
terra::writeRaster(p_det, file.path(out, "entree.tif"), overwrite = TRUE)
utils::write.csv(diag_auc, file.path(out, "auc_canaux.csv"), row.names = FALSE)
utils::write.csv(tab, file.path(out, "agent_vs_squelette.csv"), row.names = FALSE)
cat(sprintf("\nEcrit dans %s\n", normalizePath(out)))
