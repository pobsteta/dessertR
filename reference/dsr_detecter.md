# Detecter la desserte hors reference

Repere les axes de desserte probables **absents du reseau de reference**
: construit la carte `p_desserte` hors du corridor de reference
([`dsr_indice_detection()`](https://pobsteta.github.io/dessertR/reference/dsr_indice_detection.md)),
puis la vectorise
([`dsr_vectoriser()`](https://pobsteta.github.io/dessertR/reference/dsr_vectoriser.md)).
Complementaire du recalage, qui lui conserve la reference
([`dsr_repositionner()`](https://pobsteta.github.io/dessertR/reference/dsr_repositionner.md)).

## Usage

``` r
dsr_detecter(
  sigma_geo,
  reference = NULL,
  vesselness = NULL,
  sigma_surf = NULL,
  seuil = 0.6,
  seuil_vessel = 0.3,
  buffer_ref = 15,
  long_min = 30,
  ratio_min = 3,
  pas_bin = 5,
  methode = c("auto", "agent", "squelette", "vecnet", "acp"),
  poids = c(geo = 1, surf = 2, vessel = 1),
  regime = c("complet", "corridor"),
  emprise = NULL,
  elaguer = 5,
  lissage = c("savitzky-golay", "bezier", "aucun"),
  lissage_par = NULL,
  raccorder = 0,
  simplifier = 1
)
```

## Arguments

- sigma_geo:

  Conductivite geomorphologique
  ([`dsr_conductivite()`](https://pobsteta.github.io/dessertR/reference/dsr_conductivite.md)),
  `SpatRaster`.

- reference:

  `sf`/`sfc` du reseau de reference (BD TOPO) a exclure ; `NULL` pour ne
  rien exclure.

- vesselness:

  Raster de linearite
  ([`dsr_layers_dtm()`](https://pobsteta.github.io/dessertR/reference/dsr_layers_dtm.md))
  pour privilegier les structures lineaires ; `NULL` pour l'ignorer.

- sigma_surf:

  Conductivite de surface
  ([`dsr_sigma_surf()`](https://pobsteta.github.io/dessertR/reference/dsr_sigma_surf.md))
  — le canal qui distingue une piste ouverte d'une trace fossile ;
  `NULL` pour s'en passer.

- seuil:

  Seuil de binarisation de `p_desserte`. Defaut 0.6.

- seuil_vessel:

  Debut de la rampe d'appartenance sur `vesselness`. Defaut 0.3.

- buffer_ref:

  Demi-largeur (m) du corridor de reference a exclure. Defaut 15.

- long_min:

  Longueur minimale (m) d'un axe detecte. Defaut 30.

- ratio_min:

  Rapport d'allongement minimal d'une composante (methode `"acp"`
  seulement). Defaut 3.

- pas_bin:

  Pas d'echantillonnage (m) le long de l'axe principal (methode `"acp"`
  seulement). Defaut 5.

- methode:

  Vectoriseur : `"auto"`, `"agent"`, `"squelette"` ou `"acp"` (voir
  [`dsr_vectoriser()`](https://pobsteta.github.io/dessertR/reference/dsr_vectoriser.md)).

- poids:

  Poids des canaux dans l'indice ; voir
  [`dsr_indice_detection()`](https://pobsteta.github.io/dessertR/reference/dsr_indice_detection.md).

- regime:

  `"complet"` (toute la grille) ou `"corridor"` (restreint a `emprise`).

- emprise:

  `sf`/`sfc` polygonal ; requis en regime `"corridor"`, ignore en regime
  `"complet"`.

- elaguer:

  Longueur (m) en deca de laquelle une barbule ou un micro-lien de
  carrefour est retire du graphe du squelette ; voir
  [`dsr_vectoriser()`](https://pobsteta.github.io/dessertR/reference/dsr_vectoriser.md).
  Defaut 5.

- lissage:

  Lissage de la centre-ligne ; voir
  [`dsr_vectoriser()`](https://pobsteta.github.io/dessertR/reference/dsr_vectoriser.md).
  Defaut `"savitzky-golay"`.

- lissage_par:

  Parametre du lissage ; voir
  [`dsr_vectoriser()`](https://pobsteta.github.io/dessertR/reference/dsr_vectoriser.md).

- raccorder:

  Distance (m) de raccordement des trouees ; voir
  [`dsr_vectoriser()`](https://pobsteta.github.io/dessertR/reference/dsr_vectoriser.md).
  `0` (defaut) pour ne rien raccorder.

- simplifier:

  Tolerance (m) de simplification des lignes ; `0` pour ne pas
  simplifier. Defaut 1.

## Value

Un `sf` `LINESTRING` des axes detectes (colonnes `id`, `longueur`), ou
un `sf` vide si aucun.

## Details

**Regimes.** `"complet"` balaie toute la grille (moins le corridor de
reference) : c'est le regime de la v2, celui qui trouve ce que la BD
TOPO ignore. `"corridor"` restreint a une `emprise` fournie, utile pour
instruire un secteur sans payer le cout d'une dalle entiere.

**Le nuage est ici decisif.** Sans `sigma_surf`, la detection repose sur
la seule geomorphologie et rallume toutes les traces fossiles (chemins
creux, limites parcellaires, anciennes RF) — le risque n.1 du BRIEF.
Fournir `sigma_surf` fait la difference entre une piste reellement
ouverte et une cicatrice du terrain.

Le resultat est une collection d'aretes coherentes (les embranchements
partagent leurs extremites) : la passer a
[`dsr_reseau()`](https://pobsteta.github.io/dessertR/reference/dsr_reseau.md)
donne directement un graphe valide.

## See also

[`dsr_indice_detection()`](https://pobsteta.github.io/dessertR/reference/dsr_indice_detection.md),
[`dsr_vectoriser()`](https://pobsteta.github.io/dessertR/reference/dsr_vectoriser.md),
[`dsr_reseau()`](https://pobsteta.github.io/dessertR/reference/dsr_reseau.md),
[`dsr_conductivite()`](https://pobsteta.github.io/dessertR/reference/dsr_conductivite.md),
[`dsr_repositionner()`](https://pobsteta.github.io/dessertR/reference/dsr_repositionner.md).
