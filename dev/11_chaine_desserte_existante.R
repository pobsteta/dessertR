# La chaine complete, en partant d'une desserte EXISTANTE
# ------------------------------------------------------------------------------
# Le cas d'usage central du paquet : on ne part pas d'une page blanche, on part
# d'un reseau de reference (BD TOPO, couche interne, trace numerise) qu'il faut
# recaler, mesurer, qualifier -- puis completer de ce qu'il ignore.
#
# Contrairement a dev/03_validation.R, qui traite les massifs de nemeton et
# demande un cache local, ce script tourne SUR L'EXTRAIT LIVRE AVEC LE PAQUET
# (inst/extdata, 200 x 200 m, 4 troncons BD TOPO). Il est donc executable par
# quiconque a le paquet, sans donnee externe -- c'est un exemple de reference,
# pas une validation : 200 m de desserte ne valident rien.
#
# Les dix etapes, dans l'ordre ou elles dependent les unes des autres :
#
#    0. desserte existante + corridor de lecture
#    1. les deux canaux (geomorphologique, surface), jamais fusionnes
#    2. recalage contraint -- la reference fait autorite en planimetrie
#    3. etat par divergence des deux canaux
#    4. mesure de la geometrie
#    5. gabarit libre sous branches, depuis le nuage
#    6. praticabilite grumier + elargissements
#    7. ecart a la norme Certu (lecture, jamais calibration)
#    8. detection de ce que la reference ignore (elle sert de MASQUE)
#    9. reseau et connectivite au public
#   10. export GeoPackage
#
# Usage :  Rscript dev/11_chaine_desserte_existante.R
#
#   DSR_OUT   repertoire de sortie (defaut : tempdir())

suppressMessages({library(terra); library(sf)})

if (file.exists("DESCRIPTION") && requireNamespace("pkgload", quietly = TRUE)) {
  suppressMessages(pkgload::load_all(".", quiet = TRUE))
} else {
  library(dessertR)
}

ex <- function(f) system.file("extdata", f, package = "dessertR")
OUT <- Sys.getenv("DSR_OUT", tempdir())
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)


# --- 0. La desserte existante et son corridor ---------------------------------
# Le corridor ne change aucun resultat ici (la dalle fait 200 m) : il est la
# parce que sur un massif entier c'est lui qui rend le traitement possible --
# on ne lit du nuage que ce qui touche la desserte.
roads <- sf::st_zm(sf::st_read(ex("exemple_bdtopo.gpkg"), "troncon_de_route",
  quiet = TRUE))
mnt <- terra::rast(ex("exemple_mnt.tif"))
laz <- ex("exemple_nuage.laz")

corr <- dsr_corridor(roads, tampon = 40)

message(sprintf("0. %d troncons de reference, %.0f m | corridor %.1f ha",
  nrow(roads), sum(as.numeric(sf::st_length(roads))),
  as.numeric(sum(sf::st_area(corr))) / 1e4))


# --- 1. Les deux canaux, jamais fusionnes -------------------------------------
# sigma_geo dit qu'une route a marque le TERRAIN, sigma_surf dit que l'emprise
# est encore DEGAGEE. Les garder separes est ce qui permet, a l'etape 3, de
# distinguer une route en service d'une route recolonisee et d'une trouee.
grille <- dsr_grille_reference(mnt, res = 1)
pile <- dsr_layers_dtm(mnt, grille = grille)
sigma_geo <- dsr_conductivite(pile)

couches_pc <- dsr_layers_pc(laz, grille = grille, emprise = corr)
sigma_surf <- dsr_sigma_surf(couches_pc)

message(sprintf("1. %d canaux MNT | sigma_geo med %.2f, sigma_surf med %.2f",
  terra::nlyr(pile),
  stats::median(terra::values(sigma_geo), na.rm = TRUE),
  stats::median(terra::values(sigma_surf), na.rm = TRUE)))


