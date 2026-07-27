# Divergence des canaux de conductivite

Ecart signe `sigma_geo - sigma_surf`. Positif la ou l'empreinte persiste
dans le terrain mais que la surface s'est refermee : c'est la signature
d'une **route abandonnee / recolonisee** (BRIEF section 3.4). Negatif
sur les trouees sans route (faux positifs geomorphologiques).

## Usage

``` r
dsr_divergence(sigma_geo, sigma_surf)
```

## Arguments

- sigma_geo, sigma_surf:

  `SpatRaster` mono-couche alignes, dans `[0, 1]`.

## Value

Un `SpatRaster` mono-couche `divergence` dans `[-1, 1]`.

## See also

[`dsr_etat()`](https://pobsteta.github.io/dessertR/reference/dsr_etat.md).
