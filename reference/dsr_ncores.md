# Nombre de coeurs alloues aux traitements lasR

Politique du paquet : **tous les coeurs sauf un**, au minimum 1. Le
defaut de `lasR` est la moitie des coeurs
([`lasR::half_cores()`](https://rdrr.io/pkg/lasR/man/multithreading.html)),
trop conservateur pour un traitement de bloc ; en garder un seul de
libre laisse la machine utilisable et evite d'affamer les threads
GDAL/terra qui tournent entre deux etages du pipeline.

## Usage

``` r
dsr_ncores(reserve = 1L)
```

## Arguments

- reserve:

  Nombre de coeurs laisses libres. Defaut 1.

## Value

Un entier \>= 1.

## Details

La base de calcul est
[`lasR::ncores()`](https://rdrr.io/pkg/lasR/man/multithreading.html) –
le nombre de threads que `lasR` peut reellement utiliser (1 si la
version installee est sans OpenMP) – et non
[`parallel::detectCores()`](https://rdrr.io/r/parallel/detectCores.html),
qui annoncerait des coeurs inexploitables.

Deux garde-fous : l'option `dessertR.ncores` impose une valeur fixe, et
le resultat est plafonne a 2 sous `R CMD check`
(`_R_CHECK_LIMIT_CORES_`). Enfin, une strategie posee globalement par
[`lasR::set_parallel_strategy()`](https://rdrr.io/pkg/lasR/man/multithreading.html)
reste prioritaire sur ce reglage : c'est `lasR` qui arbitre.

## See also

[`lasR::set_parallel_strategy()`](https://rdrr.io/pkg/lasR/man/multithreading.html),
[`lasR::ncores()`](https://rdrr.io/pkg/lasR/man/multithreading.html).

## Examples

``` r
dsr_ncores()
#> [1] 3
```
