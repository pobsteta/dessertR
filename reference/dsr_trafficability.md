# Aptitude au grumier et motif d'inaptitude

Combine les mesures geometriques par station
([`dsr_measure()`](https://pobsteta.github.io/dessertR/reference/dsr_measure.md))
et, si fourni, le gabarit libre
([`dsr_gabarit_libre()`](https://pobsteta.github.io/dessertR/reference/dsr_gabarit_libre.md))
en un verdict `APTE_GRUMIER` et, ce qui le rend exploitable sur le
terrain, le `MOTIF_INAPTITUDE` : **quel critere bloque, et ou** (BRIEF
section 3.7). Un booleen sans motif est inutilisable.

## Usage

``` r
dsr_trafficability(stations, seuils = dsr_seuils_grumier())
```

## Arguments

- stations:

  Le `sf` `stations` de
  [`dsr_measure()`](https://pobsteta.github.io/dessertR/reference/dsr_measure.md)
  (colonnes `LARGEUR_ROULABLE`, `PENTE_LONG`, `RAYON_COURBURE` ;
  `GABARIT_LIBRE` optionnel).

- seuils:

  Seuils d'aptitude ; defaut
  [`dsr_seuils_grumier()`](https://pobsteta.github.io/dessertR/reference/dsr_seuils_grumier.md).

## Value

Une liste : `stations` (les memes, avec `APTE_GRUMIER` logique et
`MOTIF_INAPTITUDE` – criteres bloquants separes par `+`, `""` si apte)
et `resume` (part de longueur apte et compte par motif).

## See also

[`dsr_measure()`](https://pobsteta.github.io/dessertR/reference/dsr_measure.md),
[`dsr_gabarit_libre()`](https://pobsteta.github.io/dessertR/reference/dsr_gabarit_libre.md),
[`dsr_seuils_grumier()`](https://pobsteta.github.io/dessertR/reference/dsr_seuils_grumier.md).
