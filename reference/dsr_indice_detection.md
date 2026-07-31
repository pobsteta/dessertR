# Indice de detection de desserte hors reference

Fusionne les signaux disponibles en une carte de probabilite
`p_desserte` dans `[0, 1]`, **hors du corridor du reseau de reference**
(BRIEF section 3.9). C'est l'entree de
[`dsr_vectoriser()`](https://pobsteta.github.io/dessertR/reference/dsr_vectoriser.md).

## Usage

``` r
dsr_indice_detection(
  sigma_geo,
  sigma_surf = NULL,
  vesselness = NULL,
  poids = c(geo = 1, surf = 0.5, vessel = 1),
  seuil_vessel = 0.3,
  reference = NULL,
  buffer_ref = 15,
  emprise = NULL
)
```

## Arguments

- sigma_geo:

  Conductivite geomorphologique
  ([`dsr_conductivite()`](https://pobsteta.github.io/dessertR/reference/dsr_conductivite.md)),
  `SpatRaster`.

- sigma_surf:

  Conductivite de surface
  ([`dsr_sigma_surf()`](https://pobsteta.github.io/dessertR/reference/dsr_sigma_surf.md))
  ; `NULL` pour se passer du canal nuage (detection nettement moins
  sure).

- vesselness:

  Raster de linearite
  ([`dsr_layers_dtm()`](https://pobsteta.github.io/dessertR/reference/dsr_layers_dtm.md))
  ; `NULL` pour l'ignorer.

- poids:

  Vecteur nomme des poids `geo`, `surf` et `vessel`. Defaut
  `c(geo = 1, surf = 0.5, vessel = 1)` (voir Details : ce poids est
  mesure, pas suppose). Un poids nul ou un canal absent retire
  simplement le terme.

- seuil_vessel:

  Debut de la rampe d'appartenance sur `vesselness`. Defaut 0.3.

- reference:

  `sf`/`sfc` du reseau de reference (BD TOPO) a exclure ; `NULL` pour ne
  rien exclure.

- buffer_ref:

  Demi-largeur (m) du corridor de reference a exclure. Defaut 15.

- emprise:

  `sf`/`sfc` polygonal restreignant la zone balayee (regime `corridor`)
  ; `NULL` pour balayer toute la grille (regime `complet`).

## Value

Un `SpatRaster` mono-couche `p_desserte`, `NA` hors emprise et dans le
corridor de reference.

## Details

La fusion est une **moyenne geometrique ponderee**, comme
[`dsr_conductivite()`](https://pobsteta.github.io/dessertR/reference/dsr_conductivite.md).
Le canal de surface entre avec un poids de **0,5**, soit la moitie du
canal geomorphologique. Ce chiffre est mesure, et il contredit
l'intuition qui presidait au reglage precedent (`surf = 2`).

**Ce que dit la mesure.** L'AUC route / hors route de l'indice, sur deux
massifs Lidar HD et 15 tirages par point (`dev/06_calibrer_surface.R`) :

|                   |           |           |
|-------------------|-----------|-----------|
| poids `surf`      | wsfi      | ltcp      |
| 0 (canal retire)  | 0,715     | 0,667     |
| 0,25              | 0,734     | 0,682     |
| **0,5**           | **0,739** | **0,684** |
| 1                 | 0,727     | 0,679     |
| 2 (ancien defaut) | 0,697     | 0,666     |

L'ecart-type du tirage est de 0,006. Les deux massifs placent leur
maximum au meme endroit, et l'ancien defaut etait **la pire valeur
testee – moins bonne que retirer le canal purement et simplement**. A
0,5 le canal apporte en revanche un gain reel : +0,024 (4 ecarts-types)
et +0,017 (2,8).

**Pourquoi l'intuition etait fausse.** Le raisonnement d'origine (BRIEF
section 3.9) etait qu'une piste se lit d'abord dans la discontinuite du
sous-etage. Mesure canal par canal, `densite_sousetage` ne discrimine
pas la presence d'une route : AUC 0,535 et 0,521, soit le hasard. Ce
n'est pas une defaillance du canal mais un malentendu sur la question
qu'on lui pose – il mesure un **etat** (emprise degagee ou recolonisee),
et une route recolonisee reste une route. Il garde donc toute sa valeur
dans
[`dsr_etat()`](https://pobsteta.github.io/dessertR/reference/dsr_etat.md),
ou c'est sa divergence avec `sigma_geo` qui parle, et n'en a guere pour
localiser.

Le canal de surface le plus discriminant se trouve etre `h_couvert` (AUC
0,660 sur ltcp), qui marque les routes par une vegetation haute plus
basse : il detecte l'ouverture de la canopee. Utile a faible poids, mais
c'est aussi ce qui interdit de le laisser dominer – une trouee sans
route (coupe rase, ligne electrique) l'allume tout autant, et c'est
precisement le faux positif que la table de divergence du BRIEF section
3.4 cherche a ecarter.

`vesselness` n'entre pas en dur mais via une rampe croissante a partir
de `seuil_vessel`
([`dsr_appartenance()`](https://pobsteta.github.io/dessertR/reference/dsr_appartenance.md)),
pour ne pas annuler brutalement une cellule par ailleurs convaincante.

## See also

[`dsr_vectoriser()`](https://pobsteta.github.io/dessertR/reference/dsr_vectoriser.md),
[`dsr_detecter()`](https://pobsteta.github.io/dessertR/reference/dsr_detecter.md),
[`dsr_conductivite()`](https://pobsteta.github.io/dessertR/reference/dsr_conductivite.md).

## Examples

``` r
# \donttest{
sg <- terra::rast(
  nrows = 40, ncols = 40, xmin = 0, xmax = 40, ymin = 0, ymax = 40,
  crs = "EPSG:2154"
)
terra::values(sg) <- 0.2
p <- dsr_indice_detection(sg)
# }
```
