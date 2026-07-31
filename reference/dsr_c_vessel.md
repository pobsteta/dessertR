# Ancrer l'echelle de la vesselness sur une emprise de reference

Calcule, echelle par echelle, le `c` que
[`dsr_vesselness()`](https://pobsteta.github.io/dessertR/reference/dsr_vesselness.md)
deriverait de `mnt` – la moitie du maximum de la norme de Frobenius du
Hessien. Le resultat se repasse tel quel a
[`dsr_vesselness()`](https://pobsteta.github.io/dessertR/reference/dsr_vesselness.md)
ou
[`dsr_layers_dtm()`](https://pobsteta.github.io/dessertR/reference/dsr_layers_dtm.md)
pour que la vesselness cesse de dependre de l'etendue analysee.

## Usage

``` r
dsr_c_vessel(mnt, echelles_m = c(1, 2, 4))
```

## Arguments

- mnt:

  Le MNT de reference (`SpatRaster` ou chemin). Prendre l'emprise la
  plus large du chantier : c'est elle qui fixe le bareme.

- echelles_m:

  Echelles, en metres. Doit valoir ce qui sera passe ensuite a
  [`dsr_vesselness()`](https://pobsteta.github.io/dessertR/reference/dsr_vesselness.md).
  Defaut `c(1, 2, 4)`.

## Value

Un vecteur numerique nomme (`c_1`, `c_2`, ...), une valeur par echelle.

## Details

**Le probleme.** Sans `c` fixe, la vesselness est relative a l'emprise
fournie : le meme terrain, analyse seul ou au sein d'un bloc plus vaste,
ne rend pas la meme valeur. Le defaut agit **en amont** des fonctions
d'appartenance, donc aucun reglage de bornes dans
[`dsr_specs_geomorpho()`](https://pobsteta.github.io/dessertR/reference/dsr_specs_geomorpho.md)
ne le rattrape, et il touche aussi le `seuil_vessel` de
[`dsr_indice_detection()`](https://pobsteta.github.io/dessertR/reference/dsr_indice_detection.md),
ou une vesselness rescalee est comparee a un seuil absolu.

**L'usage.** Calculer une fois sur l'emprise de reference du chantier –
le massif entier, pas la fenetre du jour – puis passer le vecteur obtenu
a tous les traitements ulterieurs. Deux fenetres traitees avec le meme
`c` sont alors comparables, y compris en regime `corridor`.

## See also

[`dsr_vesselness()`](https://pobsteta.github.io/dessertR/reference/dsr_vesselness.md),
[`dsr_layers_dtm()`](https://pobsteta.github.io/dessertR/reference/dsr_layers_dtm.md).

## Examples

``` r
mnt <- terra::rast(nrows = 40, ncols = 40, xmin = 0, xmax = 40, ymin = 0,
  ymax = 40, crs = "EPSG:2154")
terra::values(mnt) <- runif(1600)
dsr_c_vessel(mnt, echelles_m = c(1, 2))
#>        c_1        c_2 
#> 0.10470876 0.05028717 
```
