# dessertR (developpement)

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
