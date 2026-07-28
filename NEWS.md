# dessertR (developpement)

## Conductivite apprise (lot 8)

* `dsr_echantillon()` : table d'apprentissage prelevee sur une pile de canaux --
  positifs sous le reseau connu, negatifs au-dela de `buffer_neg`, **bande grise
  ecartee** (accotements, fosses, imprecision planimetrique de la reference).
* `dsr_apprendre_conductivite()` : ajuste le modele (`glm` par defaut, `ranger`
  en option) et rapporte l'**AUC en validation croisee stratifiee**, pas en
  resubstitution ; l'ecart avec l'AUC d'apprentissage mesure le surapprentissage.
* `dsr_conductivite(method = "model", modele = ...)` et
  `dsr_sigma_surf(method = "model", ...)` : l'interface prevue au lot 1 est
  desormais remplie. La voie parametrique reste le defaut.
* Le BRIEF evoquait un petit U-Net ; on ne l'a pas suivi. Avec un seul massif de
  validation et des canaux deja concus pour la tache, une logistique inspectable
  fait aussi bien et n'apporte ni torch, ni GPU, ni dependance Python. Le
  passage a un modele convolutif se fera derriere la meme interface, quand le
  jeu de validation le justifiera.

## Detection hors reference, regime complet et vectorisation (lot 7)

* `dsr_indice_detection()` : carte de probabilite `p_desserte` hors du corridor
  de reference, fusion ponderee de `sigma_geo`, **`sigma_surf`** et
  `vesselness`. Le poids majoritaire va au canal de surface : un cloisonnement
  se lit d'abord dans la **discontinuite du sous-etage**, pas dans le terrain ou
  son empreinte se confond avec les traces fossiles (BRIEF section 3.9).
* `dsr_vectoriser()` : vectoriseur **enfichable**. Defaut interne = amincissement
  de Zhang-Suen puis tracage du graphe du squelette -- chaque chaine entre deux
  noeuds devient une arete, ce qui **conserve les embranchements** la ou la
  centre-ligne par ACP ecrasait toute une composante en une seule ligne (un
  peigne de cloisonnements sort maintenant en autant d'aretes). `vecnet`
  (r-lidar-lab, Roussel *et al.* 2023) est utilise automatiquement s'il est
  installe ; l'ACP reste disponible.
* `dsr_detecter()` : enchaine les deux, accepte `sigma_surf`, et distingue le
  regime `complet` (toute la grille) du regime `corridor` (restreint a une
  `emprise`). Sortie directement exploitable par `dsr_reseau()`.
* Les vectoriseurs appris (SAM-Road, RNGDet++, GLD-Road) dominent sur les jeux
  satellite mais supposent GPU, PyTorch et un corpus annote massif : ecartes
  pour l'instant, l'interface enfichable leur laisse la porte ouverte.

## Jeu de donnees d'exemple versionne (lot 0)

* `inst/extdata/` : secteur reel de 200 x 200 m (nuage classe ~327 000 points,
  MNT/MNH 50 cm, extrait BD TOPO) centre sur un franchissement route x cours
  d'eau, sous licence ouverte Etalab (voir `LICENSE.note`). Genere par
  `data-raw/make_example.R`. Les tests d'integration (catalogage, layers_pc,
  mesure, chaine geomorphologique) tournent desormais dessus, y compris en CI.

## Detection hors reference (lot 7, v2)

* `dsr_detecter()` : repere les axes de desserte ABSENTS de la reference
  (pistes, cloisonnements, anciennes RF) -- cellules de forte conductivite (et
  linearite) hors du corridor BD TOPO, regroupees en composantes connexes et
  reduites a une centre-ligne par ACP (BRIEF section 3.9). A affiner avec
  `vecnet` pour une vectorisation topologique complete.

## Repositionnement contraint par la BD TOPO (lot 4)

