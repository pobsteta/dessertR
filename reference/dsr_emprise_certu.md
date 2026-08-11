# Emprise routiere normative (methode Certu, fiche 1.7)

Estime la largeur de chaussee et l'emprise d'un troncon a partir des
seuls attributs de la BD TOPO, par les largeurs standard de la fiche
Certu 1.7 (2013). C'est un **calcul normatif**, pas une mesure : il dit
ce que la reglementation suppose, pas ce que le terrain porte.

## Usage

``` r
dsr_emprise_certu(
  troncons,
  schema = c("auto", "v2", "v3"),
  champs = NULL,
  nature_map = NULL,
  emprise = FALSE
)
```

## Arguments

- troncons:

  `sf` des troncons de route (BD TOPO).

- schema:

  `"auto"` (defaut), `"v2"` ou `"v3"`.

- champs:

  Liste nommee pour forcer les noms de colonnes (`cl_admin`, `nature`,
  `franchissement`, `nb_voies`, `pos_sol`). Elle **complete** la
  detection automatique : les champs non cites restent detectes. `NULL`
  (defaut) pour s'en remettre entierement a la detection.

- nature_map:

  Vecteur nomme de correspondance des valeurs de nature vers celles de
  la fiche ; `NULL` pour le defaut du schema detecte.

- emprise:

  `TRUE` pour renvoyer en plus les polygones d'emprise (tampon de
  `largeur_buffer` autour de l'axe). Defaut `FALSE`.

## Value

Le `sf` d'entree, augmente de `LARGEUR_CHAUSSEE_CERTU`,
`LARGEUR_EMPRISE_CERTU` (= 2 x tampon), `BANDE_ARRET_CERTU`,
`BERME_CERTU`. Les troncons non apparies recoivent `NA`. L'attribut
`"certu"` porte le schema retenu, les champs utilises et les
combinaisons non appariees. Avec `emprise = TRUE`, une liste `troncons`
/ `emprise`.

## Details

**Ce n'est pas une reference pour calibrer une mesure.** Pour toute la
desserte forestiere `Chemin`, `Route empierree`, `Sentier` la fiche rend
une **constante de 2 m**, identique quelle que soit la route. Caler
[`dsr_measure()`](https://pobsteta.github.io/dessertR/reference/dsr_measure.md)
dessus forcerait la mesure a 2 m partout, c'est-a-dire detruirait le
signal que le paquet existe pour produire. La fiche pose elle-meme ses
limites : elle a ecarte le champ de largeur de la BD TOPO ( pas
renseigne de facon homogene ), ses valeurs ne delimitent pas avec une
precision decimetrique , et la methode surestime sur la voirie locale.

Son interet est ailleurs :

- **le vocabulaire** la fiche donne la decomposition normative du profil
  en travers, et permet de situer ce que mesure `LARGEUR_ROULABLE` : la
  **chaussee**, comparable a `LARGEUR_CHAUSSEE_CERTU`, et non l'emprise,
  qui ajoute bande derasee et berme ;

- **l'ecart a la norme** c'est la lecture utile. dessertR mesure ce que
  la fiche ne peut que supposer : cette piste fait 3,2 m la ou la norme
  en suppose 2 informe le gestionnaire, dans ce sens-la et pas
  l'inverse.

**Schemas.** La fiche est ecrite pour la BD TOPO v2 (champs `cl_admin`,
`nature`, `franchisst`, `nb_voies`). En v3 les noms different et le
franchissement se deduit de `pos_sol` (negatif : tunnel, positif :
pont). Les correspondances de valeurs sont **deduites et non
officielles** : la sortie liste les combinaisons non appariees plutot
que de leur affecter un defaut silencieux.

## References

Certu, CETE Nord-Picardie et Mediterranee (2013). *Mesure de la
consommation d'espace : methodes et indicateurs*, fiche 1.7, Surfaces
occupees par les infrastructures routieres .

## See also

[`dsr_measure()`](https://pobsteta.github.io/dessertR/reference/dsr_measure.md),
[`dsr_calibrer_largeur()`](https://pobsteta.github.io/dessertR/reference/dsr_calibrer_largeur.md).
