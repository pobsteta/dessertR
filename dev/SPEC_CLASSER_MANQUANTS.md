# Spécification — les deux classes que `dsr_classer()` ne pose pas

Statut : **spécification, v0.1** — non implémentée, non arbitrée.
Fait suite à [`R/classer.R`](../R/classer.R), qui laisse délibérément deux classes hors de la
cascade automatique et le dit en tête de fichier.

---

## 0. Pourquoi elles sont dehors, et pourquoi c'est la bonne décision pour l'instant

`dsr_classer()` attribue six classes et refuse d'en poser deux :

| Classe | Ce qui manque |
|---|---|
| `pare_feu` | un critère de **position topographique** — le paquet ne calcule pas de ligne de crête |
| `place_depot` | un **tag OSM consensuel** — le fil OSM-fr ne l'aborde pas, et ce n'est pas un linéaire |

Les sortir en `indetermine` est préférable à les déclarer sur un seuil inventé : une largeur de
8 m ne fait pas un pare-feu, et un tag improvisé pollue une base collaborative durablement.

## 1. `pare_feu` — le critère de crête

### Ce qui le distingue vraiment

Un pare-feu n'est pas une desserte large. Il se reconnaît à trois traits, dont un seul manque au
paquet :

1. **il suit une ligne de crête** ou une limite topographique franche — c'est sa raison d'être,
   couper la propagation ; **manquant** ;
2. il est **large et végétalisé ras** : plage minérale absente (NDVI intermédiaire, ni chaussée ni
   couvert) — `dsr_largeur_ndvi()` le donne déjà ;
3. il est **continu sur une grande longueur** et ne dessert rien — la topologie de `dsr_reseau()`
   le donne déjà (composante, extrémités libres).

### Le critère à ajouter

Un indice de **position topographique** le long de l'axe : la station est-elle plus haute que son
voisinage latéral ? C'est le TPI (*Topographic Position Index*), différence entre l'altitude au
point et la moyenne dans un anneau de rayon `r`. Sur une crête, TPI > 0 franchement ; sur une
route en versant, TPI ≈ 0 ; en fond de vallon, TPI < 0.

Le paquet a déjà tout ce qu'il faut : `dsr_micro_relief()` calcule des différentiels d'altitude
par fenêtre, et `dsr_profils()` échantillonne le long d'un tracé.

```r
dsr_tpi(mnt, rayon_m = 50, rayon_min_m = NULL)   # SpatRaster, unités du MNT
```

Le rayon est le paramètre qui commande tout : à 10 m on mesure la banquette de la route
elle-même, à 200 m on mesure le massif. **50 m est un point de départ, pas une valeur calibrée** —
un banc sur un pare-feu connu est un préalable à toute publication du critère.

Puis, dans `dsr_classer()`, un critère `crete` : la médiane du TPI le long de l'axe dépasse un
seuil, et la part de stations à TPI positif est élevée. Il entre dans la cascade **avant** le
peigne (un pare-feu n'est pas un cloisonnement) et **après** la référence (s'il est porté par la
BD TOPO, c'est une desserte qui suit une crête, cas fréquent en montagne).

### Le piège

**Beaucoup de routes forestières suivent des crêtes** — c'est même une pratique de tracé, le
terrain y est plat en travers et le drainage naturel. Le TPI seul classerait ces routes en
pare-feu. Le critère n'est donc recevable qu'en **conjonction** avec l'absence de plage minérale :
crête **et** pas de chaussée. Sans NDVI, la classe ne doit pas être posée du tout.

C'est la même discipline que le reste du fichier : un critère isolé ne conclut pas.

### Balisage

`man_made=cutline` + `cutline=firebreak`, déjà cité dans le fil OSM-fr comme sous-type reconnu.

## 2. `place_depot` — un objet, pas une classe

`dsr_places()` rend déjà les élargissements, en **points**. Le problème n'est pas de les détecter
mais de les baliser : le fil OSM-fr n'en parle pas, et rien dans les usages consultés ne fait
consensus. Trois pistes, à instruire **au wiki OSM avant toute implémentation** :

- `landuse=forestry` + un sous-tag `forestry=*` — la proposition « Forestry » existe, son adoption
  reste à vérifier ;
- `man_made=storage_yard` — générique, non forestier ;
- ne rien poser et se contenter d'une couche interne exportée au GeoPackage.

**Recommandation : la troisième**, jusqu'à ce qu'un tag soit établi. Une place de dépôt est une
information de gestion utile au gestionnaire ; elle n'a pas à devenir une contribution OSM
douteuse. `dsr_export_gpkg()` la transporte déjà.

Point secondaire, mais réel : une place de dépôt est une **surface**, pas un point. La rendre en
polygone — emprise de l'élargissement mesurée par `dsr_measure()` — serait plus juste et coûte peu
puisque les largeurs par station sont déjà là.

## 3. Estimation

| Étape | Charge |
|---|---|
| `dsr_tpi()` + tests sur relief de synthèse (crête, versant, vallon) | 2 j |
| Critère `crete` dans la cascade + conjonction avec `minerale` | 1 j |
| Banc sur un pare-feu réel — préalable à toute publication du seuil | 2 j |
| Place de dépôt en polygone | 1 j |
| Arbitrage du tag OSM (veille wiki, éventuellement fil OSM-fr) | — |

**≈ 6 jours** pour le pare-feu, dont deux qui ne sont pas du code mais de la validation.
La place de dépôt tient en un jour si l'on renonce au tag, ce qui est la recommandation.

## 4. Ce qui ne doit pas arriver

Poser ces classes sans leur critère. `CLASSE_CONF` chiffre déjà la part de critères renseignés :
une classe posée sur un seuil de largeur ferait monter la confiance sans que rien ne l'appuie,
ce qui est pire que l'`indetermine` actuel — lequel est lisible, et se corrige à la main.
