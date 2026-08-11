# Regrouper les traces en peignes de paralleles

Repere les faisceaux de lineaires **paralleles et regulierement
espaces** – la signature d'un cloisonnement d'exploitation, qui n'existe
jamais seul.

## Usage

``` r
dsr_peignes(
  traces,
  tol_angle = 15,
  espacement_min = 4,
  espacement_max = 40,
  n_min = 3,
  regularite = 0.5
)
```

## Arguments

- traces:

  `sf` de `LINESTRING`.

- tol_angle:

  Ecart de direction admis dans un groupe, en degres. Defaut 15.

- espacement_min, espacement_max:

  Bornes de recherche de l'espacement entre dents, en metres. Defauts 4
  et 40.

- n_min:

  Nombre minimal de dents. Defaut 3.

- regularite:

  Ecart relatif maximal a l'espacement median. Defaut 0.5.

## Value

Le `sf` d'entree, augmente de `PEIGNE` (identifiant, `NA` hors peigne),
`PEIGNE_N` (nombre de dents) et `PEIGNE_ESPACEMENT` (m, median).

## Details

**Pourquoi une structure plutot qu'une largeur.** Un cloisonnement se
reconnait a son peigne, pas a sa section : les largeurs de cloisonnement
varient avec le peuplement et le materiel, et la largeur que mesure
[`dsr_measure()`](https://pobsteta.github.io/dessertR/reference/dsr_measure.md)
est souvent une plateforme (voir `BORDS_CHAUSSEE`). La periodicite,
elle, est **estimee sur la donnee** : aucune valeur d'espacement n'est
posee a priori, seules les bornes de recherche le sont.

La direction d'une trace est prise entre ses extremites, modulo 180
degres. Les traces de direction voisine sont regroupees, projetees sur
la normale a la direction moyenne du groupe, puis triees : un peigne est
une suite d'au moins `n_min` traces dont les ecarts successifs tiennent
dans `[espacement_min, espacement_max]` et ne s'ecartent pas de plus de
`regularite` de leur mediane.

**Limite assumee** : deux traces colineaires (bout a bout) se projettent
au meme endroit ; `espacement_min` les ecarte du peigne plutot que de
les compter comme deux dents.

## See also

[`dsr_classer()`](https://pobsteta.github.io/dessertR/reference/dsr_classer.md),
[`dsr_dedupe_paralleles()`](https://pobsteta.github.io/dessertR/reference/dsr_dedupe_paralleles.md).

## Examples

``` r
g <- lapply(seq(0, 60, by = 20), function(y)
  sf::st_linestring(cbind(c(0, 100), c(y, y))))
tr <- sf::st_sf(geometry = sf::st_sfc(g, crs = 2154))
dsr_peignes(tr)$PEIGNE
#> [1] 1 1 1 1
```
