# Conductivite geomorphologique `sigma_geo`

Fusionne les couches du canal geomorphologique en une conductivite
`sigma_geo` dans `[sigma_min, 1]` — la probabilite qu'un pixel porte
l'**empreinte** d'une route (BRIEF section 3.4). La combinaison est une
**moyenne geometrique ponderee** des fonctions d'appartenance, plancher
a `sigma_min` pour eviter les zeros infranchissables. Les canaux
multi-echelles (p. ex. `openness_neg_2` / `_5` / `_10`) sont regroupes
par nom de base et moyennes avant ponderation.

## Usage

``` r
dsr_conductivite(
  couches,
  specs = dsr_specs_geomorpho(),
  method = c("param", "model"),
  sigma_min = 0.05,
  confiance = NULL
)
```

## Arguments

- couches:

  Le `SpatRaster` multi-bandes de
  [`dsr_layers_dtm()`](https://pobsteta.github.io/dessertR/reference/dsr_layers_dtm.md)
  (ou tout sous-ensemble aligne).

- specs:

  Regles d'appartenance ; defaut
  [`dsr_specs_geomorpho()`](https://pobsteta.github.io/dessertR/reference/dsr_specs_geomorpho.md).
  Les canaux sans regle sont ignores.

- method:

  `"param"` (defaut) pour la combinaison parametrique, ou `"model"`
  (conductivite apprise) — reserve, non encore implemente.

- sigma_min:

  Plancher de conductivite. Defaut 0.05.

- confiance:

  `SpatRaster` de confiance dans `[0, 1]`, aligne sur `couches` ; `NULL`
  pour ne pas ponderer.

## Value

Un `SpatRaster` mono-couche `sigma_geo`, valeurs dans `[sigma_min, 1]`.

## Details

**Ponderation par la confiance.** La ou la densite de points sol
s'effondre, l'openness devient du bruit : passer cette couche de
confiance (normalisee dans `[0, 1]`, typiquement `densite_sol` mise a
l'echelle) via `confiance` tire `sigma_geo` vers l'**incertain** (0.5)
plutot que vers une valeur faible trompeuse.

## See also

[`dsr_layers_dtm()`](https://pobsteta.github.io/dessertR/reference/dsr_layers_dtm.md),
[`dsr_appartenance()`](https://pobsteta.github.io/dessertR/reference/dsr_appartenance.md),
[`dsr_specs_geomorpho()`](https://pobsteta.github.io/dessertR/reference/dsr_specs_geomorpho.md).

## Examples

``` r
# \donttest{
mnt <- terra::rast(
  nrows = 60, ncols = 60, xmin = 0, xmax = 60, ymin = 0, ymax = 60,
  crs = "EPSG:2154"
)
terra::values(mnt) <- 100 + terra::rowFromCell(mnt, seq_len(terra::ncell(mnt))) * 0.1
pile <- dsr_layers_dtm(mnt, res = 1)
sg <- dsr_conductivite(pile)
# }
```
