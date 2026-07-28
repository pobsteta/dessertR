# Ecrire un style QGIS categorise (.qml)

Genere un fichier de style QGIS `.qml` a rendu categorise sur un champ,
avec une couleur par valeur (BRIEF section 3 : styles QGIS). Compatible
QGIS 3.x (format `prop`). Un fichier `.qml` place a cote d'une couche
est charge automatiquement par QGIS.

## Usage

``` r
dsr_qml_categorise(
  fichier,
  champ,
  valeurs,
  couleurs,
  labels = NULL,
  geometrie = c("line", "point", "fill")
)
```

## Arguments

- fichier:

  Chemin du `.qml` a ecrire.

- champ:

  Nom du champ portant les categories.

- valeurs:

  Valeurs des categories.

- couleurs:

  Couleurs `"r,g,b"` (une par valeur).

- labels:

  Libelles affiches ; defaut = `valeurs`.

- geometrie:

  `"line"` (defaut), `"point"` ou `"fill"`.

## Value

Le chemin du `.qml`, invisiblement.

## See also

[`dsr_export_gpkg()`](https://pobsteta.github.io/dessertR/reference/dsr_export_gpkg.md).
