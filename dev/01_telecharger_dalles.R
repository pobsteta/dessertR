# Recuperation d'un secteur de test --------------------------------------
#
# Les dalles Lidar HD se telechargent depuis la Geoplateforme :
#   https://cartes.gouv.fr/telechargement/IGNF_MNT-LIDAR-HD
#   https://cartes.gouv.fr/telechargement/IGNF_MNH-LIDAR-HD
# et le nuage de points depuis la fiche "Nuages de points LiDAR HD"
# sur data.gouv.fr.
#
# Avancement de la couverture :
#   https://macarte.ign.fr/carte/mThSup/diffusionMNxLiDARHD
#
# Choisir un secteur de test qui coche les cases suivantes :
#   - un massif forestier avec desserte connue du gestionnaire (verite terrain)
#   - au moins un franchissement de cours d'eau (test des tabliers de pont)
#   - de preference un secteur riche en traces fossiles : chemins creux,
#     limites parcellaires anciennes, cloisonnements abandonnes. C'est le
#     risque numero un du projet, autant l'affronter tout de suite.
#
# Emprise et volume : compter environ 200 Mo par dalle COPC.LAZ.
# Un massif de 5000 ha represente une cinquantaine de dalles, soit ~10 Go.

dir.create("dev/data/laz", recursive = TRUE, showWarnings = FALSE)
dir.create("dev/data/mnt", recursive = TRUE, showWarnings = FALSE)
dir.create("dev/data/mnh", recursive = TRUE, showWarnings = FALSE)

# Une fois les dalles en place :
# devtools::load_all()
# cat <- dsr_catalog(laz = "dev/data/laz", mnt = "dev/data/mnt", mnh = "dev/data/mnh")
# print(cat)
# plot(sf::st_geometry(cat))
