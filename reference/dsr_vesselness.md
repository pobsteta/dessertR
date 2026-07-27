# Linearite (vesselness de Frangi) et orientation du MNT

Probabilite qu'un pixel appartienne a une structure **lineaire en
creux** (une route deprimee : plateforme en deblai, chemin creux,
fosse), calculee par l'analyse des valeurs propres du **Hessien** a
plusieurs echelles (filtre de Frangi). Fournit aussi l'**orientation**
locale de la ligne, qui alimente le cout anisotrope du pathfinder (BRIEF
sections 3.2 et 3.5).

## Usage

``` r
dsr_vesselness(mnt, echelles_m = c(1, 2, 4), beta = 0.5, c = NULL)
```

## Arguments

- mnt:

  Le MNT (`SpatRaster` ou chemin), de preference a 1 m.

- echelles_m:

  Ecarts-types gaussiens en metres. Defaut `c(1, 2, 4)`.

- beta:

  Sensibilite au rapport d'anisotropie (Frangi). Defaut 0.5.

- c:

  Sensibilite a l'intensite de structure ; `NULL` (defaut) -\> moitie du
  maximum de la norme de Frobenius du Hessien, par echelle
  (auto-echelle).

## Value

Un `SpatRaster` a deux couches : `vesselness` (0..1) et `theta`
(orientation de la ligne en degres, 0..180), alignees sur `mnt`.

## Details

A chaque echelle, le MNT est lisse par une gaussienne d'ecart-type
`sigma`, le Hessien est estime par differences finies (normalise par
`sigma^2`), et la vesselness de Frangi est evaluee pour les structures
**sombres** (vallees, `lambda2 > 0`). La reponse retenue est le maximum
sur les echelles, et l'orientation celle de l'echelle gagnante. Les
routes etant des creux, on ne detecte pas les cretes.

## See also

[`dsr_layers_dtm()`](https://pobsteta.github.io/dessertR/reference/dsr_layers_dtm.md).
