# Changelog

## dessertR 0.1.0

Premiere version taggee. Socle et noyau natif.

### Socle

- Catalogage des dalles Lidar HD (LAZ, MNT, MNH) et appariement sur la
  grille kilometrique IGN.
- Extraction du corridor autour d’un reseau de reference.
- Script de benchmark du regime corridor (`dev/02_bench_corridor.R`).

### Canal geomorphologique et noyau Rust

- [`dsr_grille_reference()`](https://pobsteta.github.io/dessertR/reference/dsr_grille_reference.md)
  : grille de reference unique calee a 1 m, derivee du MNT, sur laquelle
  toutes les sorties raster sont alignees.
- [`dsr_canaux_externes()`](https://pobsteta.github.io/dessertR/reference/dsr_canaux_externes.md)
  : ingestion et alignement de canaux morphometriques precalcules
  (openness, SVF, SLRM, vesselness), avec garde-fou refusant les
  composites de visualisation 8 bits (CVAT / VAT).
- [`dsr_micro_relief()`](https://pobsteta.github.io/dessertR/reference/dsr_micro_relief.md)
  : sky-view factor et openness (positive / negative) via un noyau Rust
  (`extendr`) vendorise, portage valide de la Relief Visualization
  Toolbox. C’est desormais l’unique chaine native du paquet (voir
  `dev/BRIEF.md`, section 3.5).
