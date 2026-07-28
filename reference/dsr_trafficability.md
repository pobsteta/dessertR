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
  `GABARIT_LIBRE`, `SURPLOMB` et `HAUT_SURPLOMB` optionnels).

- seuils:

  Seuils d'aptitude ; defaut
  [`dsr_seuils_grumier()`](https://pobsteta.github.io/dessertR/reference/dsr_seuils_grumier.md).

## Value

Une liste : `stations` (les memes, avec `APTE_GRUMIER` logique et
`MOTIF_INAPTITUDE` – criteres bloquants separes par `+`, `""` si apte)
et `resume` (part de longueur apte et compte par motif).

## Details

Cinq criteres, dont trois toujours evalues (`largeur`, `pente`, `rayon`)
et deux qui ne le sont que si les colonnes correspondantes sont
presentes :

- `gabarit` – hauteur libre sous branches
  ([`dsr_gabarit_libre()`](https://pobsteta.github.io/dessertR/reference/dsr_gabarit_libre.md),
  sur le nuage classe) inferieure a `gabarit_min` ;

- `surplomb` – houppier empietant sur l'emprise **et** situe sous
  `gabarit_min`
  ([`dsr_gabarit_lateral()`](https://pobsteta.github.io/dessertR/reference/dsr_gabarit_lateral.md),
  sur un modele de hauteur de canopee). L'empietement seul ne bloque
  rien : un couvert ferme a 20 m au-dessus d'une route ne gene aucun
  grumier.

Un critere non evaluable (`NA`) ne declare jamais d'inaptitude.

## See also

[`dsr_measure()`](https://pobsteta.github.io/dessertR/reference/dsr_measure.md),
[`dsr_gabarit_libre()`](https://pobsteta.github.io/dessertR/reference/dsr_gabarit_libre.md),
[`dsr_gabarit_lateral()`](https://pobsteta.github.io/dessertR/reference/dsr_gabarit_lateral.md),
[`dsr_seuils_grumier()`](https://pobsteta.github.io/dessertR/reference/dsr_seuils_grumier.md).