# --- 2. Recalage contraint ----------------------------------------------------
# La deviation maximale n'est pas un reglage de confort : sans elle, le
# pathfinder accroche les lineaires paralleles (fosses, cloisonnements). Un
# troncon dont le recalage echoue GARDE sa geometrie d'origine -- RECALE = FALSE
# le dit, et aucun lineaire n'est perdu.
recale <- dsr_repositionner(roads, sigma_geo,
  theta = pile[["theta"]], poids = pile[["vesselness"]],
  deviation_max = 10, attraction = 1)

message(sprintf("2. recales %d/%d | deplacement moyen %.2f m, max %.2f m",
  sum(recale$RECALE), nrow(recale),
  mean(recale$DEPLACEMENT_MOY, na.rm = TRUE),
  max(recale$DEPLACEMENT_MAX, na.rm = TRUE)))


# --- 3. Etat : divergence des deux canaux -------------------------------------
long <- which(as.numeric(sf::st_length(recale)) >= 30)
if (length(long) == 0L) stop("Aucun troncon de 30 m ou plus a traiter.")

etats <- lapply(long, function(i)
  dsr_etat_trace(recale[i, ], sigma_geo, sigma_surf, pas = 2))
res_etat <- do.call(rbind, lapply(etats, `[[`, "resume"))
res_etat <- stats::aggregate(longueur ~ etat, data = res_etat, FUN = sum)
message("3. etat : ", paste(sprintf("%s %.0f m", res_etat$etat, res_etat$longueur),
  collapse = " | "))


# --- 4. Mesure de la geometrie ------------------------------------------------
# methode_largeur = "chaussee" vise la chaussee, accotement retranche. Quand la
# rupture chaussee/accotement n'est pas resolue, la mesure retombe sur la
# PLATEFORME et BORDS_CHAUSSEE le dit : c'est la colonne a lire avant la
# largeur, pas apres.
stations <- do.call(rbind, lapply(long, function(i) {
  m <- dsr_measure(recale[i, ], mnt, pas = 2, demi_largeur = 8,
    pas_travers = 0.25, liss_travers = 3,
    methode_largeur = "chaussee", tol_planeite = 0.10, base_courbure = 30)
  m$stations$troncon <- i
  m$stations
}))

message(sprintf(
  "4. %d stations | largeur med %.2f m | bords resolus %.0f %% | fosses 0/1/2 : %s",
  nrow(stations), stats::median(stations$LARGEUR_ROULABLE, na.rm = TRUE),
  100 * mean(stations$BORDS_CHAUSSEE > 0, na.rm = TRUE),
  paste(as.integer(table(factor(stations$FOSSES, levels = 0:2))), collapse = "/")))


# --- 5. Gabarit libre sous branches -------------------------------------------
# Mesure directe sur le nuage classe, absente de toutes les bases existantes.
# L'appariement se fait sur (troncon, chainage) : meme `pas` des deux cotes, on
# ne suppose pas que les deux tables sortent dans le meme ordre.
gab <- do.call(rbind, lapply(long, function(i) {
  g <- dsr_gabarit_libre(recale[i, ], laz, demi_largeur_route = 1.5, pas = 2)
  g$troncon <- i
  g
}))
stations$GABARIT_LIBRE <- gab$GABARIT_LIBRE[match(
  paste(stations$troncon, round(stations$chainage, 2)),
  paste(gab$troncon, round(gab$chainage, 2)))]


# --- 6. Praticabilite grumier -------------------------------------------------
# Les seuils sont INDICATIFS : dsr_seuils_grumier() est un point de depart a
# caler avec le gestionnaire, jamais une norme.
apte <- dsr_trafficability(stations, dsr_seuils_grumier())
message(sprintf("6. apte grumier : %.0f %% des stations | motifs : %s",
  100 * apte$resume$part_apte,
  paste(sprintf("%s=%d", names(apte$resume$par_motif), apte$resume$par_motif),
    collapse = " ")))

