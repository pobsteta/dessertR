# Construire la grille de reference d'une dalle

Toutes les sorties raster du paquet, quelle que soit leur origine (MNT
via `terra`, nuage via `lasR`, canaux importes), doivent partager une
**grille unique** ; sans cela l'empilement final est bancal (BRIEF
section 3.1). Cette grille est derivee du MNT et calee a 1 m par defaut
: le MNT Lidar HD a 50 cm est trop fin pour les couches morphometriques
multi-echelles, ou il n'apporte que du bruit d'interpolation pour un
cout multiplie par quatre (section 3.2).

## Usage

``` r
dsr_grille_reference(mnt, res = DSR_RES_MULTIECHELLE)
```

## Arguments

- mnt:

  Un `SpatRaster` (le MNT), ou un chemin vers un GeoTIFF.

- res:

  Resolution de la grille en metres. Defaut 1 (voir
  DSR_RES_MULTIECHELLE). Descendre a 0.5 uniquement pour la mesure fine.

## Value

Un `SpatRaster` **sans valeurs** servant de gabarit d'alignement.

## Details

L'emprise est calee sur des multiples de la resolution, pour que deux
dalles voisines produisent des grilles jointives.

## See also

[`dsr_canaux_externes()`](https://pobsteta.github.io/dessertR/reference/dsr_canaux_externes.md)
qui aligne des canaux sur cette grille.
