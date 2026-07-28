# Coller les extremites proches sur des noeuds partages

Les traces corriges independamment ont des extremites qui devraient
coincider mais different de quelques decimetres. Cette fonction regroupe
les extremites distantes de moins de `tol` et les ramene sur un noeud
commun (BRIEF section 3.8), condition d'un graphe valide.

## Usage

``` r
dsr_coller_noeuds(traces, tol = 1)
```

## Arguments

- traces:

  Un `sf` de `LINESTRING`.

- tol:

  Distance de collage des extremites, en metres. Defaut 1.

## Value

Le meme `sf`, extremites collees.

## See also

[`dsr_reseau()`](https://pobsteta.github.io/dessertR/reference/dsr_reseau.md).
