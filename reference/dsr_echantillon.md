# Echantillon d'apprentissage de la conductivite

Construit la table d'apprentissage d'une conductivite apprise : une
ligne par cellule retenue, la valeur de chaque canal en colonnes, et
l'etiquette `y` (1 = route, 0 = hors route). Les positifs sont les
cellules sous le reseau de reference, les negatifs celles suffisamment
eloignees de tout lineaire connu.

## Usage

``` r
dsr_echantillon(
  couches,
  positifs,
  negatifs = NULL,
  buffer_pos = 3,
  buffer_neg = 25,
  emprise = NULL,
  n_max = 20000,
  equilibre = TRUE
)
```

## Arguments

- couches:

  `SpatRaster` multi-bandes des canaux explicatifs — la pile de
  [`dsr_layers_dtm()`](https://pobsteta.github.io/dessertR/reference/dsr_layers_dtm.md),
  celle de
  [`dsr_layers_pc()`](https://pobsteta.github.io/dessertR/reference/dsr_layers_pc.md),
  ou leur concatenation.

- positifs:

  `sf`/`sfc` du reseau connu comme reellement present (BD TOPO verifiee,
  releves GNSS, desserte du gestionnaire).

- negatifs:

  `sf`/`sfc` des zones connues sans desserte ; `NULL` (defaut) pour
  prendre tout ce qui est au-dela de `buffer_neg` des `positifs`.

- buffer_pos:

  Demi-largeur (m) du tampon des positifs. Defaut 3.

- buffer_neg:

  Distance (m) au-dela de laquelle une cellule est tenue pour negative.
  Defaut 25. Ignore si `negatifs` est fourni.

- emprise:

  `sf`/`sfc` polygonal restreignant la zone de prelevement ; `NULL` pour
  toute la grille.

- n_max:

  Nombre maximal de cellules prelevees. Defaut 20000.

- equilibre:

  `TRUE` (defaut) pour tirer autant de positifs que de negatifs ;
  `FALSE` pour conserver la prevalence reelle.

## Value

Un `data.frame` : colonne `y` (0/1) puis une colonne par canal.
L'attribut `"cellules"` porte les numeros de cellule preleves.

## Details

**La bande grise est ecartee.** Entre `buffer_pos` et `buffer_neg`
autour du reseau, aucune cellule n'est prelevee : ce sont les
accotements, les fosses et l'imprecision planimetrique residuelle de la
reference. Les y verser brouillerait les deux classes et le modele
apprendrait le flou de la BD TOPO plutot que la route.

Le tirage est aleatoire : appeler
[`set.seed()`](https://rdrr.io/r/base/Random.html) en amont pour un
echantillon reproductible.

## See also

[`dsr_apprendre_conductivite()`](https://pobsteta.github.io/dessertR/reference/dsr_apprendre_conductivite.md),
[`dsr_conductivite()`](https://pobsteta.github.io/dessertR/reference/dsr_conductivite.md).
