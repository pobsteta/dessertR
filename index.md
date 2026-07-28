# dessertR

Correction, mesure et qualification de la desserte forestiere a partir
des donnees du programme **Lidar HD** de l’IGN et d’une carte de
reference vectorielle telle que la **BD TOPO**.

> **Etat : chaine complete, calibrage en cours.** Le traitement va de la
> dalle Lidar brute au GeoPackage de sortie. Les seuils metier ne sont
> pas encore cales sur un jeu de validation suffisant : les sorties sont
> inspectables et defendables, elles ne sont pas encore opposables. Voir
> [Ce qui reste a faire](#ce-qui-reste-a-faire).

## Ce que le paquet fait

A partir d’un nuage de points Lidar HD classe, du MNT, du MNH et d’un
reseau de reference imparfait :

- **mesurer** ce que la BD TOPO ne dit pas : largeur roulable, fosses,
  devers, pente longitudinale, rayon de courbure, gabarit libre sous
  branches ;
- **qualifier la praticabilite**, en particulier l’aptitude au grumier,
  avec le motif d’inaptitude et sa localisation, gabarit vertical **et**
  lateral ;
- **situer l’elagage** : ou les houppiers empietent sur l’emprise, et de
  combien ;
- **diagnostiquer l’etat** en separant le signal geomorphologique
  (l’empreinte de la route dans le terrain, memoire longue) du signal de
  surface (l’emprise est-elle encore degagee) ; c’est la divergence
  entre les deux qui revele les troncons abandonnes ou recolonises ;
- **detecter** la desserte absente de la reference : pistes,
  cloisonnements, places de depot ;
- **recaler** les troncons sans jamais s’ecarter de la reference au-dela
  d’une tolerance choisie, la BD TOPO faisant autorite en planimetrie.

## La chaine

``` r

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

# 5 bis. Canal optique (facultatif) : ou les houppiers debordent sur l'emprise.
#        Le CHM vient de l'ortho, pas du lidar : deux sources independantes.
chm     <- terra::rast("…/chm_predit.tif")
lat     <- dsr_gabarit_lateral(recale[1, ], chm, largeur = m$stations)
m$stations$SURPLOMB      <- lat$SURPLOMB
m$stations$HAUT_SURPLOMB <- lat$HAUT_SURPLOMB

apte    <- dsr_trafficability(m$stations, dsr_seuils_grumier())

# 6. Detection de ce que la reference ignore
detecte <- dsr_detecter(sigma_geo, reference = roads, sigma_surf = sigma_surf)
reseau  <- dsr_reseau(detecte, reseau_public = roads)

# 7. Export
dsr_export_gpkg(list(desserte = recale, stations = m$stations), "sortie.gpkg")
```

## Quatre partis pris

**Ne pas fusionner les signaux en un score unique.** `sigma_geo` dit
qu’une route a marque le terrain, `sigma_surf` dit que l’emprise est
encore degagee. Leur croisement distingue une route en service d’une
route recolonisee et d’une trouee sans route — ce qu’un score composite
ne peut pas faire. Le pathfinder tourne sur `sigma_geo`, robuste a la
vegetation.

**La reference fait autorite en planimetrie.** En France la BD TOPO est
deja precise ; le repositionnement libre accroche des lineaires
paralleles (fosses, lignes, cloisonnements).
[`dsr_repositionner()`](https://pobsteta.github.io/dessertR/reference/dsr_repositionner.md)
recale sous contrainte de deviation et conserve integralement le reseau
: aucun troncon n’est perdu.

**Le nuage tranche les traces fossiles.** Le sol forestier francais est
sature de linearites anciennes que le canal geomorphologique allume
toutes. Sur une scene de controle portant une piste reelle et une trace
fossile de meme signature geomorphologique, la detection sans
`sigma_surf` remonte les deux ; avec `sigma_surf`, seule la piste reelle
sort.

**Un second avis n’en est un que s’il est independant.** Tout ce qui
precede sort du meme nuage de points. Les canaux derives de l’ortho —
NDVI, et les modeles de hauteur de canopee predits depuis la BD ORTHO —
ne partagent aucune erreur avec le lidar, ce qui est exactement ce qui
manquait a une desserte issue d’un autre algorithme applique au *meme*
nuage. Independant ne veut pas dire interchangeable : ces canaux servent
a **discriminer** et a situer le surplomb, jamais a mesurer une largeur
de chaussee.

## Ce qui est mesure, et avec quelle fiabilite

Les chiffres ci-dessous viennent de profils et de traces de **synthese,
de geometrie connue** : ils bornent l’erreur de l’estimateur, ils ne
remplacent pas une validation terrain.

| Grandeur | Etat |
|----|----|
| Largeur de chaussee | exacte a ±0,35 m sur profil de synthese quand la rupture chaussee/accotement est resolue ; retombe sur la plateforme sinon, en le signalant |
| Devers | restitue a ±0,005 ; distingue du bombement de drainage, qui est symetrique |
| Rayon de courbure | ajuste par cercle des moindres carres sur 30 m ; le cercle circonscrit a trois stations sous-estime d’un ordre de grandeur sur un trace vectorise |
| Fosses (0/1/2) | **creux** lateral au-dela du bord de plateforme : descente puis remontee. Un versant qui descend sans remonter n’en est pas un |
| Gabarit libre (vertical) | mesure directement sur le nuage classe, absent des bases existantes |
| Surplomb (lateral) | empietement des houppiers sur l’emprise, depuis un modele de hauteur de canopee ; hauteur lue **permissive** (sommet du houppier, pas dessous de branche) |
| Largeur de la plage minerale (NDVI) | second avis independant du lidar, seuil determine par Otsu ; muet sur piste enherbee ou ombragee |
| Etat de la desserte | valide sur dalle reelle : les routes actives ressortent `en_service` |

Deux reglages meritent attention avant tout usage metier :

- **`tol_planeite` doit depasser la fleche du bombement**
  (`bombement x largeur / 2`). Une route de 6 m bombee a 3 % passe avec
  le defaut de 0,10 m ; la meme bombee a 6 % est tronquee et demande
  0,20 m.
- **`base_courbure` commande la courbure bien plus que le pas des
  stations.** Sur un arc de rayon vrai 60 m quantifie au metre puis
  lisse, la mediane des rayons vaut 16,6 m a trois stations, 49 m sur
  base 20 m, 60 m sur base 50 m.
- **La largeur mesure la CHAUSSEE, accotement retranche**
  (`methode_largeur = "chaussee"`, defaut). Le bord est l’intersection
  de la droite de chaussee et de la droite d’accotement, sans seuil de
  pente. Mais la rupture n’est pas toujours visible : un accotement a 4
  % ne se distingue pas d’un bombement a 3 %, et un bruit de MNT au-dela
  de 5 cm la noie. Dans ces cas la mesure **retombe sur la plateforme**
  et `BORDS_CHAUSSEE` le dit (0, 1 ou 2 cotes resolus). **Lire cette
  colonne avant la largeur** : sur l’extrait livre avec le paquet, MNT
  50 cm sous couvert, elle vaut 0 a 162 stations sur 222.
  `methode_largeur = "planeite"` rend la plateforme entiere.
- **Les deux bords ne se valent pas en montagne.** Sur l’extrait Lidar
  HD livre avec le paquet (route en deblai-remblai), l’ecart
  interquartile de la position du bord le long du troncon vaut 0,50 m
  cote amont, adosse a un talus de deblai construit, contre 1,00 a 1,25
  m cote aval sur remblai. La variation est **lisse** — le bord se
  deplace d’une seule maille d’echantillonnage entre stations voisines,
  autocorrelation 0,44 a 0,68 — donc c’est la geometrie de l’accotement
  qui varie, pas la mesure qui saute. `BORD_G` et `BORD_D` sont renvoyes
  separement pour que cette dissymetrie reste lisible.

### Ce qui fait reference, et pour quoi

| Usage | Reference |
|----|----|
| Position planimetrique | **BD TOPO**, sans reserve — c’est le socle du recalage |
| Existence d’un troncon | **BD TOPO** — base de la precision/rappel sur la detection |
| Largeur | **aucune source cartographique** ; il faut un releve |
| Trouee de canopee, NDVI | **second avis, jamais reference** — voir ci-dessous |

`LARGEUR_DE_CHAUSSEE` de la BD TOPO est un attribut **declaratif**,
souvent defaute par classe et vide sur `Chemin` et `Sentier` — soit
precisement notre cas d’usage. Elle sert de controle **ordinal** (la
largeur mesuree doit se ranger dans l’ordre des natures), jamais de
metre etalon.

Et la sortie d’un traitement anterieur — desserte corrigee par ALSroads
ou equivalent — est disqualifiee **par construction** :
[`dsr_calibrer_largeur()`](https://pobsteta.github.io/dessertR/reference/dsr_calibrer_largeur.html)
retient le reglage qui *minimise* l’ecart, donc s’y caler ne mesurerait
pas le biais de l’autre methode, ça le **reproduirait**.

Une trouee de canopee tombe sous le meme interdit, pour une autre raison
: ce n’est pas une chaussee. Sous futaie mature elle est plus etroite,
les houppiers debordent ; sur une coupe rase elle est beaucoup plus
large. L’ecart n’est pas constant, il est correle a la structure du
peuplement riverain, donc il change tout au long du troncon. Un decalage
constant se calibre ; celui-la non — on mesurerait surtout l’age du
peuplement voisin. S’ajoute une contrainte d’echelle : un modele de
hauteur de canopee predit depuis l’ortho travaille a une maille de
l’ordre de **1,5 m**, ou une chaussee de 4 m ne couvre que 2,7 cellules.
`LARGEUR_DEGAGEE` et `LARGEUR_NDVI` n’alimentent donc pas
[`dsr_calibrer_largeur()`](https://pobsteta.github.io/dessertR/reference/dsr_calibrer_largeur.md).

Avec une vraie verite terrain (decametre, GNSS, photo-interpretation sur
ortho THR),
[`dsr_calibrer_largeur()`](https://pobsteta.github.io/dessertR/reference/dsr_calibrer_largeur.md)
balaie une grille de parametres et renvoie biais, MAE et RMSE. Sans
elle, `dev/03_validation.R` se limite aux diagnostics de coherence —
dispersion intra-troncon, ordre des classes — qui disent si la mesure
est reproductible et plausible, pas si elle est juste.

``` sh
DSR_INVENTAIRE=1 Rscript dev/03_validation.R   # que voit-on ?
Rscript dev/03_validation.R                    # tout traiter
```

La racine des projets est resolue selon le systeme (`%LOCALAPPDATA%`
sous Windows, `Library/Application Support` sous macOS, `XDG_DATA_HOME`
sous Linux) ; `DSR_NEMETON` la remplace au besoin, `DSR_PROJETS`
restreint a un sous-ensemble.

## Ce qui reste a faire

1.  **Obtenir une verite terrain sur la largeur.** C’est le vrai verrou
    : l’estimateur est stabilise et son erreur bornee sur profils de
    synthese, mais aucune source disponible ne permet de le calibrer. Ni
    la BD TOPO (attribut declaratif), ni une desserte issue d’un autre
    algorithme (circulaire). Il faut un releve. Restera ensuite a
    distinguer l’erreur de mesure de l’**ecart de definition** : la
    largeur roulable retient la bande de faible devers, une largeur
    carrossable de gestionnaire inclut souvent les accotements — cette
    question-la se tranche avec le gestionnaire, pas au seuil.
2.  **Valider sur des massifs contrastes.** Feuillus de plaine, resineux
    de montagne, plateau calcaire — ce dernier est le test decisif du
    canal geomorphologique, la ou les chemins creux et les traces
    fossiles abondent.
3.  **Publier les chiffres de validation ici meme** : RMSE lateral, MAE
    sur la largeur, matrice de confusion sur l’etat, precision/rappel
    sur les troncons hors BD TOPO et sur `APTE_GRUMIER`.
4.  **Caler les seuils d’aptitude avec un gestionnaire.**
    [`dsr_seuils_grumier()`](https://pobsteta.github.io/dessertR/reference/dsr_seuils_grumier.md)
    est indicatif et ne doit jamais etre pris pour un referentiel.
5.  **Vignette** « du telechargement des dalles au GPKG de sortie ».

## Installation

``` r

# lasR n'est pas sur le CRAN
install.packages("lasR", repos = "https://r-lidar.r-universe.dev")

remotes::install_github("pobsteta/dessertR")
```

Le paquet embarque un noyau **Rust** (openness / sky-view factor et
pathfinder anisotrope) : l’installation depuis les sources demande
`cargo` et `rustc >= 1.65`. Les dependances cargo sont vendorisees, la
compilation se fait hors ligne.

Paquets optionnels : `igraph` (topologie du reseau), `sfnetworks`
(export graphe), `ranger` (conductivite apprise par foret aleatoire),
`lasR` (canal nuage), et
[`vecnet`](https://github.com/r-lidar-lab/vecnet) — non publie sur le
CRAN — utilise automatiquement comme vectoriseur s’il est installe.

## Donnees

- **Lidar HD** (IGN, licence ouverte Etalab) : nuage classe en 11
  categories, MNT et MNH au pas de 50 cm, dalles de 1 km x 1 km.
  Couverture metropolitaine complete annoncee pour fin 2026.
- **BD TOPO** (IGN, licence ouverte Etalab).

Un extrait reel de 200 x 200 m (nuage classe, MNT, MNH, extrait BD TOPO)
est versionne dans `inst/extdata/` sous licence ouverte Etalab, et sert
aux tests d’integration.

## Origine

La methode reprend et adapte celle d’ALSroads et de vecnet, developpes
au laboratoire de Jean-Romain Roussel a l’Universite Laval pour la
desserte forestiere quebecoise :

- Roussel, J.-R., Bourdon, J.-F., Morley, I. D., Coops, N. C., &
  Achim, A. (2022). Correction, update, and enhancement of vectorial
  forestry road maps using ALS data, a pathfinder, and seven metrics.
  *International Journal of Applied Earth Observation and
  Geoinformation*, 114, 103020.
  <https://doi.org/10.1016/j.jag.2022.103020>
- Roussel, J.-R., Bourdon, J.-F., Morley, I. D., Coops, N. C., &
  Achim, A. (2023). Vectorial and topologically valid segmentation of
  forestry road networks from ALS data. *International Journal of
  Applied Earth Observation and Geoinformation*, 118, 103267.
  <https://doi.org/10.1016/j.jag.2023.103267>

Le post-traitement des centre-lignes emprunte a deux travaux plus
recents : le lissage de Savitzky-Golay de Wang *et al.* (2025,
arXiv:2502.07486) et la representation par courbes de Bezier de DOGE
(Sun *et al.*, 2025, arXiv:2511.19850) — cette derniere ramenee a un
ajustement direct, l’algorithme publie supposant PyTorch et un GPU.

Le contexte francais deplace la valeur : la BD TOPO etant deja precise
en planimetrie, le repositionnement des troncons devient secondaire
devant la mesure, la qualification d’etat et la detection de la desserte
non cartographiee.

## Licence

GPL (\>= 3).