places <- dsr_places(stations, marge = 2, long_min = 6)
message(sprintf("   elargissements (places de depot / retournement) : %d",
  nrow(places)))


# --- 7. Ecart a la norme Certu ------------------------------------------------
# Sens de lecture : la fiche rend une CONSTANTE de 2 m sur toute la desserte
# forestiere. On ne cale rien dessus -- on lit l'ecart entre ce que la norme
# suppose et ce que le lidar mesure. Sur cet extrait le classement
# administratif est vide : la fiche ne peut pas apparier, et elle le DIT
# (combinaisons non appariees) au lieu de defauter en silence.
certu <- dsr_emprise_certu(roads)
ecart <- dsr_ecart_norme(stations, certu)
message("7. Certu (norme) vs mesure (lidar) :")
print(ecart, row.names = FALSE)


# --- 8. Ce que la reference ignore --------------------------------------------
# La desserte existante sert ici de MASQUE (buffer_ref) : on ne remonte que
# l'inconnu. Sur un massif entier, prendre regime = "corridor" avec
# emprise = corr pour ne balayer que les abords de la desserte connue.
det <- dsr_detecter(sigma_geo, reference = recale, sigma_surf = sigma_surf,
  regime = "complet", seuil = 0.6, buffer_ref = 15, long_min = 30)
message(sprintf("8. detecte hors reference : %d axe(s), %.0f m",
  nrow(det), if (nrow(det)) sum(as.numeric(sf::st_length(det))) else 0))


# --- 9. Reseau et connectivite au public --------------------------------------
# Une desserte detectee qui ne rejoint pas le reseau public est signalee comme
# artefact PROBABLE : c'est un tri a instruire, pas une suppression.
# La colonne `troncon` est portee des ici : dsr_reseau() conserve les attributs,
# et c'est par elle que dsr_classer() retrouvera les stations mesurees.
traces <- rbind(
  sf::st_sf(source = "reference", troncon = seq_len(nrow(recale)),
    geometry = sf::st_geometry(recale)),
  if (nrow(det)) sf::st_sf(source = "detecte", troncon = NA_integer_,
    geometry = sf::st_geometry(det))
)
reseau <- dsr_reseau(traces, tol_noeud = 1, largeur_dedupe = 3,
  reseau_public = roads, tol_public = 5)
message(sprintf(
  "9. reseau : %d aretes, %d noeuds, %d composants | %.0f m deconnectes du public",
  reseau$resume$n_aretes, reseau$resume$n_noeuds, reseau$resume$n_composants,
  reseau$resume$longueur_deconnectee))


# --- 9 bis. Classement et proposition de balisage OSM -------------------------
# Ce que la detection remonte hors reference, en foret geree, est plus souvent
# un cloisonnement ou un layon qu'une desserte : la classe le dit, et le
# balisage propose suit le consensus du fil OSM-fr (man_made=cutline, pas
# highway=*). Sans NDVI ni parcellaire ici, la plupart des criteres restent
# inconnus -- CLASSE_CONF le chiffre plutot que de le taire.
classe <- dsr_classer(reseau$aretes, stations = stations, reference = roads)
message("9 bis. classement :")
print(sf::st_drop_geometry(classe)[, c("source", "CLASSE", "CLASSE_CONF",
  "CLASSE_MOTIF", "OSM_TAGS")], row.names = FALSE)

# --- 10. Export ---------------------------------------------------------------
gpkg <- file.path(OUT, "desserte_chaine.gpkg")
dsr_export_gpkg(list(
  desserte = recale,
  stations = apte$stations,
  places = places,
  detecte = det,
  aretes = classe
), gpkg)

md <- file.path(OUT, "desserte_rapport.md")
dsr_rapport(
  praticabilite = apte,
  etat = etats[[1]],
  reseau = reseau,
  norme = ecart,
  fichier = md)
message(sprintf("10. ecrit : %s\n    %s", gpkg, md))
