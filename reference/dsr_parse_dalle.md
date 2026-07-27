# Decoder le nom d'une dalle Lidar HD

Les produits du programme Lidar HD sont diffuses en dalles de 1 km x 1
km dont le nom porte les coordonnees kilometriques du coin nord-ouest,
par exemple `LHD_FXX_0186_6834_PTS_C_LAMB93_IGF69.copc.laz` ou
`LHD_FXX_0186_6834_MNT_O_0M50_LAMB93_IGF69.tif`.

## Usage

``` r
dsr_parse_dalle(x, taille = DSR_TAILLE_DALLE)
```

## Arguments

- x:

  Chemins ou noms de fichiers.

- taille:

  Cote de la dalle en metres. Defaut 1000.

## Value

Un `data.table` avec les colonnes `fichier`, `cle`, `xmin`, `ymin`,
`xmax`, `ymax`. Les lignes non decodables ont des emprises `NA`.

## Details

La fonction extrait le premier couple de nombres a quatre chiffres et en
derive l'emprise. Elle ne lit pas le fichier : c'est un decodage
purement textuel, tres rapide, utilise pour construire l'index avant
toute I/O.

ATTENTION : la convention de nommage a varie entre les blocs et les
millesimes. Verifier le resultat sur un echantillon de vos dalles avant
de faire confiance a l'index, et comparer avec les emprises reelles
retournees par
[`dsr_catalog()`](https://pobsteta.github.io/dessertR/reference/dsr_catalog.md)
avec `entetes = TRUE`.
