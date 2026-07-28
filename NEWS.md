# dessertR (developpement)

## Mesure : deux estimateurs remplaces, et pourquoi

Les deux grandeurs qui commandent l'aptitude grumier etaient mal estimees. Les
chiffres ci-dessous viennent de profils et de traces de synthese a geometrie
connue.

* **Largeur roulable** — `dsr_measure(methode_largeur = "planeite")`, nouveau
  defaut. On ajuste le plan de chaussee sur une fenetre centrale puis on
  s'ecarte tant que la surface reste a moins de `tol_planeite` de ce plan, avec
  interpolation du bord entre echantillons. Sur une plateforme de 4,00 m bombee
  a 3 % :

  | bruit du MNT | `"gradient"` (ancien) | `"planeite"` |
  |---|---|---|
  | aucun | 3,00 m (−1,00) | 3,92 m (−0,08) |
  | 5 cm | 2,56 m (−1,44) | 3,72 m (−0,28) |
  | 10 cm | 0,93 m (−3,08) | 3,66 m (−0,34) |

  Le point decisif n'est pas le gain de biais mais la stabilite : le biais du
  seuil de pente depend du **pas transversal** (−3,74 m a 0,1 m de pas, 0,00 m a
  1 m) autant que de `seuil_devers`. Un seuil cale sur un massif n'aurait valu
  que pour ce pas et ce niveau de bruit — l'ancien estimateur n'etait pas
  calibrable. `tol_planeite` a lui une lecture physique : il doit depasser la
  fleche du bombement (`bombement x largeur / 2`).
* **Devers** — desormais la pente du plan ajuste. Il est distingue du bombement
  de drainage, qui est symetrique et ne cree aucun devers net.
* **Rayon de courbure** — `base_courbure` (defaut 30 m) : ajustement d'un cercle
  des moindres carres sur une fenetre physique, au lieu du cercle circonscrit a
  trois stations consecutives. Sur un arc de rayon vrai 60 m quantifie au metre
  puis lisse, la mediane des rayons passe de **16,6 m a 56,5 m**. C'etait une
  faute lourde : `dsr_trafficability()` compare `RAYON_COURBURE` a un seuil de
  12 m, donc l'ancien estimateur declarait inapte a peu pres toute route
  courbe. La base de 30 m est aussi l'ordre de grandeur d'un ensemble routier
  grumier. `RAYON_COURBURE_P05` s'ajoute au minimum, moins sensible a une
  station aberrante.
* `dsr_calibrer_largeur()` : balaie une grille de parametres contre une largeur
  de reference et renvoie biais, MAE et RMSE, avec stratification optionnelle
  par confiance du MNT. Un biais constant a MAE faible signale un ecart de
  **definition** (la reference inclut-elle les accotements ?), pas une erreur de
  mesure — la distinction est documentee, elle se tranche avec le gestionnaire.
* `dev/03_validation.R` remplace `dev/03_validation_wsfi.R` : il **decouvre** les
  projets nemeton exploitables au lieu d'en coder un en dur, les traite tous, et
  publie un tableau de calibrage croise. Un reglage qui gagne sur un massif et
  perd sur les autres n'est pas un reglage.
  - La racine nemeton est resolue **selon le systeme** : `%LOCALAPPDATA%` sous
    Windows (`nemeton/nemeton/projects`), `Library/Application Support` sous
    macOS, `XDG_DATA_HOME` sous Linux. `DSR_NEMETON` reste prioritaire.
  - L'inventaire liste **tous** les projets avec ce qu'ils portent (dalles, MNT
    mosaique, roads, desserte de reference) plutot que d'ecarter en silence. Un
    projet sans desserte de reference est traite quand meme, aux valeurs par
    defaut : il n'est simplement pas calibrable, et le rapport le dit.
  - `DSR_INVENTAIRE=1` s'arrete apres l'inventaire, pour voir ce qui est trouve
    sans lancer les traitements.
* README reecrit : etat reel de la chaine, fiabilite mesuree grandeur par
  grandeur, et ce qui reste a caler.

## Lissage et raccordement des centre-lignes

