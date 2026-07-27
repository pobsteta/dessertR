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

## Etat de la desserte

- [`dsr_etat()`](https://pobsteta.github.io/dessertR/reference/dsr_etat.md)
  : Etat de la desserte par croisement des deux conductivites
- [`dsr_divergence()`](https://pobsteta.github.io/dessertR/reference/dsr_divergence.md)
  : Divergence des canaux de conductivite

## Recherche de trace

- [`dsr_pathfinder()`](https://pobsteta.github.io/dessertR/reference/dsr_pathfinder.md)
  : Trace de moindre cout anisotrope entre deux points
