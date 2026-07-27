# Assembler le canal geomorphologique complet

Construit toute la pile de couches geomorphologiques (BRIEF section 3.2)
sur la **grille de reference** (1 m par defaut), a partir du seul MNT.
C'est l'entree du calcul de `sigma_geo`
([`dsr_conductivite()`](https://pobsteta.github.io/dessertR/reference/dsr_conductivite.md)).

## Usage

``` r
dsr_layers_dtm(
  mnt,
  grille = NULL,
  res = DSR_RES_MULTIECHELLE,
  rayons_openness = c(2, 5, 10),
  echelles_vessel = c(1, 2, 4),
  fenetres_slrm = c(5, 15),
  fenetre_rugosite = 5
)
```

## Arguments

- mnt:

  Le MNT (`SpatRaster` ou chemin), typiquement a 50 cm.

- grille:

  Grille de reference
  ([`dsr_grille_reference()`](https://pobsteta.github.io/dessertR/reference/dsr_grille_reference.md))
  ; `NULL` (defaut) -\> derivee du MNT a `res`.

- res:

  Resolution de la grille si `grille` est `NULL`. Defaut 1.

- rayons_openness:

  Rayons d'openness negative multi-echelle, en metres. Defaut
  `c(2, 5, 10)`.

- echelles_vessel:

  Echelles de la vesselness, en metres. Defaut `c(1, 2, 4)`.

- fenetres_slrm:

  Fenetres du SLRM, en metres. Defaut `c(5, 15)`.

- fenetre_rugosite:

  Fenetre de la rugosite, en metres. Defaut 5.

## Value

Un `SpatRaster` multi-bandes aligne sur la grille : `pente`, `rugosite`,
`slrm_*`, `openness_neg_*`, `openness_pos`, `svf`, `vesselness`,
`theta`.

## Details

Le MNT est d'abord reechantillonne sur la grille de reference ; toutes
les couches sont donc nativement alignees, sans reechantillonnage a
posteriori.

## See also

[`dsr_micro_relief()`](https://pobsteta.github.io/dessertR/reference/dsr_micro_relief.md),
[`dsr_conductivite()`](https://pobsteta.github.io/dessertR/reference/dsr_conductivite.md).
