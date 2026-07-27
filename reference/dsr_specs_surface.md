# Specifications d'appartenance par defaut du canal de surface

Regles reliant les couches de
[`dsr_layers_pc()`](https://pobsteta.github.io/dessertR/reference/dsr_layers_pc.md)
a la probabilite qu'une emprise soit **encore degagee** : le
discriminant central est `densite_sousetage` (echos 0,3-3 m au-dessus du
sol) – faible = degagee, forte = recolonisee (BRIEF sections 0 et 3.4).
`taux_penetration` (ouverture au-dessus de l'emprise) intervient en
appui, avec un poids moindre.

## Usage

``` r
dsr_specs_surface()
```

## Value

Une liste nommee par canal, chaque element une liste `type` / `poids`
pour
[`dsr_sigma_surf()`](https://pobsteta.github.io/dessertR/reference/dsr_sigma_surf.md).

## See also

[`dsr_sigma_surf()`](https://pobsteta.github.io/dessertR/reference/dsr_sigma_surf.md).
