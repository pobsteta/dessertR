# Probabilite qu'un pixel appartienne a une structure **lineaire en creux** (une route deprimee : plateforme en deblai, chemin creux, fosse), calculee par l'analyse des valeurs propres du **Hessien** a plusieurs echelles (filtre de Frangi). Fournit aussi l'**orientation** locale de la ligne, qui alimente le cout anisotrope du pathfinder (BRIEF sections 3.2 et 3.5).

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

  Sensibilite a l'intensite de structure. `NULL` (defaut) -\> moitie du
  maximum de la norme de Frobenius du Hessien, **derive de l'image**,
  echelle par echelle. Sinon un scalaire, ou un vecteur de longueur
  `length(echelles_m)` applique echelle par echelle.

  **Le defaut rend la sortie dependante de l'emprise fournie** : une
  fenetre plus vaste contient un maximum de norme plus eleve, ce qui
  comprime `1 - exp(-s^2 / 2c^2)` pour tous les pixels. Mesure sur un
  meme terrain, `c` derive sur 4 km2 vaut environ le DOUBLE de celui
  derive sur 1 km2 (x2,12 / x2,16 / x1,93 aux echelles 1 / 2 / 4 m).
  Deux sites d'etendues differentes ne sont donc pas comparables, et le
  regime `corridor` change le bareme. Passer un `c` fixe ancre l'echelle
  et rend la vesselness absolue ;
  [`dsr_c_vessel()`](https://pobsteta.github.io/dessertR/reference/dsr_c_vessel.md)
  le calcule sur une emprise de reference.

  Un scalaire unique ne convient pas : `c` varie d'un facteur ~3,5 entre
  les echelles d'un meme site, et l'aplatir fausserait la selection du
  maximum multi-echelle. Utiliser un vecteur.

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
