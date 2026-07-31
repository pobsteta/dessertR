# Specifications d'appartenance par defaut du canal geomorphologique

Jeu de regles *provisoire* reliant les couches de
[`dsr_layers_dtm()`](https://pobsteta.github.io/dessertR/reference/dsr_layers_dtm.md)
a leur appartenance a « empreinte de route » : une route est un lineaire
en creux (`vesselness` haute), aux bords concaves (`openness_neg` haute)
et **plus rugueuse que son environnement** (`rugosite` haute). Les
bornes sont laissees a `NULL` (derivees des quantiles) tant qu'un jeu de
validation ne permet pas de les caler (BRIEF section 4). A adapter
librement.

## Usage

``` r
dsr_specs_geomorpho()
```

## Value

Une liste nommee par nom de base de canal ; chaque element est une liste
`type` / `a` / `b` / `poids` pour
[`dsr_conductivite()`](https://pobsteta.github.io/dessertR/reference/dsr_conductivite.md).

## Details

**`rugosite` est croissante, ce qui surprend.** L'intuition dit qu'une
route est lisse. A 50 cm de resolution, c'est faux : une piste empierree
a ornieres est plus rugueuse qu'un versant forestier localement plan, et
le profil en travers – fosse, talus, devers – domine dans une fenetre de
quelques cellules. Le canal etait declare `decroissante` jusqu'ici, donc
utilise a l'envers.

Mesure a l'appui
([`dsr_calibrer_specs()`](https://pobsteta.github.io/dessertR/reference/dsr_calibrer_specs.md),
fenetres de 1,5 km2) : `rugosite` est le canal le plus discriminant des
sept, `sens = +1` sur les deux massifs (AUC 0,759 et 0,744 ; 0,753 en
conjoint), et l'AUC de `sigma_geo` gagne **+0,175 sur chacun** – 0,530
-\> 0,705 sur wsfi, 0,479 -\> 0,654 sur ltcp. Le defaut precedent
passait donc **sous le hasard** sur un des deux massifs.

Les autres signes sont inchangees. `pente` et `slrm` s'inversent d'un
massif a l'autre (`stable = FALSE`) et n'ont rien a faire dans un defaut
; `openness_neg` mesure `-1` sur les deux massifs mais `+1` sur une
dalle Lozere recouvrant wsfi, avec une AUC proche du hasard (0,527) la
ou le signe se decide – pas de quoi trancher.

Ces regles restent un **point de depart**. Le chemin recommande est
[`dsr_calibrer_specs()`](https://pobsteta.github.io/dessertR/reference/dsr_calibrer_specs.md),
qui mesure les signes, les poids et les bornes sur vos donnees plutot
que de les supposer.

## See also

[`dsr_conductivite()`](https://pobsteta.github.io/dessertR/reference/dsr_conductivite.md),
[`dsr_appartenance()`](https://pobsteta.github.io/dessertR/reference/dsr_appartenance.md).
