# Rapport de synthese d'un traitement

Assemble en un texte Markdown les metriques cles d'un traitement de
desserte (BRIEF section 3 : rapport) : geometrie mesuree, praticabilite,
etat, reseau. Chaque entree est optionnelle.

## Usage

``` r
dsr_rapport(
  mesure = NULL,
  praticabilite = NULL,
  etat = NULL,
  reseau = NULL,
  norme = NULL,
  fichier = NULL
)
```

## Arguments

- mesure:

  Sortie de
  [`dsr_measure()`](https://pobsteta.github.io/dessertR/reference/dsr_measure.md)
  (`$resume`), ou son `resume`.

- praticabilite:

  Sortie de
  [`dsr_trafficability()`](https://pobsteta.github.io/dessertR/reference/dsr_trafficability.md)
  (`$resume`).

- etat:

  Sortie de
  [`dsr_etat_trace()`](https://pobsteta.github.io/dessertR/reference/dsr_etat_trace.md)
  (`$resume`, `data.frame`).

- reseau:

  Sortie de
  [`dsr_reseau()`](https://pobsteta.github.io/dessertR/reference/dsr_reseau.md)
  (`$resume`).

- norme:

  Sortie de
  [`dsr_ecart_norme()`](https://pobsteta.github.io/dessertR/reference/dsr_ecart_norme.md)
  : l'ecart entre la largeur mesuree et la largeur normative de la fiche
  Certu. La section se lit dans **un seul sens** – la mesure informe sur
  ce que la norme suppose, jamais l'inverse (voir
  [`dsr_emprise_certu()`](https://pobsteta.github.io/dessertR/reference/dsr_emprise_certu.md)).

- fichier:

  Chemin d'un `.md` a ecrire ; `NULL` pour seulement renvoyer le texte.

## Value

Le texte Markdown (caractere), invisiblement si `fichier` est fourni.

## See also

[`dsr_export_gpkg()`](https://pobsteta.github.io/dessertR/reference/dsr_export_gpkg.md),
[`dsr_ecart_norme()`](https://pobsteta.github.io/dessertR/reference/dsr_ecart_norme.md).
