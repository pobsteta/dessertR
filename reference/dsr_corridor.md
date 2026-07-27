# Construire le corridor autour d'un reseau de reference

Le regime "corridor" est ce qui rend le traitement d'un massif entier
realiste : sur une dalle forestiere, un tampon de 30 a 50 m autour du
reseau connu ne represente typiquement qu'une petite fraction des
points. Tout le flux de correction et de mesure travaille dans ce
corridor. Seule la detection de desserte absente de la reference impose
le regime complet.

## Usage

``` r
dsr_corridor(reseau, tampon = 40, fusionner = TRUE)
```

## Arguments

- reseau:

  Objet `sf` de lignes (par exemple `troncon_de_route` de la BD TOPO,
  filtre sur l'emprise d'etude).

- tampon:

  Demi-largeur du corridor en metres. Defaut 40, soit large devant la
  plus grosse erreur de position attendue sur la BD TOPO plus la largeur
  d'emprise maximale.

- fusionner:

  Fusionner les tampons en une geometrie unique.

## Value

Un objet `sf` de polygones.
