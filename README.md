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

> **Etat : lot 0, socle en cours.** Rien n'est utilisable en production.
> Voir [`dev/BRIEF.md`](dev/BRIEF.md) pour la conception d'ensemble et la
> feuille de route.

## Ce que le paquet vise

A partir d'un nuage de points Lidar HD classe, du MNT et du MNH, et d'un
reseau de reference imparfait :

- **mesurer** ce que la BD TOPO ne dit pas : largeur roulable, fosses, devers,
  pente longitudinale, rayons de courbure, gabarit libre sous branches ;
- **qualifier la praticabilite**, en particulier l'aptitude au grumier, avec
  le motif d'inaptitude et sa localisation ;
- **diagnostiquer l'etat** en separant le signal geomorphologique (l'empreinte
  de la route dans le terrain, memoire longue) du signal de surface (l'emprise
  est-elle encore degagee). C'est la divergence entre les deux qui revele les
  troncons abandonnes ou recolonises ;
- **detecter** la desserte absente de la reference : pistes, cloisonnements,
  places de depot.

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

Le contexte francais deplace la valeur : la BD TOPO etant deja precise en
planimetrie, le repositionnement des troncons devient secondaire devant la
mesure, la qualification d'etat et la detection de la desserte non cartographiee.

## Installation

```r
# lasR n'est pas sur le CRAN
install.packages("lasR", repos = "https://r-lidar.r-universe.dev")

remotes::install_github("pobsteta/dessertR")
```

## Donnees

- **Lidar HD** (IGN, licence ouverte Etalab) : nuage de points classe en 11
  categories, MNT et MNH au pas de 50 cm, dalles de 1 km x 1 km.
  Couverture metropolitaine complete annoncee pour fin 2026.
- **BD TOPO** (IGN, licence ouverte Etalab).

## Licence

GPL (>= 3).
