# Conductivite de surface `sigma_surf`

Probabilite que l'empreinte d'une route soit **encore degagee et
circulable** (canal nuage, etat present), dans `[sigma_min, 1]` (BRIEF
section 3.4). Meme machinerie que
[`dsr_conductivite()`](https://pobsteta.github.io/dessertR/reference/dsr_conductivite.md)
(moyenne geometrique ponderee de fonctions d'appartenance), appliquee
aux couches de
[`dsr_layers_pc()`](https://pobsteta.github.io/dessertR/reference/dsr_layers_pc.md).
Le signal central est `densite_sousetage` : une emprise recolonisee par
le sous-etage n'est plus circulable, meme sous un couvert haut intact –
distinction impossible sur le MNH.

## Usage

``` r
dsr_sigma_surf(
  couches,
  specs = dsr_specs_surface(),
  method = c("param", "model"),
  sigma_min = 0.05,
  masque_exclusion = NULL,
  modele = NULL
)
```

## Arguments

- couches:

  Le `SpatRaster` de
  [`dsr_layers_pc()`](https://pobsteta.github.io/dessertR/reference/dsr_layers_pc.md)
  (ou un sous-ensemble aligne).

- specs:

  Regles d'appartenance ; defaut
  [`dsr_specs_surface()`](https://pobsteta.github.io/dessertR/reference/dsr_specs_surface.md).

- method:

  `"param"` (defaut) ou `"model"` (conductivite apprise, qui demande
  alors un `modele`).

- sigma_min:

  Plancher de conductivite. Defaut 0.05.

- masque_exclusion:

  `SpatRaster` binaire (1 = zone neutralisee, p. ex. `masque_exclusion`
  de
  [`dsr_layers_pc()`](https://pobsteta.github.io/dessertR/reference/dsr_layers_pc.md))
  ; les cellules a 1 sont ramenees a `sigma_min`. `NULL` pour ne pas
  masquer.

- modele:

  Objet `dsr_modele_conductivite`
  ([`dsr_apprendre_conductivite()`](https://pobsteta.github.io/dessertR/reference/dsr_apprendre_conductivite.md))
  requis quand `method = "model"` ; ignore sinon.

## Value

Un `SpatRaster` mono-couche `sigma_surf`.

## Details

`sigma_surf` n'a de sens que **la ou une empreinte existe** : c'est sa
divergence avec `sigma_geo` qui revele l'etat
([`dsr_etat()`](https://pobsteta.github.io/dessertR/reference/dsr_etat.md)),
pas sa valeur absolue.

## See also

[`dsr_conductivite()`](https://pobsteta.github.io/dessertR/reference/dsr_conductivite.md),
[`dsr_layers_pc()`](https://pobsteta.github.io/dessertR/reference/dsr_layers_pc.md),
[`dsr_etat()`](https://pobsteta.github.io/dessertR/reference/dsr_etat.md),
[`dsr_apprendre_conductivite()`](https://pobsteta.github.io/dessertR/reference/dsr_apprendre_conductivite.md).
