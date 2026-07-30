# Vectoriser une carte de desserte

Passe d'une carte de probabilite
([`dsr_indice_detection()`](https://pobsteta.github.io/dessertR/reference/dsr_indice_detection.md),
ou toute conductivite) a une collection de `LINESTRING`. Le vectoriseur
est **enfichable** : la porte reste ouverte a un backend appris sans
changer l'interface.

## Usage

``` r
dsr_vectoriser(
  p,
  seuil = 0.6,
  methode = c("auto", "agent", "squelette", "vecnet", "acp"),
  long_min = 30,
  ratio_min = 3,
  pas_bin = 5,
  elaguer = 5,
  lissage = c("savitzky-golay", "bezier", "aucun"),
  lissage_par = NULL,
  raccorder = 0,
  simplifier = 1,
  reference = NULL,
  ...
)
```

## Arguments

- p:

  `SpatRaster` mono-couche de probabilite / conductivite.

- seuil:

  Seuil de binarisation pour `"squelette"` et `"acp"`. Defaut 0.6.

- methode:

  `"auto"`, `"agent"`, `"squelette"` ou `"acp"`. `"vecnet"` est accepte
  comme synonyme de `"agent"`.

- long_min:

  Longueur minimale (m) d'un axe retenu. Defaut 30.

- ratio_min:

  Rapport d'allongement minimal d'une composante (methode `"acp"`
  seulement). Defaut 3.

- pas_bin:

  Pas d'echantillonnage (m) le long de l'axe principal (methode `"acp"`
  seulement). Defaut 5.

- elaguer:

  Longueur (m) en deca de laquelle une barbule ou un micro-lien de
  carrefour est retire du graphe du squelette ; `0` ou `NULL` pour ne
  rien nettoyer. Defaut 5. Methode `"squelette"` seulement.

- lissage:

  Lissage de la centre-ligne, methode `"squelette"` seulement :
  `"savitzky-golay"` (defaut), `"bezier"` ou `"aucun"`.

- lissage_par:

  Parametre du lissage, `NULL` pour le defaut de la methode :
  demi-largeur exprimee en metres pour `"savitzky-golay"` (defaut 7),
  tolerance d'ajustement en metres pour `"bezier"` (defaut : la
  resolution de `p`).

- raccorder:

  Distance (m) en deca de laquelle deux extremites de composantes
  distinctes et **alignees** sont reliees, pour franchir une trouee de
  conductivite. `0` (defaut) pour ne rien raccorder.

- simplifier:

  Tolerance (m) de simplification Douglas-Peucker des lignes produites ;
  `0` ou `NULL` pour ne pas simplifier. Defaut 1.

- reference:

  `sf`/`sfc` du reseau deja connu. Pour `"agent"`, il sert deux fois :
  ses extremites amorcent l'exploration, et il est infranchissable
  (l'agent s'y arrete au lieu de le revectoriser). Ignore par les autres
  methodes.

