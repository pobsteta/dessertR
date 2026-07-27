# Canaux de surface et de qualite du nuage de points

Rasterise, via `lasR`, les metriques du nuage classe qui portent l'etat
de surface d'une desserte et la confiance du MNT (BRIEF section 3.3),
sur une grille alignee sur le MNT :

## Usage

``` r
dsr_layers_pc(
  dalle,
  res = DSR_RES_MULTIECHELLE,
  grille = NULL,
  emprise = NULL,
  masque = NULL,
  sousetage = c(0.3, 3),
  classe_sol = 2L,
  classe_couvert = 5L,
  classe_pont = 17L,
  classes_exclusion = c(6L, 9L, 64L, 66L),
  seuil_couvert = 0.95
)
```

## Arguments

- dalle:

  Chemin d'un fichier LAZ/LAS/COPC, ou une ligne de
  [`dsr_catalog()`](https://pobsteta.github.io/dessertR/reference/dsr_catalog.md)
  (colonne `laz`).

- res:

  Resolution des rasters en metres. Defaut 1 (aligne sur la grille de
  reference ; 2 suffit pour les seules metriques de couvert).

- grille:

  Grille de reference
  ([`dsr_grille_reference()`](https://pobsteta.github.io/dessertR/reference/dsr_grille_reference.md))
  pour aligner les sorties ; `NULL` conserve la grille native de `lasR`.

- emprise:

  Restreint la **lecture** a un rectangle : `NULL` (dalle entiere), un
  vecteur `c(xmin, ymin, xmax, ymax)`, ou un objet `sf`/`sfc`/
  `SpatVector` (son emprise est utilisee).

- masque:

  Objet `sf`/`sfc`/`SpatVector` pour **decouper** finement les sorties
  (corridor) ; `NULL` pour ne pas masquer.

- sousetage:

  Bornes de hauteur du sous-etage, en metres. Defaut `c(0.3, 3)`.

- classe_sol, classe_couvert, classe_pont:

  Codes ASPRS du sol (2), de la vegetation haute (5) et du tablier de
  pont (17).

- classes_exclusion:

  Codes ASPRS a neutraliser. Defaut `c(6, 9, 64, 66)` (batiment, eau,
  sursol perenne, points virtuels).

- seuil_couvert:

  Percentile de hauteur pour `h_couvert`. Defaut 0.95.

## Value

Un `SpatRaster` multi-bandes aligne (si `grille` fourni) portant les
canaux ci-dessus. Noms compatibles avec la suite du traitement
(`sigma_surf`, etat, confiance de
[`dsr_conductivite()`](https://pobsteta.github.io/dessertR/reference/dsr_conductivite.md)).

## Details

- `densite_sol`:

  points sol (classe 2) au m2 – **couche de confiance** du MNT, pas de
  detection.

- `taux_penetration`:

  points sol / points totaux – ouverture de la canopee au-dessus de
  l'emprise.

- `densite_sousetage`:

  echos entre `sousetage` m au-dessus du sol, rapportes au total –
  **recolonisation de l'emprise, le signal d'abandon**, inaccessible au
  MNH.

- `h_couvert`:

  percentile haut de la vegetation haute (hauteur au sol).

- `masque_exclusion`:

  1 la ou une classe neutralisee (eau, points virtuels, sursol perenne,
  batiment) est presente.

- `masque_pont`:

  1 la ou la classe tablier de pont est presente – corridors
  franchissables.

Les hauteurs au sol sont obtenues par
[`lasR::normalize()`](https://rdrr.io/pkg/lasR/man/hag.html) (TIN des
points sol). Les points virtuels sont exclus du calcul de `densite_sol`.
Le regime corridor (lecture restreinte a l'emprise) rend le traitement
d'un massif realiste : passer `emprise` limite la lecture a un rectangle
; passer en plus `masque` decoupe finement les sorties au corridor.

## See also

[`dsr_conductivite()`](https://pobsteta.github.io/dessertR/reference/dsr_conductivite.md)
(consomme `densite_sol` comme confiance),
[`dsr_grille_reference()`](https://pobsteta.github.io/dessertR/reference/dsr_grille_reference.md).
