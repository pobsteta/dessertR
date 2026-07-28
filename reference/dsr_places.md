# Detecter les elargissements (places de depot / retournement)

Reperage des elargissements locaux de la chaussee le long du trace : une
station dont la largeur roulable depasse nettement la largeur courante
est un candidat place de depot ou de retournement (BRIEF section 3.7),
sortie a part entiere.

## Usage

``` r
dsr_places(stations, marge = 2, long_min = 6)
```

## Arguments

- stations:

  Le `sf` `stations` de
  [`dsr_measure()`](https://pobsteta.github.io/dessertR/reference/dsr_measure.md)
  (colonne `LARGEUR_ROULABLE`, `chainage`).

- marge:

  Surlargeur minimale (m) au-dessus de la mediane pour signaler un
  elargissement. Defaut 2.

- long_min:

  Longueur minimale continue (m) d'un elargissement. Defaut 6.

## Value

Un `sf` `POINT` des centres d'elargissement, avec `chainage`, `longueur`
et `largeur_max`. Zero ligne si aucun.

## See also

[`dsr_measure()`](https://pobsteta.github.io/dessertR/reference/dsr_measure.md).
