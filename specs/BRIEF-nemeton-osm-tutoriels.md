# BRIEF `nemeton` — les tutoriels sont le dernier appel direct à `osmdata`

> **Statut** : ouvert, 2026-08-13. **Priorité basse**, périmètre minimal.
> **Amont** : `BRIEF-osm-overpass-unification.md` §5.4, et ADR-010 de `foretaccess`.
> **À traiter dans une session de dev dédiée sur `/home/pascal/dev/nemeton`**
> (un repo = une session).

## Où en est l'écosystème

L'unification des requêtes Overpass est livrée là où elle comptait :

| paquet | état |
|---|---|
| `foretaccess` | `osm_overpass()` exporté, client canonique (ADR-010) — §5.1 fait |
| `dessertR` | `dsr_osm()` bascule dessus, avec repli interne — §5.2 fait |
| `nemetonshiny` | passe par `foretaccess::acquire_desserte_osm()`, rien à changer |
| `nemeton` | **deux tutoriels appellent `osmdata` en direct** — ce brief |

Après ce lot, un seul chemin de code fait un appel réseau vers Overpass dans
l'écosystème **hors vos tutoriels**, qui sont explicitement dérogés par le brief
d'origine.

## Ce qui est demandé, et rien de plus

`inst/tutorials/03-terrain/03-terrain.Rmd` (densité de sentiers, indicateur S3)
et `04-ecological.Rmd` (landuse en repli d'OCS-GE) enchaînent
`opq() |> add_osm_feature() |> osmdata_sf()`. Ils tournent sous
`requireNamespace()` conditionnel avec `tryCatch` : **c'est acceptable pour un
tutoriel, et il ne faut pas les réécrire dans ce lot.**

**Action unique** : ajouter dans chaque chunk une note disant que le chemin de
production est `foretaccess::osm_overpass()` (ou
`foretaccess::acquire_desserte_osm()` pour la desserte), et que l'appel direct à
`osmdata` est pédagogique.

## Pourquoi la note n'est pas décorative

Un lecteur qui recopie le chunk hérite de trois défauts que le client canonique
corrige, et dont aucun ne se voit à l'exécution :

1. **Une instance saturée ne rend pas d'erreur, elle fait attendre.** `osmdata`
   boucle alors en backoff de 60 s **sans plafond** — 16 reprises consécutives
   mesurées, soit 16 minutes d'attente pure. `setTimeLimit()` n'y peut rien : il
   n'interrompt qu'aux points de contrôle R, jamais un socket bloqué dans du C.
2. **La rotation d'instances d'`osmdata` est inatteignable quand elle servirait**
   : `set_overpass_url()` appelle `overpass_status()`, donc *changer d'instance
   est lui-même un appel réseau*, et c'est la bascule qui échoue.
3. **Un refus se lit comme un vide.** Une instance bridée renvoie un XML **bien
   formé** de quelques centaines d'octets, **HTTP 200**, avec un élément
   `<remark>`. Lu naïvement, cela dit « aucune donnée ici ». C'est l'erreur qui a
   masqué l'absence de DFCI pendant une journée entière — et sur un indicateur
   comme S3, elle ne produit pas une erreur mais une **densité de sentiers nulle**
   parfaitement plausible.

Le troisième est le seul qui compte vraiment pour un tutoriel : les deux premiers
font perdre du temps, celui-ci fait publier un chiffre faux.

## Ce que ce brief ne demande pas

- Pas de dépendance nouvelle : `foretaccess` n'a pas à entrer dans le
  `DESCRIPTION` de `nemeton` pour une note de tutoriel.
- Pas de réécriture des chunks, ni de retrait d'`osmdata`.
- Pas de fonds de carte : `leaflet`/`maptiles` ne sont pas concernés.
- Pas d'extraits Geofabrik `.pbf` (§6 du brief d'origine) : c'est une spec
  dédiée, à instruire séparément si la cible devient le massif entier en batch.