* `dsr_vectoriser(lissage = )` : le squelette d'une emprise rasterisee est un
  escalier, et ce n'est pas un defaut cosmetique -- `dsr_measure()` en tire
  `RAYON_COURBURE` et `SINUOSITE`, dont depend l'aptitude grumier. Sur un arc de
  cercle de reference, l'escalier **surestime la longueur de 26 % et la
  sinuosite de 27 %**.
  - `"savitzky-golay"` (defaut, Wang *et al.* 2025) : ajustement polynomial
    local sur `x(t)` et `y(t)`. Ramene l'erreur de longueur a 1,8 %, l'ecart
    median a la courbe vraie de 0,32 m a 0,13 m.
  - `"bezier"` : Bezier cubiques par morceaux ajustees aux moindres carres
    (representation de DOGE, Sun *et al.* 2025, ramenee a un ajustement direct
    sans optimisation differentiable). Courbe C1 par morceaux ; **moins fidele
    que Savitzky-Golay** (0,39 m) et sans gain de sommets une fois
    reechantillonnee en `LINESTRING`. A choisir pour la continuite, pas pour la
    precision.
  - Dans les deux cas les extremites sont figees : elles portent la topologie.
* `dsr_vectoriser(raccorder = )` : relie deux extremites de composantes
  distinctes separees par une trouee de conductivite. Au critere de distance de
  Wang *et al.* s'ajoute un critere d'alignement, sans quoi une piste serait
  soudee au cloisonnement qu'elle croise sans le rejoindre. **Desactive par
  defaut** : cette etape invente de la geometrie la ou la donnee ne montre rien.
* Constat qui a conduit a revoir la mesure : le rayon de courbure dependait
  bien plus du pas des stations que du lissage. Il n'a PAS ete corrige en
  touchant a `pas` -- qui doit rester serre pour les profils transversaux --
  mais en decouplant les deux echelles, voir `base_courbure` ci-dessus.

## Conductivite apprise

* `dsr_echantillon()` : table d'apprentissage prelevee sur une pile de canaux --
  positifs sous le reseau connu, negatifs au-dela de `buffer_neg`, **bande grise
  ecartee** (accotements, fosses, imprecision planimetrique de la reference).
* `dsr_apprendre_conductivite()` : ajuste le modele (`glm` par defaut, `ranger`
  en option) et rapporte l'**AUC en validation croisee stratifiee**, pas en
  resubstitution ; l'ecart avec l'AUC d'apprentissage mesure le surapprentissage.
* `dsr_conductivite(method = "model", modele = ...)` et
  `dsr_sigma_surf(method = "model", ...)` : l'interface prevue des l'origine
  est desormais remplie. La voie parametrique reste le defaut.
* Le BRIEF evoquait un petit U-Net ; on ne l'a pas suivi. Avec un seul massif de
  validation et des canaux deja concus pour la tache, une logistique inspectable
  fait aussi bien et n'apporte ni torch, ni GPU, ni dependance Python. Le
  passage a un modele convolutif se fera derriere la meme interface, quand le
  jeu de validation le justifiera.

## Detection hors reference, regime complet et vectorisation

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

## Jeu de donnees d'exemple versionne

* `inst/extdata/` : secteur reel de 200 x 200 m (nuage classe ~327 000 points,
  MNT/MNH 50 cm, extrait BD TOPO) centre sur un franchissement route x cours
  d'eau, sous licence ouverte Etalab (voir `LICENSE.note`). Genere par
  `data-raw/make_example.R`. Les tests d'integration (catalogage, layers_pc,
  mesure, chaine geomorphologique) tournent desormais dessus, y compris en CI.

## Detection hors reference (v2)

* `dsr_detecter()` : repere les axes de desserte ABSENTS de la reference
  (pistes, cloisonnements, anciennes RF) -- cellules de forte conductivite (et
  linearite) hors du corridor BD TOPO, regroupees en composantes connexes et
  reduites a une centre-ligne par ACP (BRIEF section 3.9). A affiner avec
  `vecnet` pour une vectorisation topologique complete.

## Repositionnement contraint par la BD TOPO

* `dsr_repositionner()` : recale un reseau de reference (BD TOPO) sur le MNT
  lidar via le pathfinder, **sans jamais s'ecarter de plus de `deviation_max`
  metres de l'axe d'origine** (couloir dur + attraction douce vers l'axe). La
  reference fait autorite : le reseau est **integralement conserve** (repli sur
  la geometrie d'origine si le pathfinder echoue). Corrige le probleme revele par
  la validation (le repositionnement libre accroche des lineaires paralleles --
  risque n.1 du BRIEF) : le recalage contraint ne degrade plus la mesure.

## Jeu de validation

* `dev/03_validation.R` : harnais de validation sur un bloc reel de 4 dalles
  Lidar HD (MNT/MNH 50 cm, reseau BD TOPO, desserte de reference foretaccess).
  Chaine complete + comparaison de la largeur roulable a la reference (MAE,
  biais), brute vs repositionnee. Constats : la mesure sous-estime la largeur
  carrossable (seuils a caler) et le repositionnement sur `sigma_geo` seul peut
  accrocher un lineaire parallele (risque n.1 du BRIEF) -- a contraindre par
  l'axe de reference ou `sigma_surf`.
* `dsr_measure()` : detection de la chaussee plus robuste au desalignement de
  l'axe (plage plane la plus proche du centre, plutot que croissance depuis le
  centre exact) ; seuil de devers par defaut releve a 0.15 (cale par validation).

## Export et rapport

* `dsr_export_gpkg()` : ecrit les couches vectorielles d'un massif dans un unique
  GeoPackage, avec les styles QGIS des couches reconnues.
* `dsr_qml_categorise()` : genere un style QGIS `.qml` categorise (etat,
  aptitude), charge automatiquement a cote de la couche.
* `dsr_rapport()` : synthese Markdown d'un traitement (geometrie, praticabilite,
  etat, reseau). Cloture le socle fonctionnel du BRIEF (hors detection v2).

