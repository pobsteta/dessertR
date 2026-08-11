# Cubature deblai / remblai le long d'un trace

Chiffre, tous les `pas` metres, les volumes de deblai et de remblai
qu'exige la mise a un gabarit donne, par construction d'un **profil en
travers theorique** confronte au terrain (voir `dev/SPEC_CUBATURE.md`).

## Usage

``` r
dsr_cubature(
  trace,
  mnt,
  largeur,
  regime,
  s_amont = 1,
  s_aval = 0.6,
  p_rocher = 0,
  pas = 10,
  demi_largeur = 20,
  pas_travers = 0.05,
  ripage_min = 0.35,
  ripage_max = 0.6,
  tol_z = 0.05,
  tol_xy = NULL
)
```

## Arguments

- trace:

  Un `sf`/`sfc` `LINESTRING`, ou l'element `trace` de
  [`dsr_pathfinder()`](https://pobsteta.github.io/dessertR/reference/dsr_pathfinder.md).

- mnt:

  Le MNT (`SpatRaster`).

- largeur:

  Largeur de plateforme visee, en metres. Un scalaire, ou un vecteur
  d'une valeur par station.

- regime:

  Ce que porte le `mnt` : `"elargissement"` (la plateforme y est deja
  creusee – cas d'un MNT Lidar HD) ou `"construction"` (terrain vierge,
  emprise absente). **Sans defaut** : omis, `"elargissement"` est
  suppose et la fonction le dit. Le regime ne change pas le calcul – le
  terrain est toujours pris tel quel – il declare ce qu'on lui donne, et
  en `"construction"` il verifie cette declaration contre le terrain
  (voir Details).

- s_amont, s_aval:

  Pente des talus amont et aval, en pente (`1` = 100 %). Defauts 1 et
  0.6.

- p_rocher:

  Pourcentage de rocher dans le deblai, pour le volume de roche. Defaut
  0.

- pas:

  Espacement des points d'analyse le long du trace, en metres. Defaut
  10.

- demi_largeur:

  Demi-largeur des profils, en metres. Doit couvrir l'emprise attendue,
  talus compris. Defaut 20.

- pas_travers:

  Pas d'echantillonnage transversal, en metres. Defaut 0.05 ; au-dela de
  0.1 les sections sont sensiblement biaisees.

- ripage_min, ripage_max:

  Devers encadrant le ripage. Defauts 0.35 et 0.60.

- tol_z:

  Tolerance altimetrique de detection du point de niveau, en metres.
  Defaut 0.05.

- tol_xy:

  Rayon de recherche du point de niveau autour de l'axe, en metres.
  `NULL` (defaut) : la moitie de `largeur`.

## Value

Une liste : `points` (`sf` `POINT`, une ligne par point d'analyse) et
`resume` (totaux). Colonnes de `points` : `chainage`, `long_applicable`,
`config`, `forme`, `ripage`, `pente_g`, `pente_d`, `assise_deblai`,
`assise_remblai`, `talus_amont`, `talus_aval`, `talus_force`,
`section_deblai`, `section_remblai`, `volume_deblai`, `volume_remblai`,
`volume_evacuer`, `volume_roche`, `assiette_deblai`, `assiette_remblai`,
`emprise`, `surface_emprise`.

## Details

Le profil theorique n'est pas ancre sur l'axe du trace – qui n'est pas a
l'altitude du terrain – mais sur le **point de niveau**, point du profil
ou le terrain croise l'altitude de plateforme. De part et d'autre : la
plateforme, puis un talus amont et un talus aval prolonges jusqu'a
retrouver le terrain.

Le partage de l'assise entre deblai et remblai est arbitre par le
**ripage**, interpolation du devers amont entre `ripage_min` et
`ripage_max` : `assise_deblai = largeur / 2 * (1 + ripage^2)`. Sur pente
douce (`ripage = 0`) deblai et remblai s'equilibrent ; sur pente raide
(`ripage = 1`) le remblai ne tient pas et la totalite passe en deblai.

**Le terrain est pris tel quel**, et c'est `regime` qui dit ce qu'il
porte. Sur un MNT Lidar HD, une route existante est deja creusee : la
cubature obtenue est celle de l'**ecart au gabarit**
(`"elargissement"`), pas celle d'une construction sur terrain vierge.
C'est le regime utile en France –
[`dsr_trafficability()`](https://pobsteta.github.io/dessertR/reference/dsr_trafficability.md)
dit que le grumier ne passe pas, la cubature dit combien pour qu'il
passe. Pour chiffrer une construction, fournir un MNT dont l'emprise a
ete comblee **et** le declarer par `regime = "construction"`.

**La declaration est verifiee.** En regime `"construction"`, chaque
profil est teste : la pente en travers de la bande centrale est-elle
nettement plus faible que celle des bandes qui la flanquent ? Sur un
versant vierge les deux se valent ; sur un versant deja terrasse, le
replat de la route trahit l'emprise. Si plus de la moitie des profils
portent cette signature, la fonction le signale – elle ne bloque pas, la
decision reste a l'appelant. Le controle **s'abstient** sous 10 % de
pente en travers : sur du plat, un replat ne se distingue de rien.

Le **volume a evacuer** n'est pas le volume de deblai : sur un profil
equilibre, le deblai est reemploye en remblai sur place. Seuls les
profils ou ce reemploi est impossible – devers superieur a `ripage_max`,
ou plateforme entierement sous ou au-dessus du terrain – sont cumules a
l'evacuation.

## See also

[`dsr_profils()`](https://pobsteta.github.io/dessertR/reference/dsr_profils.md),
[`dsr_measure()`](https://pobsteta.github.io/dessertR/reference/dsr_measure.md),
[`dsr_emprise_certu()`](https://pobsteta.github.io/dessertR/reference/dsr_emprise_certu.md).

## Examples

``` r
mnt <- terra::rast(nrows = 200, ncols = 200, xmin = 0, xmax = 100,
  ymin = 0, ymax = 100, crs = "EPSG:2154")
# Versant regulier a 30 %, pente vers l'est.
terra::values(mnt) <- terra::xFromCell(mnt, seq_len(terra::ncell(mnt))) * 0.3
tr <- sf::st_sfc(sf::st_linestring(cbind(c(50, 50), c(10, 90))),
  crs = "EPSG:2154")
# Plan incline sans emprise : c'est bien une construction, on le declare.
cub <- dsr_cubature(tr, mnt, largeur = 4, regime = "construction", pas = 10)
cub$resume
#>         regime n_points longueur volume_deblai volume_remblai volume_evacuer
#> 1 construction        9       80         68.58          96.12              0
#>   volume_roche surface_emprise n_talus_force
#> 1            0             552             0
```
