# Ecart a la norme Certu, troncon par troncon

Confronte la largeur MESUREE
([`dsr_measure()`](https://pobsteta.github.io/dessertR/reference/dsr_measure.md))
a la largeur NORMATIVE de la fiche Certu
([`dsr_emprise_certu()`](https://pobsteta.github.io/dessertR/reference/dsr_emprise_certu.md)).
Le sens de lecture est fixe : la mesure informe sur ce que la norme ne
fait que supposer – « cette piste fait 3,2 m la ou la fiche en suppose 2
». L'inverse, ramener la mesure vers la norme, detruirait le signal que
le paquet produit (voir
[`dsr_emprise_certu()`](https://pobsteta.github.io/dessertR/reference/dsr_emprise_certu.md)).

## Usage

``` r
dsr_ecart_norme(
  stations,
  certu,
  id = "troncon",
  champ_mesure = "LARGEUR_ROULABLE",
  champ_certu = "LARGEUR_CHAUSSEE_CERTU"
)
```

## Arguments

- stations:

  `sf`/`data.frame` des stations
  ([`dsr_measure()`](https://pobsteta.github.io/dessertR/reference/dsr_measure.md)),
  portant `champ_mesure`, la colonne `id` et, si possible,
  `BORDS_CHAUSSEE`.

- certu:

  Sortie de
  [`dsr_emprise_certu()`](https://pobsteta.github.io/dessertR/reference/dsr_emprise_certu.md)
  (ou tout objet portant `champ_certu`).

- id:

  Nom de la colonne identifiant le troncon dans `stations`. Defaut
  `"troncon"`.

- champ_mesure, champ_certu:

  Colonnes comparees. Defauts `"LARGEUR_ROULABLE"` et
  `"LARGEUR_CHAUSSEE_CERTU"`.

## Value

Un `data.frame`, une ligne par troncon mesure : la colonne `id`,
`N_STATIONS`, `LARGEUR_MED` (mediane mesuree), `LARGEUR_NORME`,
`ECART_NORME` (mesure - norme, m), `ECART_REL` (rapporte a la norme) et
`BORDS_RESOLUS` (part de stations ou la chaussee est resolue, `NA` si
`BORDS_CHAUSSEE` est absent). Les troncons que la fiche n'apparie pas
gardent `LARGEUR_NORME = NA` et un ecart `NA` : ils sont conserves, pas
silencieusement retires.

## Details

**Comparer ce qui est comparable.** `LARGEUR_ROULABLE` vise la chaussee,
et `LARGEUR_CHAUSSEE_CERTU` est une largeur de chaussee : les deux se
correspondent. Mais quand la rupture chaussee/accotement n'est pas
resolue,
[`dsr_measure()`](https://pobsteta.github.io/dessertR/reference/dsr_measure.md)
retombe sur la **plateforme** et le signale par `BORDS_CHAUSSEE`. La
colonne `BORDS_RESOLUS` reporte cette part au niveau du troncon : proche
de 0, l'ecart compare une plateforme a une largeur de chaussee, et se
lit comme un majorant.

**Appariement.**
[`dsr_measure()`](https://pobsteta.github.io/dessertR/reference/dsr_measure.md)
ne nomme pas ses troncons ; l'usage etabli est d'ajouter soi-meme une
colonne (`troncon`) portant l'indice de ligne du reseau mesure. Si
`certu` porte la meme colonne, l'appariement se fait dessus ; sinon il
se fait par **indice de ligne**, ce qui suppose que `certu` est le meme
reseau, dans le meme ordre.

## See also

[`dsr_emprise_certu()`](https://pobsteta.github.io/dessertR/reference/dsr_emprise_certu.md),
[`dsr_measure()`](https://pobsteta.github.io/dessertR/reference/dsr_measure.md),
[`dsr_rapport()`](https://pobsteta.github.io/dessertR/reference/dsr_rapport.md).

## Examples

``` r
stations <- data.frame(troncon = c(1, 1, 2, 2),
  LARGEUR_ROULABLE = c(3.0, 3.4, 2.1, 2.3), BORDS_CHAUSSEE = c(2, 2, 0, 0))
certu <- data.frame(LARGEUR_CHAUSSEE_CERTU = c(2, 2))
dsr_ecart_norme(stations, certu)
#>   troncon N_STATIONS LARGEUR_MED LARGEUR_NORME ECART_NORME ECART_REL
#> 1       1          2         3.2             2         1.2       0.6
#> 2       2          2         2.2             2         0.2       0.1
#>   BORDS_RESOLUS
#> 1             1
#> 2             0
```