## Coherence topologique du reseau

* `dsr_reseau()` : assemble une collection de traces en reseau valide (BRIEF
  section 3.8) -- collage des noeuds partages ([dsr_coller_noeuds()]),
  deduplication des paralleles ([dsr_dedupe_paralleles()]), analyse des
  composantes et rattachement au reseau public (une desserte qui ne debouche
  nulle part est signalee). Noyau `igraph`.
* `dsr_sfnetwork()` : export en objet `sfnetwork` (graphe spatial valide) quand
  `sfnetworks` est disponible.

## Praticabilite grumier

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

## Mesure de la geometrie

* `dsr_profils()` : profils transversaux preleves perpendiculairement au trace
  tous les `pas` metres, echantillonnes en bilineaire sur le MNT.
* `dsr_measure()` : premier livrable metier (BRIEF section 3.6) -- largeur
  roulable, devers, fosses (0/1/2), pente longitudinale par station, et
  metriques globales de rayon de courbure minimal et de sinuosite ;
  optionnellement `CONFIANCE_MNT` (densite de points sol) et `DEPLACEMENT` a une
  geometrie de reference. Lissage transversal / longitudinal pour amortir le
  bruit du MNT sous couvert. Valide sur profils synthetiques (devers, largeur,
  sinuosite, courbure).

## Etat le long du trace

* `dsr_etat_trace()` : echantillonne `sigma_geo` / `sigma_surf` le long d'un
  trace ([dsr_pathfinder()] ou geometrie BD TOPO), classe l'etat par troncon et
  resume la repartition (longueur et pourcentage par etat). C'est la lecture
  pertinente de l'etat -- en raster plein il est bruite, le long du trace retenu
  il devient interpretable (BRIEF section 3.4). La classification est factorisee
  avec `dsr_etat()`. Valide sur dalle reelle.

## Pathfinder anisotrope

* `dsr_pathfinder()` : recherche de trace de moindre cout sur `sigma_geo`, avec
  noyau Rust -- etat d'orientation (cellule, cap), penalite d'anisotropie (les
  deplacements en travers de `theta` sont penalises), penalite de courbure, et
  voisinage 16 qui supprime le biais de metrication du Dijkstra 8-connexe
  (BRIEF section 3.5). Sortie `sf` `LINESTRING` + champ de cout cumule. Les
  sauts « cavalier » sont verrouilles pour ne pas franchir une barriere `NA`
  d'une cellule. Valide sur dalle reelle (le trace suit la route forestiere).

## Conductivite de surface et etat

* `dsr_sigma_surf()` : conductivite de surface (emprise encore degagee), fondee
  sur `densite_sousetage` -- le signal d'abandon -- avec masque d'exclusion.
* `dsr_divergence()` et `dsr_etat()` : croisement `sigma_geo` / `sigma_surf` en
  quatre etats (en service, abandonnee, trouee sans route, hors route), le
  diagnostic d'etat du BRIEF (section 3.4). Valide sur dalle reelle : les routes
  actives ressortent en `en_service`.

## Canal surface et qualite via le nuage

* `dsr_layers_pc()` : rasterise via `lasR` les metriques du nuage classe sur la
  grille de reference -- `densite_sol` (confiance du MNT), `taux_penetration`,
  `densite_sousetage` (signal d'abandon, 0,3-3 m au-dessus du sol), `h_couvert`,
  `masque_exclusion` et `masque_pont`. Regime corridor par `emprise` / `masque`.
  Valide sur dalle Lidar HD reelle (lecture COPC par lasR).

## Canal geomorphologique complet et conductivite

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

Premiere version taggee. Socle et noyau natif.

## Socle

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
