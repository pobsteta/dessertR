# Benchmark du regime corridor -------------------------------------------
#
# LIVRABLE DU LOT 0. Rien d'autre ne doit etre ecrit avant que ce chiffre
# soit connu.
#
# Question : quelle fraction des points d'une dalle forestiere se trouve dans
# un tampon de 40 m autour du reseau BD TOPO, et quel gain en temps de lecture
# cela represente-t-il ?
#
# Hypothese a valider : 5 a 10 % des points, gain de lecture d'un facteur 5 a
# 15. Si le gain observe est inferieur a 5, le passage a l'echelle d'un massif
# est compromis et il faut revoir la strategie avant d'aller plus loin
# (indexation COPC exploitee plus finement, pre-decoupage des dalles, ou
# renoncement au traitement wall-to-wall).

devtools::load_all()
library(sf)

catalogue <- dsr_catalog(laz = "dev/data/laz",
                         mnt = "dev/data/mnt",
                         mnh = "dev/data/mnh")

reseau <- sf::st_read("dev/data/bdtopo/troncon_de_route.gpkg")
reseau <- sf::st_transform(reseau, sf::st_crs(catalogue))

corridor  <- dsr_corridor(reseau, tampon = 40)
concernes <- dsr_dalles_requises(catalogue, corridor)

# --- Fraction surfacique (borne superieure grossiere, gratuite) -----------
aire_dalles   <- sum(sf::st_area(concernes))
aire_corridor <- sf::st_area(sf::st_intersection(corridor, sf::st_union(concernes)))
cat(sprintf("Fraction surfacique du corridor : %.1f %%\n",
            100 * as.numeric(aire_corridor / aire_dalles)))

# --- Fraction reelle en points et temps de lecture ------------------------
# A COMPLETER une fois dsr_lire_corridor() ecrite.
#
# Pour chaque dalle, mesurer :
#   t_complet <- system.time(<lecture dalle entiere>)
#   t_corr    <- system.time(<lecture restreinte au corridor>)
#   n_complet, n_corr
#
# Consigner les resultats dans dev/resultats_bench.csv et les reporter dans
# le README. C'est le premier chiffre honnete du projet.