* `dsr_repositionner()` : recale un reseau de reference (BD TOPO) sur le MNT
  lidar via le pathfinder, **sans jamais s'ecarter de plus de `deviation_max`
  metres de l'axe d'origine** (couloir dur + attraction douce vers l'axe). La
  reference fait autorite : le reseau est **integralement conserve** (repli sur
  la geometrie d'origine si le pathfinder echoue). Corrige le probleme revele par
  la validation (le repositionnement libre accroche des lineaires paralleles --
  risque n.1 du BRIEF) : le recalage contraint ne degrade plus la mesure.

## Jeu de validation (lot 1)

* `dev/03_validation_wsfi.R` : harnais de validation sur un bloc reel de 4 dalles
  Lidar HD (MNT/MNH 50 cm, reseau BD TOPO, desserte de reference foretaccess).
  Chaine complete + comparaison de la largeur roulable a la reference (MAE,
  biais), brute vs repositionnee. Constats : la mesure sous-estime la largeur
  carrossable (seuils a caler) et le repositionnement sur `sigma_geo` seul peut
  accrocher un lineaire parallele (risque n.1 du BRIEF) -- a contraindre par
  l'axe de reference ou `sigma_surf`.
* `dsr_measure()` : detection de la chaussee plus robuste au desalignement de
  l'axe (plage plane la plus proche du centre, plutot que croissance depuis le
  centre exact) ; seuil de devers par defaut releve a 0.15 (cale par validation).

## Export et rapport (lot 6)

* `dsr_export_gpkg()` : ecrit les couches vectorielles d'un massif dans un unique
  GeoPackage, avec les styles QGIS des couches reconnues.
* `dsr_qml_categorise()` : genere un style QGIS `.qml` categorise (etat,
  aptitude), charge automatiquement a cote de la couche.
* `dsr_rapport()` : synthese Markdown d'un traitement (geometrie, praticabilite,
  etat, reseau). Cloture le socle fonctionnel du BRIEF (hors detection v2).

## Coherence topologique du reseau (lot 6)

* `dsr_reseau()` : assemble une collection de traces en reseau valide (BRIEF
  section 3.8) -- collage des noeuds partages ([dsr_coller_noeuds()]),
  deduplication des paralleles ([dsr_dedupe_paralleles()]), analyse des
  composantes et rattachement au reseau public (une desserte qui ne debouche
  nulle part est signalee). Noyau `igraph`.
* `dsr_sfnetwork()` : export en objet `sfnetwork` (graphe spatial valide) quand
  `sfnetworks` est disponible.

## Praticabilite grumier (lot 5)

* `dsr_gabarit_libre()` : hauteur libre sous branches le long du trace, calculee
  sur le nuage classe (lasR) -- critere reel pour un grumier (~4,5 m), absent des
  bases existantes.
* `dsr_trafficability()` + `dsr_seuils_grumier()` : verdict `APTE_GRUMIER` et
  surtout `MOTIF_INAPTITUDE` (quel critere bloque, et ou), sur des seuils
  parametrables a caler avec le gestionnaire (BRIEF section 3.7).
* `dsr_places()` : detection des elargissements locaux (places de depot / de
  retournement).
* `dsr_measure()` expose desormais le rayon de courbure par station
  (`RAYON_COURBURE`) ; `dsr_profils()` accepte `methode` (bilineaire / plus
  proche voisin).

## Mesure de la geometrie (lot 2)

* `dsr_profils()` : profils transversaux preleves perpendiculairement au trace
  tous les `pas` metres, echantillonnes en bilineaire sur le MNT.
* `dsr_measure()` : premier livrable metier (BRIEF section 3.6) -- largeur
  roulable, devers, fosses (0/1/2), pente longitudinale par station, et
  metriques globales de rayon de courbure minimal et de sinuosite ;
  optionnellement `CONFIANCE_MNT` (densite de points sol) et `DEPLACEMENT` a une
  geometrie de reference. Lissage transversal / longitudinal pour amortir le
  bruit du MNT sous couvert. Valide sur profils synthetiques (devers, largeur,
  sinuosite, courbure).

## Etat le long du trace (lot 4)

