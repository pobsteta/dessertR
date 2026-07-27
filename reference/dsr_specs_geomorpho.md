# Specifications d'appartenance par defaut du canal geomorphologique

Jeu de regles *provisoire* reliant les couches de
[`dsr_layers_dtm()`](https://pobsteta.github.io/dessertR/reference/dsr_layers_dtm.md)
a leur appartenance a « empreinte de route » : une route est un lineaire
en creux (`vesselness` haute), aux bords concaves (`openness_neg` haute)
et anormalement lisse (`rugosite` basse). Les bornes sont laissees a
`NULL` (derivees des quantiles) tant qu'un jeu de validation ne permet
pas de les caler (BRIEF section 4). A adapter librement.

## Usage

``` r
dsr_specs_geomorpho()
```

## Value

Une liste nommee par nom de base de canal ; chaque element est une liste
`type` / `a` / `b` / `poids` pour
[`dsr_conductivite()`](https://pobsteta.github.io/dessertR/reference/dsr_conductivite.md).

## See also

[`dsr_conductivite()`](https://pobsteta.github.io/dessertR/reference/dsr_conductivite.md),
[`dsr_appartenance()`](https://pobsteta.github.io/dessertR/reference/dsr_appartenance.md).
