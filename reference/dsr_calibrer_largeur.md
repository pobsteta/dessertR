# Calibrer la mesure de largeur sur une reference terrain

Balaie une grille de parametres de
[`dsr_measure()`](https://pobsteta.github.io/dessertR/reference/dsr_measure.md)
et confronte la largeur mesuree a une largeur de reference (releves du
gestionnaire, GNSS, photo-interpretation), station par station. Renvoie
le tableau des ecarts, trie du meilleur au pire, pour arbitrer sur des
chiffres plutot que sur une impression.

## Usage

``` r
dsr_calibrer_largeur(
  traces,
  mnt,
  reference,
  champ_largeur,
  grille = NULL,
  long_min = 30,
  confiance = NULL,
  seuils_confiance = c(0, 2, 5, Inf),
  ...
)
```

## Arguments

- traces:

  `sf` des troncons a mesurer.

- mnt:

  Le MNT (`SpatRaster`).

- reference:

  `sf` portant une largeur de reference **mesuree independamment** (voir
  Details) — pas la sortie d'un autre algorithme.

- champ_largeur:

  Nom de la colonne de `reference` portant la largeur (m).

- grille:

  `data.frame` des combinaisons a essayer ; une colonne par argument de
  [`dsr_measure()`](https://pobsteta.github.io/dessertR/reference/dsr_measure.md)
  a faire varier. `NULL` (defaut) balaie `methode_largeur` x
  `tol_planeite`.

- long_min:

  Longueur minimale (m) d'un troncon mesure. Defaut 30.

- confiance:

  `SpatRaster` de confiance pour la stratification ; `NULL` pour ne pas
  stratifier.

- seuils_confiance:

  Bornes de stratification de `confiance`. Defaut `c(0, 2, 5, Inf)`
  (points sol par m2).

- ...:

  Arguments communs transmis a
  [`dsr_measure()`](https://pobsteta.github.io/dessertR/reference/dsr_measure.md).

## Value

Un `data.frame` : les colonnes de `grille`, puis `n` (stations
appariees), `biais` (mesure - reference, m), `mae`, `rmse`, `med_dsr`,
`med_ref`. Trie par `mae` croissante. Si `confiance` est fourni, une
ligne par combinaison **et** par classe de confiance, avec la colonne
`strate`.

## Details

**Ce qui peut servir de reference, et ce qui ne le peut pas.** Le
calibrage retient le reglage qui **minimise l'ecart** : pointer cette
fonction vers la sortie d'un autre algorithme ne mesure donc pas un
biais, il le *reproduit* — on selectionne les parametres qui imitent le
mieux l'autre methode, defauts compris. Une reference doit etre
**independante de toute mesure automatique** : releve au decametre,
GNSS, ou photo-interpretation sur ortho THR.

Deux sources tentantes qui n'en sont pas :

- la **largeur declarative d'une base cartographique**
  (`LARGEUR_DE_CHAUSSEE` de la BD TOPO, par exemple) est souvent
  defautee par classe et vide sur les chemins et sentiers — elle ne
  soutient pas un calibrage au decimetre. Elle reste utile comme
  controle **ordinal** : la largeur mesuree doit se ranger dans l'ordre
  des classes ;

- la **sortie d'un traitement anterieur** (desserte corrigee par
  ALSroads ou equivalent) est disqualifiee par construction.

**Le calibrage ne peut pas commencer par le seuil.** Avec
`methode_largeur = "gradient"`, le biais depend du pas transversal et du
lissage autant que de `seuil_devers` : la valeur trouvee ne vaudrait que
pour un triplet de parametres et un niveau de bruit. C'est pourquoi le
defaut est `"planeite"`, dont le biais est stable (voir
[`dsr_measure()`](https://pobsteta.github.io/dessertR/reference/dsr_measure.md))
— un seuil cale sur un massif a alors une chance d'etre transferable.

**Separer le biais de mesure de l'ecart de definition.** Un biais
residuel constant, une fois la methode stabilisee, ne signale pas une
erreur de mesure mais un desaccord sur ce qu'on mesure : la largeur
roulable retient la bande de faible devers, tandis qu'une « largeur
carrossable » de gestionnaire inclut souvent les accotements. C'est une
question a trancher avec le gestionnaire, pas un parametre a tordre.
Regarder `biais` et `mae` ensemble : un biais constant avec une MAE
faible est un decalage de definition ; une MAE forte avec un biais
faible est du bruit de mesure.

**Stratifier.** La qualite du MNT commande tout (BRIEF, risque n.3) :
passer `confiance` (typiquement `densite_sol` de
[`dsr_layers_pc()`](https://pobsteta.github.io/dessertR/reference/dsr_layers_pc.md))
fait sortir les ecarts par classe de confiance. Un biais qui se creuse
quand la densite de points sol s'effondre n'appelle pas un autre seuil,
il appelle une reserve sur le domaine de validite.

## See also

[`dsr_measure()`](https://pobsteta.github.io/dessertR/reference/dsr_measure.md),
[`dsr_layers_pc()`](https://pobsteta.github.io/dessertR/reference/dsr_layers_pc.md).