* `dsr_etat_trace()` : echantillonne `sigma_geo` / `sigma_surf` le long d'un
  trace ([dsr_pathfinder()] ou geometrie BD TOPO), classe l'etat par troncon et
  resume la repartition (longueur et pourcentage par etat). C'est la lecture
  pertinente de l'etat -- en raster plein il est bruite, le long du trace retenu
  il devient interpretable (BRIEF section 3.4). La classification est factorisee
  avec `dsr_etat()`. Valide sur dalle reelle.

## Pathfinder anisotrope (lot 4)

* `dsr_pathfinder()` : recherche de trace de moindre cout sur `sigma_geo`, avec
  noyau Rust -- etat d'orientation (cellule, cap), penalite d'anisotropie (les
  deplacements en travers de `theta` sont penalises), penalite de courbure, et
  voisinage 16 qui supprime le biais de metrication du Dijkstra 8-connexe
  (BRIEF section 3.5). Sortie `sf` `LINESTRING` + champ de cout cumule. Les
  sauts « cavalier » sont verrouilles pour ne pas franchir une barriere `NA`
  d'une cellule. Valide sur dalle reelle (le trace suit la route forestiere).

## Conductivite de surface et etat (lot 3)

* `dsr_sigma_surf()` : conductivite de surface (emprise encore degagee), fondee
  sur `densite_sousetage` -- le signal d'abandon -- avec masque d'exclusion.
* `dsr_divergence()` et `dsr_etat()` : croisement `sigma_geo` / `sigma_surf` en
  quatre etats (en service, abandonnee, trouee sans route, hors route), le
  diagnostic d'etat du BRIEF (section 3.4). Valide sur dalle reelle : les routes
  actives ressortent en `en_service`.

## Canal surface et qualite via le nuage (lot 3, amorce)

* `dsr_layers_pc()` : rasterise via `lasR` les metriques du nuage classe sur la
  grille de reference -- `densite_sol` (confiance du MNT), `taux_penetration`,
  `densite_sousetage` (signal d'abandon, 0,3-3 m au-dessus du sol), `h_couvert`,
  `masque_exclusion` et `masque_pont`. Regime corridor par `emprise` / `masque`.
  Valide sur dalle Lidar HD reelle (lecture COPC par lasR).

## Canal geomorphologique complet et conductivite (lot 1)

* `dsr_pente()`, `dsr_rugosite()` (rugosite residuelle), `dsr_slrm()` (relief
  local simplifie multi-echelle) et `dsr_vesselness()` (linearite de Frangi +
  orientation `theta` pour le pathfinder anisotrope).
* `dsr_layers_dtm()` : assemble toute la pile geomorphologique sur la grille de
  reference a partir du seul MNT.
* `dsr_conductivite()` : `sigma_geo` par combinaison parametrique de fonctions
  d'appartenance ([dsr_appartenance()], [dsr_specs_geomorpho()]), plancher
  `sigma_min` et ponderation par une couche de confiance ; interface
  `method = c("param", "model")` prete pour la conductivite apprise.


# dessertR 0.1.0

Premiere version taggee. Socle du lot 0 et noyau natif.

## Socle (lot 0)

* Catalogage des dalles Lidar HD (LAZ, MNT, MNH) et appariement sur la grille
  kilometrique IGN.
* Extraction du corridor autour d'un reseau de reference.
* Script de benchmark du regime corridor (`dev/02_bench_corridor.R`).

## Canal geomorphologique et noyau Rust

* `dsr_grille_reference()` : grille de reference unique calee a 1 m, derivee du
  MNT, sur laquelle toutes les sorties raster sont alignees.
* `dsr_canaux_externes()` : ingestion et alignement de canaux morphometriques
  precalcules (openness, SVF, SLRM, vesselness), avec garde-fou refusant les
  composites de visualisation 8 bits (CVAT / VAT).
* `dsr_micro_relief()` : sky-view factor et openness (positive / negative) via
  un noyau Rust (`extendr`) vendorise, portage valide de la Relief Visualization
  Toolbox. C'est desormais l'unique chaine native du paquet (voir `dev/BRIEF.md`,
  section 3.5).