- ...:

  Arguments supplementaires transmis a
  [`dsr_conduire()`](https://pobsteta.github.io/dessertR/reference/dsr_conduire.md).

## Value

Un `sf` `LINESTRING` (colonnes `id`, `longueur`), vide si rien n'est
retenu. L'attribut `"methode"` porte le vectoriseur reellement employe.

## Details

Trois methodes :

- `"squelette"` — binarisation a `seuil`, amincissement de
  **Zhang-Suen**, puis tracage du graphe du squelette : chaque chaine
  entre deux noeuds (extremite ou embranchement) devient une arete.
  Deterministe, sans dependance, et surtout **il conserve les
  embranchements** : un peigne de cloisonnements sort en autant de
  lignes, la ou `"acp"` l'ecrase en une. Le graphe est ensuite nettoye
  (`elaguer`) : contraction des grappes de jonction, elagage des
  barbules, fusion des chaines. Sans cette etape, les bavures de bord
  d'une emprise binarisee reelle hachent une piste de 190 m en plusieurs
  dizaines de troncons dont aucun n'atteint `long_min`.

- `"agent"` (defaut) — **agent conducteur**
  ([`dsr_conduire()`](https://pobsteta.github.io/dessertR/reference/dsr_conduire.md))
  : la route est vectorisee en la parcourant, l'agent avancant par pas
  vers la direction la moins couteuse de son champ de vision.
  Reimplementation terra/sf de l'algorithme de vecnet (Roussel *et
  al.* 2023) sur le noyau Rust du paquet. Deux atouts sur le squelette :
  il **franchit les trouees** de detection, et il rend des lignes lisses
  sans passer par un escalier de pixels. Il exige en revanche des
  **amorces**
  ([`dsr_amorces()`](https://pobsteta.github.io/dessertR/reference/dsr_amorces.md))
  : fournir `reference` est de loin le meilleur amorcage, les extremites
  du reseau connu pointant la ou commence la desserte qui manque.

- `"acp"` — methode historique : composantes connexes, puis centre-ligne
  par analyse en composantes principales. Rapide, mais une composante
  donne une seule ligne ; ne convient qu'aux axes isoles et bien
  allonges.

**Lissage de la centre-ligne.** Le squelette d'une emprise rasterisee
est un escalier : chaque virage y est un ressaut de 0 ou 45 degres. Ce
n'est pas cosmetique —
[`dsr_measure()`](https://pobsteta.github.io/dessertR/reference/dsr_measure.md)
en tire `RAYON_COURBURE` et `SINUOSITE`, et
[`dsr_trafficability()`](https://pobsteta.github.io/dessertR/reference/dsr_trafficability.md)
en deduit l'aptitude grumier. `lissage` corrige cela :

- `"savitzky-golay"` (defaut) — ajustement polynomial local sur `x(t)`
  et `y(t)` (Wang *et al.* 2025). Filtre local : conserve la longueur et
  ne rabote pas les virages francs.

- `"bezier"` — ajustement de Bezier cubiques par morceaux aux moindres
  carres, avec decoupe recursive sur l'erreur maximale, puis
  reechantillonnage. C'est la representation de DOGE (Sun *et al.* 2025)
  ramenee a un ajustement direct, sans optimisation differentiable. Elle
  donne une courbe **C1 par morceaux**, analytiquement derivable, dont
  le pas de reechantillonnage se choisit librement. Deux reserves
  mesurees sur un arc de reference : elle est moins fidele que
  Savitzky-Golay (ecart median a la courbe vraie 0,39 m contre 0,13 m),
  et sa compacite reside dans les points de controle — le `LINESTRING`
  rendu etant reechantillonne, il n'a pas moins de sommets que
  l'escalier d'origine. A choisir pour la continuite, pas pour la
  precision.

- `"aucun"` — l'escalier brut.

Dans les deux cas **les extremites sont figees** : elles portent la
topologie que
[`dsr_reseau()`](https://pobsteta.github.io/dessertR/reference/dsr_reseau.md)
reconstruit ensuite.

**Raccordement des trouees.** `raccorder` relie deux extremites de
composantes distinctes separees par une trouee de conductivite (couvert
dense, franchissement). Au critere de distance de Wang *et al.* on
ajoute un critere d'alignement, faute de quoi une piste serait soudee au
cloisonnement voisin qu'elle croise sans le rejoindre. Cette etape
**invente de la geometrie la ou la donnee ne montre rien** : elle est
desactivee par defaut.

`"auto"` prend `"agent"`. Si l'agent echoue – ou si aucune amorce n'est
exploitable, faute de reference et de route touchant le bord de
l'emprise – le repli sur le squelette est signale. Demande
explicitement, son echec est une erreur et l'absence d'amorce rend un
resultat vide.

`"vecnet"` reste accepte et vaut `"agent"` : le paquet externe du meme
nom a ete remplace par une implementation native, sans dependance.

Le cout de l'amincissement croit avec la demi-largeur des taches : sur
une carte tres bruitee, relever `seuil` avant d'elargir la grille.

## References

Roussel, J.-R., Bourdon, J.-F., Morley, I. D., Coops, N. C., & Achim, A.
(2023). Vectorial and topologically valid segmentation of forestry road
networks from ALS data. *IJAEOG*, 118, 103267.
[doi:10.1016/j.jag.2023.103267](https://doi.org/10.1016/j.jag.2023.103267)

Wang, X., Ibrahim, M., Mansoor, A., Tareque, H., & Mian, A. (2025).
Automated Road Extraction and Centreline Fitting in LiDAR Point Clouds.
*arXiv:2502.07486*.

Sun, J., Lu, J., Yin, J., Xu, Y., Li, Y., & Guo, Y. (2025). DOGE:
Differentiable Bezier Graph Optimization for Road Network Extraction.
*arXiv:2511.19850*.

## See also

[`dsr_indice_detection()`](https://pobsteta.github.io/dessertR/reference/dsr_indice_detection.md),
[`dsr_detecter()`](https://pobsteta.github.io/dessertR/reference/dsr_detecter.md),
[`dsr_reseau()`](https://pobsteta.github.io/dessertR/reference/dsr_reseau.md).
