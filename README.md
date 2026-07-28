# dessertR

<!-- badges: start -->
[![R-CMD-check](https://github.com/pobsteta/dessertR/actions/workflows/r.yml/badge.svg)](https://github.com/pobsteta/dessertR/actions/workflows/r.yml)
[![Version](https://img.shields.io/github/v/release/pobsteta/dessertR?sort=semver&logo=github&label=version&color=blue)](https://github.com/pobsteta/dessertR/releases/latest)
[![pkgdown](https://github.com/pobsteta/dessertR/actions/workflows/pkgdown.yaml/badge.svg)](https://pobsteta.github.io/dessertR/)
[![codecov](https://codecov.io/gh/pobsteta/dessertR/graph/badge.svg)](https://codecov.io/gh/pobsteta/dessertR)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg?logo=gnu)](https://www.gnu.org/licenses/gpl-3.0)
[![Lifecycle: experimental](https://img.shields.io/badge/lifecycle-experimental-orange.svg)](https://lifecycle.r-lib.org/articles/stages.html#experimental)
<!-- badges: end -->

Correction, mesure et qualification de la desserte forestiere a partir des
donnees du programme **Lidar HD** de l'IGN et d'une carte de reference
vectorielle telle que la **BD TOPO**.

> **Etat : chaine complete, calibrage en cours.** Le traitement va de la dalle
> Lidar brute au GeoPackage de sortie. Les seuils metier ne sont pas encore
> cales sur un jeu de validation suffisant : les sorties sont inspectables et
> defendables, elles ne sont pas encore opposables. Voir
> [Ce qui reste a faire](#ce-qui-reste-a-faire).

## Ce que le paquet fait

A partir d'un nuage de points Lidar HD classe, du MNT, du MNH et d'un reseau de
reference imparfait :

- **mesurer** ce que la BD TOPO ne dit pas : largeur roulable, fosses, devers,
  pente longitudinale, rayon de courbure, gabarit libre sous branches ;
- **qualifier la praticabilite**, en particulier l'aptitude au grumier, avec le
  motif d'inaptitude et sa localisation ;
- **diagnostiquer l'etat** en separant le signal geomorphologique (l'empreinte
  de la route dans le terrain, memoire longue) du signal de surface (l'emprise
  est-elle encore degagee) ; c'est la divergence entre les deux qui revele les
  troncons abandonnes ou recolonises ;
- **detecter** la desserte absente de la reference : pistes, cloisonnements,
  places de depot ;
- **recaler** les troncons sans jamais s'ecarter de la reference au-dela d'une
  tolerance choisie, la BD TOPO faisant autorite en planimetrie.

## La chaine

```r
library(dessertR)

# 1. Catalogage des dalles et grille de reference commune
dalles <- dsr_catalog(laz = "…/lidar_nuage", mnt = "…/lidar_mnt", mnh = "…/lidar_mnh")
mnt    <- terra::rast("…/lidar_mnt_mosaic.tif")
grille <- dsr_grille_reference(mnt, res = 1)

# 2. Deux canaux SEPARES, jamais fusionnes en un score unique
pile       <- dsr_layers_dtm(mnt, grille = grille)   # pente, rugosite, SLRM, vesselness, openness
sigma_geo  <- dsr_conductivite(pile)                 # l'empreinte dans le terrain
couches_pc <- dsr_layers_pc(dalles$laz[1], grille = grille)
sigma_surf <- dsr_sigma_surf(couches_pc)             # l'emprise est-elle encore degagee

# 3. Etat = divergence des deux canaux
etat <- dsr_etat(sigma_geo, sigma_surf)              # en service / abandonnee / trouee / hors route

# 4. Recalage contraint : la reference fait autorite
roads   <- sf::st_read("…/roads.gpkg")
recale  <- dsr_repositionner(roads, sigma_geo, theta = pile[["theta"]],
                             deviation_max = 10)

# 5. Mesure et praticabilite
m       <- dsr_measure(recale[1, ], mnt, pas = 2, base_courbure = 30)
apte    <- dsr_trafficability(m$stations, dsr_seuils_grumier())

# 6. Detection de ce que la reference ignore
detecte <- dsr_detecter(sigma_geo, reference = roads, sigma_surf = sigma_surf)
reseau  <- dsr_reseau(detecte, reseau_public = roads)

# 7. Export
dsr_export_gpkg(list(desserte = recale, stations = m$stations), "sortie.gpkg")
```

## Trois partis pris

**Ne pas fusionner les signaux en un score unique.** `sigma_geo` dit qu'une
route a marque le terrain, `sigma_surf` dit que l'emprise est encore degagee.
Leur croisement distingue une route en service d'une route recolonisee et d'une
trouee sans route — ce qu'un score composite ne peut pas faire. Le pathfinder
tourne sur `sigma_geo`, robuste a la vegetation.

**La reference fait autorite en planimetrie.** En France la BD TOPO est deja
precise ; le repositionnement libre accroche des lineaires paralleles (fosses,
lignes, cloisonnements). `dsr_repositionner()` recale sous contrainte de
deviation et conserve integralement le reseau : aucun troncon n'est perdu.

**Le nuage tranche les traces fossiles.** Le sol forestier francais est sature
de linearites anciennes que le canal geomorphologique allume toutes. Sur une
scene de controle portant une piste reelle et une trace fossile de meme
signature geomorphologique, la detection sans `sigma_surf` remonte les deux ;
avec `sigma_surf`, seule la piste reelle sort.

## Ce qui est mesure, et avec quelle fiabilite

Les chiffres ci-dessous viennent de profils et de traces de **synthese, de
geometrie connue** : ils bornent l'erreur de l'estimateur, ils ne remplacent pas
une validation terrain.

| Grandeur | Etat |
|---|---|
| Largeur roulable | biais −0,1 a −0,3 m sur profil de synthese, stable jusqu'a 10 cm de bruit du MNT |
| Devers | restitue a ±0,005 ; distingue du bombement de drainage, qui est symetrique |
| Rayon de courbure | ajuste par cercle des moindres carres sur 30 m ; le cercle circonscrit a trois stations sous-estime d'un ordre de grandeur sur un trace vectorise |
| Fosses (0/1/2) | detectes par creux lateral au-dela du bord de plateforme |
| Gabarit libre | mesure directement sur le nuage classe, absent des bases existantes |
| Etat de la desserte | valide sur dalle reelle : les routes actives ressortent `en_service` |

Deux reglages meritent attention avant tout usage metier :

- **`tol_planeite` doit depasser la fleche du bombement** (`bombement x largeur / 2`).
  Une route de 6 m bombee a 3 % passe avec le defaut de 0,10 m ; la meme bombee
  a 6 % est tronquee et demande 0,20 m.
- **`base_courbure` commande la courbure bien plus que le pas des stations.**
  Sur un arc de rayon vrai 60 m quantifie au metre puis lisse, la mediane des
  rayons vaut 16,6 m a trois stations, 49 m sur base 20 m, 60 m sur base 50 m.

[`dsr_calibrer_largeur()`](https://pobsteta.github.io/dessertR/reference/dsr_calibrer_largeur.html)
balaie une grille de parametres contre une largeur de reference et renvoie
biais, MAE et RMSE — pour arbitrer sur des chiffres. `dev/03_validation.R`
l'applique a tous les massifs disponibles et publie le tableau croise : un
reglage qui gagne sur un massif et perd sur les autres n'est pas un reglage.

## Ce qui reste a faire

1. **Calibrer la largeur sur le terrain.** L'estimateur est stabilise, le biais
   residuel est faible et constant — reste a savoir s'il traduit une erreur de
   mesure ou un **ecart de definition** : la largeur roulable retient la bande
   de faible devers, une largeur carrossable de gestionnaire inclut souvent les
   accotements. Cette question se tranche avec le gestionnaire, pas au seuil.
2. **Valider sur des massifs contrastes.** Feuillus de plaine, resineux de
   montagne, plateau calcaire — ce dernier est le test decisif du canal
   geomorphologique, la ou les chemins creux et les traces fossiles abondent.
3. **Publier les chiffres de validation ici meme** : RMSE lateral, MAE sur la
   largeur, matrice de confusion sur l'etat, precision/rappel sur les troncons
   hors BD TOPO et sur `APTE_GRUMIER`.
4. **Caler les seuils d'aptitude avec un gestionnaire.** `dsr_seuils_grumier()`
   est indicatif et ne doit jamais etre pris pour un referentiel.
5. **Vignette** « du telechargement des dalles au GPKG de sortie ».

## Installation

```r
# lasR n'est pas sur le CRAN
install.packages("lasR", repos = "https://r-lidar.r-universe.dev")

remotes::install_github("pobsteta/dessertR")
```

Le paquet embarque un noyau **Rust** (openness / sky-view factor et pathfinder
anisotrope) : l'installation depuis les sources demande `cargo` et
`rustc >= 1.65`. Les dependances cargo sont vendorisees, la compilation se fait
hors ligne.

Paquets optionnels : `igraph` (topologie du reseau), `sfnetworks` (export
graphe), `ranger` (conductivite apprise par foret aleatoire), `lasR` (canal
nuage), et [`vecnet`](https://github.com/r-lidar-lab/vecnet) — non publie sur le
CRAN — utilise automatiquement comme vectoriseur s'il est installe.

## Donnees

- **Lidar HD** (IGN, licence ouverte Etalab) : nuage classe en 11 categories,
  MNT et MNH au pas de 50 cm, dalles de 1 km x 1 km. Couverture metropolitaine
  complete annoncee pour fin 2026.
- **BD TOPO** (IGN, licence ouverte Etalab).

Un extrait reel de 200 x 200 m (nuage classe, MNT, MNH, extrait BD TOPO) est
versionne dans `inst/extdata/` sous licence ouverte Etalab, et sert aux tests
d'integration.

## Origine

La methode reprend et adapte celle d'ALSroads et de vecnet, developpes au
laboratoire de Jean-Romain Roussel a l'Universite Laval pour la desserte
forestiere quebecoise :

- Roussel, J.-R., Bourdon, J.-F., Morley, I. D., Coops, N. C., & Achim, A.
  (2022). Correction, update, and enhancement of vectorial forestry road maps
  using ALS data, a pathfinder, and seven metrics. *International Journal of
  Applied Earth Observation and Geoinformation*, 114, 103020.
  <https://doi.org/10.1016/j.jag.2022.103020>
- Roussel, J.-R., Bourdon, J.-F., Morley, I. D., Coops, N. C., & Achim, A.
  (2023). Vectorial and topologically valid segmentation of forestry road
  networks from ALS data. *International Journal of Applied Earth Observation
  and Geoinformation*, 118, 103267.
  <https://doi.org/10.1016/j.jag.2023.103267>

Le post-traitement des centre-lignes emprunte a deux travaux plus recents : le
lissage de Savitzky-Golay de Wang *et al.* (2025, arXiv:2502.07486) et la
representation par courbes de Bezier de DOGE (Sun *et al.*, 2025,
arXiv:2511.19850) — cette derniere ramenee a un ajustement direct, l'algorithme
publie supposant PyTorch et un GPU.

Le contexte francais deplace la valeur : la BD TOPO etant deja precise en
planimetrie, le repositionnement des troncons devient secondaire devant la
mesure, la qualification d'etat et la detection de la desserte non cartographiee.

## Licence

GPL (>= 3).
