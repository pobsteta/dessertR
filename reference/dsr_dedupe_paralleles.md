# Dedupliquer les traces paralleles

Supprime les traces qui longent une autre a moins d'une largeur d'ecart
– les doublons paralleles qu'engendre une correction troncon par troncon
(BRIEF section 3.8). On conserve les traces les plus longues et l'on
ecarte celles largement recouvertes par le tampon des traces deja
retenues.

## Usage

``` r
dsr_dedupe_paralleles(traces, largeur = 3, recouvrement = 0.7)
```

## Arguments

- traces:

  Un `sf` de `LINESTRING`.

- largeur:

  Ecart (m) en deca duquel deux traces sont consideres doublons. Defaut
  3.

- recouvrement:

  Fraction de longueur recouverte au-dela de laquelle une trace est
  ecartee. Defaut 0.7.

## Value

Le sous-ensemble `sf` conserve.

## See also

[`dsr_reseau()`](https://pobsteta.github.io/dessertR/reference/dsr_reseau.md).
