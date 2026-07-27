# Pente locale du MNT

Couche de base du canal geomorphologique (BRIEF section 3.2) : une route
est une plateforme localement peu pentue. Simple enveloppe de
[`terra::terrain()`](https://rspatial.github.io/terra/reference/terrain.html).

## Usage

``` r
dsr_pente(mnt, unite = c("degrees", "radians"))
```

## Arguments

- mnt:

  Le MNT (`SpatRaster` ou chemin).

- unite:

  `"degrees"` (defaut) ou `"radians"`.

## Value

Un `SpatRaster` mono-couche `pente`.

## See also

[`dsr_layers_dtm()`](https://pobsteta.github.io/dessertR/reference/dsr_layers_dtm.md).
