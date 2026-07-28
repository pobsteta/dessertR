# Package index

## Catalogage des dalles

- [`dsr_catalog()`](https://pobsteta.github.io/dessertR/reference/dsr_catalog.md)
  : Cataloguer un jeu de dalles Lidar HD
- [`dsr_parse_dalle()`](https://pobsteta.github.io/dessertR/reference/dsr_parse_dalle.md)
  : Decoder le nom d'une dalle Lidar HD

## Emprises et corridors

- [`dsr_corridor()`](https://pobsteta.github.io/dessertR/reference/dsr_corridor.md)
  : Construire le corridor autour d'un reseau de reference
- [`dsr_dalles_requises()`](https://pobsteta.github.io/dessertR/reference/dsr_dalles_requises.md)
  : Selectionner les dalles intersectant une emprise

## Canal geomorphologique (MNT)

- [`dsr_grille_reference()`](https://pobsteta.github.io/dessertR/reference/dsr_grille_reference.md)
  : Construire la grille de reference d'une dalle
- [`dsr_layers_dtm()`](https://pobsteta.github.io/dessertR/reference/dsr_layers_dtm.md)
  : Assembler le canal geomorphologique complet
- [`dsr_micro_relief()`](https://pobsteta.github.io/dessertR/reference/dsr_micro_relief.md)
  : Canaux de micro-relief openness et SVF d'un MNT
- [`dsr_pente()`](https://pobsteta.github.io/dessertR/reference/dsr_pente.md)
  : Pente locale du MNT
- [`dsr_rugosite()`](https://pobsteta.github.io/dessertR/reference/dsr_rugosite.md)
  : Rugosite residuelle du MNT
- [`dsr_slrm()`](https://pobsteta.github.io/dessertR/reference/dsr_slrm.md)
  : Modele de relief local simplifie (SLRM / MSTP)
- [`dsr_vesselness()`](https://pobsteta.github.io/dessertR/reference/dsr_vesselness.md)
  : Linearite (vesselness de Frangi) et orientation du MNT
- [`dsr_canaux_externes()`](https://pobsteta.github.io/dessertR/reference/dsr_canaux_externes.md)
  : Ingerer des canaux morphometriques externes et les aligner

## Canal surface et qualite (nuage)

- [`dsr_layers_pc()`](https://pobsteta.github.io/dessertR/reference/dsr_layers_pc.md)
  : Canaux de surface et de qualite du nuage de points

## Conductivite

- [`dsr_conductivite()`](https://pobsteta.github.io/dessertR/reference/dsr_conductivite.md)
  :

  Conductivite geomorphologique `sigma_geo`

- [`dsr_sigma_surf()`](https://pobsteta.github.io/dessertR/reference/dsr_sigma_surf.md)
  :

  Conductivite de surface `sigma_surf`

- [`dsr_appartenance()`](https://pobsteta.github.io/dessertR/reference/dsr_appartenance.md)
  : Fonction d'appartenance floue

- [`dsr_specs_geomorpho()`](https://pobsteta.github.io/dessertR/reference/dsr_specs_geomorpho.md)
  : Specifications d'appartenance par defaut du canal geomorphologique

- [`dsr_specs_surface()`](https://pobsteta.github.io/dessertR/reference/dsr_specs_surface.md)
  : Specifications d'appartenance par defaut du canal de surface

## Conductivite apprise

- [`dsr_echantillon()`](https://pobsteta.github.io/dessertR/reference/dsr_echantillon.md)
  : Echantillon d'apprentissage de la conductivite
- [`dsr_apprendre_conductivite()`](https://pobsteta.github.io/dessertR/reference/dsr_apprendre_conductivite.md)
  : Ajuster une conductivite apprise
- [`predict(`*`<dsr_modele_conductivite>`*`)`](https://pobsteta.github.io/dessertR/reference/predict.dsr_modele_conductivite.md)
  [`print(`*`<dsr_modele_conductivite>`*`)`](https://pobsteta.github.io/dessertR/reference/predict.dsr_modele_conductivite.md)
  : Predire une conductivite apprise

## Etat de la desserte

- [`dsr_etat()`](https://pobsteta.github.io/dessertR/reference/dsr_etat.md)
  : Etat de la desserte par croisement des deux conductivites
- [`dsr_etat_trace()`](https://pobsteta.github.io/dessertR/reference/dsr_etat_trace.md)
  : Etat de la desserte le long d'un trace
- [`dsr_divergence()`](https://pobsteta.github.io/dessertR/reference/dsr_divergence.md)
  : Divergence des canaux de conductivite

## Recherche de trace

- [`dsr_pathfinder()`](https://pobsteta.github.io/dessertR/reference/dsr_pathfinder.md)
  : Trace de moindre cout anisotrope entre deux points
- [`dsr_repositionner()`](https://pobsteta.github.io/dessertR/reference/dsr_repositionner.md)
  : Repositionner un reseau de reference sous contrainte

## Mesure de la geometrie

- [`dsr_measure()`](https://pobsteta.github.io/dessertR/reference/dsr_measure.md)
  : Mesurer la geometrie de la desserte le long d'un trace
- [`dsr_profils()`](https://pobsteta.github.io/dessertR/reference/dsr_profils.md)
  : Profils transversaux le long d'un trace
- [`dsr_calibrer_largeur()`](https://pobsteta.github.io/dessertR/reference/dsr_calibrer_largeur.md)
  : Calibrer la mesure de largeur sur une reference terrain
- [`dsr_emprise_certu()`](https://pobsteta.github.io/dessertR/reference/dsr_emprise_certu.md)
  : Emprise routiere normative (methode Certu, fiche 1.7)

## Praticabilite (grumier)

- [`dsr_trafficability()`](https://pobsteta.github.io/dessertR/reference/dsr_trafficability.md)
  : Aptitude au grumier et motif d'inaptitude
- [`dsr_gabarit_libre()`](https://pobsteta.github.io/dessertR/reference/dsr_gabarit_libre.md)
  : Gabarit libre sous branches le long d'un trace
- [`dsr_places()`](https://pobsteta.github.io/dessertR/reference/dsr_places.md)
  : Detecter les elargissements (places de depot / retournement)
- [`dsr_seuils_grumier()`](https://pobsteta.github.io/dessertR/reference/dsr_seuils_grumier.md)
  : Seuils d'aptitude au grumier par defaut

## Reseau (topologie)

- [`dsr_reseau()`](https://pobsteta.github.io/dessertR/reference/dsr_reseau.md)
  : Construire un reseau topologiquement coherent
- [`dsr_coller_noeuds()`](https://pobsteta.github.io/dessertR/reference/dsr_coller_noeuds.md)
  : Coller les extremites proches sur des noeuds partages
- [`dsr_dedupe_paralleles()`](https://pobsteta.github.io/dessertR/reference/dsr_dedupe_paralleles.md)
  : Dedupliquer les traces paralleles
- [`dsr_sfnetwork()`](https://pobsteta.github.io/dessertR/reference/dsr_sfnetwork.md)
  : Exporter le reseau en objet sfnetworks

## Export et rapport

- [`dsr_export_gpkg()`](https://pobsteta.github.io/dessertR/reference/dsr_export_gpkg.md)
  : Exporter les couches d'un massif en GeoPackage
- [`dsr_qml_categorise()`](https://pobsteta.github.io/dessertR/reference/dsr_qml_categorise.md)
  : Ecrire un style QGIS categorise (.qml)
- [`dsr_rapport()`](https://pobsteta.github.io/dessertR/reference/dsr_rapport.md)
  : Rapport de synthese d'un traitement

## Detection hors reference

- [`dsr_detecter()`](https://pobsteta.github.io/dessertR/reference/dsr_detecter.md)
  : Detecter la desserte hors reference
- [`dsr_indice_detection()`](https://pobsteta.github.io/dessertR/reference/dsr_indice_detection.md)
  : Indice de detection de desserte hors reference
- [`dsr_vectoriser()`](https://pobsteta.github.io/dessertR/reference/dsr_vectoriser.md)
  : Vectoriser une carte de desserte
