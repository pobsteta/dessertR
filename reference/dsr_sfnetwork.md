# Exporter le reseau en objet sfnetworks

Convertit les aretes d'un reseau
([`dsr_reseau()`](https://pobsteta.github.io/dessertR/reference/dsr_reseau.md))
en objet `sfnetwork` – un graphe spatial valide plutot qu'une collection
de `LINESTRING` (BRIEF section 3.8). Necessite le paquet `sfnetworks`.

## Usage

``` r
dsr_sfnetwork(reseau)
```

## Arguments

- reseau:

  La sortie de
  [`dsr_reseau()`](https://pobsteta.github.io/dessertR/reference/dsr_reseau.md),
  ou directement un `sf` d'aretes.

## Value

Un objet `sfnetwork`.

## See also

[`dsr_reseau()`](https://pobsteta.github.io/dessertR/reference/dsr_reseau.md).
