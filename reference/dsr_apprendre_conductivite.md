# Ajuster une conductivite apprise

Ajuste sur un echantillon
([`dsr_echantillon()`](https://pobsteta.github.io/dessertR/reference/dsr_echantillon.md))
le modele qui remplace la combinaison parametrique de
[`dsr_conductivite()`](https://pobsteta.github.io/dessertR/reference/dsr_conductivite.md)
quand `method = "model"` (BRIEF sections 3.4 et 5, lot 8).

## Usage

``` r
dsr_apprendre_conductivite(
  echantillon,
  methode = c("glm", "ranger"),
  k = 5,
  ...
)
```

## Arguments

- echantillon:

  `data.frame` issu de
  [`dsr_echantillon()`](https://pobsteta.github.io/dessertR/reference/dsr_echantillon.md)
  : colonne `y` (0/1) et une colonne par canal.

- methode:

  `"glm"` (regression logistique, defaut) ou `"ranger"` (foret aleatoire
  probabiliste).

- k:

  Nombre de plis de la validation croisee stratifiee. `NULL` ou `< 2`
  pour la sauter. Defaut 5.

- ...:

  Arguments supplementaires transmis a
  [`ranger::ranger()`](http://imbs-hl.github.io/ranger/reference/ranger.md).

## Value

Un objet de classe `dsr_modele_conductivite` : liste `fit`, `methode`,
`canaux`, `auc_vc` (validation croisee), `auc_app` (apprentissage), `n`,
`prevalence`, `k`.

## Details

Deux moteurs. `"glm"` (defaut) est une regression logistique : sans
dependance, ses coefficients se lisent, et sur une dizaine de canaux
deja concus pour la tache elle est difficile a battre avec quelques
milliers de cellules. `"ranger"` (paquet en Suggests) est une foret
aleatoire en mode probabiliste, utile quand le jeu grossit et que les
interactions comptent.

**L'AUC rapportee est celle de la validation croisee stratifiee** a `k`
plis, pas celle de l'apprentissage : c'est la seule qui dise quelque
chose de la generalisation. L'ecart entre `auc_vc` et `auc_app` mesure
le surapprentissage. Un modele ajuste sur un massif n'est pas presume
valide sur un autre — le revalider avant de l'y appliquer (BRIEF section
4).

## See also

[`dsr_echantillon()`](https://pobsteta.github.io/dessertR/reference/dsr_echantillon.md),
[`predict.dsr_modele_conductivite()`](https://pobsteta.github.io/dessertR/reference/predict.dsr_modele_conductivite.md),
[`dsr_conductivite()`](https://pobsteta.github.io/dessertR/reference/dsr_conductivite.md).
