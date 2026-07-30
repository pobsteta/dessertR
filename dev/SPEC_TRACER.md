# Spécification — `dsr_tracer()`, conception de desserte neuve

**Équivalent dessertR de SylvaRoaD** (SylvaLab / ONF Pôle RDI Chambéry, Sylvain Dupire 2021 ; portage QGIS `github.com/Tijjat/SylvaRoad_qgis_plugin`, GPL-3.0)

Statut : spécification, **v0.1** — non implémentée, non arbitrée dans la roadmap du [BRIEF](BRIEF.md).
Source analysée : `functions_np.py` (664 l.), `functions.py` (403 l.) du portage QGIS.

---

## 0. Pourquoi ce n'est pas `dsr_pathfinder()` avec d'autres paramètres

C'est l'arbitrage central, et il faut le poser avant tout le reste.

`dsr_pathfinder()` et SylvaRoaD partagent la machinerie — un plus court chemin sur
grille. Ils ne répondent pas à la même question :

| | `dsr_pathfinder()` | SylvaRoaD |
|---|---|---|
| Question | **Où la route est-elle ?** | **Où la route pourrait-elle être ?** |
| Coût | `1/σ_geo` — signature géomorphologique d'une plateforme existante | Distance + pénalités de génie civil sur terrain vierge |
| Le MNT sert à | reconnaître une forme déjà creusée | vérifier qu'une forme est **constructible** |
| Optimum | le tracé le plus « route-like » | le tracé le moins coûteux à construire |
| État | markovien (position seule) | **path-dependent** (voir §2) |

Une route existante est un attracteur dans `σ_geo` ; un tracé neuf n'existe dans
aucun raster. Les deux coûts sont disjoints, et un tracé neuf doit en plus
respecter des contraintes que `dsr_pathfinder()` ne sait pas exprimer parce
qu'elles portent sur **l'historique du chemin**, pas sur la cellule courante.

**Conséquence : nouvelle fonction, nouveau noyau Rust.** Réutiliser
`pathfinder_anisotrope` reviendrait à le dénaturer. En revanche `dsr_pente()`,
`dsr_corridor()`, `dsr_dalles_requises()` et la logique de lissage de `curves.R`
sont réutilisables tels quels.

---

## 1. Entrées

**Obligatoires**

- `mnt` : `SpatRaster` mono-couche. Résolution recommandée 1–5 m — au-delà de
  5 m la pente en travers devient un artefact, en deçà de 1 m le graphe explose
  (§4). La grille de référence dessertR est à 1 m : prévoir un agrégat.
- `points` : `sf` `POINT` ordonnés, portant `ID_TRONCON` et `ID_POINT`. Le
  premier et le dernier sont départ et arrivée ; les intermédiaires sont des
  **points de passage obligatoires**, traversés dans l'ordre (SylvaRoaD :
  `get_waypoints()` découpe en sous-segments enchaînés).

**Optionnelles**

- `obstacles` : `sf` (ou liste de `sf`) rasterisés en interdiction dure. À
  alimenter depuis la BD TOPO (bâti, hydrographie, ouvrages) et les couches
  réglementaires (réserve biologique, habitat d'espèce protégée, périmètre de
  captage).
- `foncier` : `sf` polygones ; hors emprise = interdit. SylvaRoaD code
  obstacle = 1 et foncier = 2 dans le même raster, ce qui permet de distinguer
  les deux causes d'échec dans le diagnostic — à conserver.

**Paramètres** (noms SylvaRoaD entre parenthèses, valeurs par défaut à calibrer
sur le jeu de validation avant publication — ne pas reprendre celles du plugin
sans vérification)

| Argument | (SylvaRoaD) | Rôle |
|---|---|---|
| `pente_long` | `min_slope`, `max_slope` | Intervalle de pente longitudinale admissible, %. Le **minimum** n'est pas cosmétique : une route à pente nulle ne se draine pas. |
| `pente_travers_max` | `trans_slope_all` | Dévers du terrain au-delà duquel la construction devient coûteuse. **Pas une interdiction** : voir `long_travers_max`. |
| `pente_travers_lacet` | `trans_slope_hairpin` | Dévers au-delà duquel un lacet est irréalisable. |
| `long_travers_max` | `Lmax_ab_sl` | Longueur cumulée tolérée au-dessus de `pente_travers_max`, m, **sur l'ensemble du tracé**. |
| `angle_lacet` | `angle_hairpin` | Angle au-delà duquel un virage est un lacet. |
| `angle_max` | `max_hairpin_angle` | Changement de direction absolu interdit. |
| `penalite_direction` | `penalty_xy` | Poids du changement de cap. |
| `penalite_pente` | `penalty_z` | Poids du changement de pente longitudinale. |
| `rayon` | `Radius` | Rayon de braquage ; conditionne l'espacement minimal entre lacets. |
| `voisinage` | `D_neighborhood` | Rayon de recherche autour d'un pixel, m. **Le paramètre le plus coûteux** (§4). |
| `ecart_z_max` | `max_diff_z` | Écart maximal entre le profil théorique et le terrain, m, sur un segment de longueur `voisinage`. |

---

## 2. Le cœur : un graphe à état étendu

C'est le point technique qui justifie un noyau dédié, et celui qu'il ne faut pas
rater.

### 2.1 Voisinage large, pas 8 ou 16 cellules

SylvaRoaD ne relie pas une cellule à ses 8 voisines mais à **toutes les cellules
dans un rayon `voisinage`** (`build_NeibTable()`). À 5 m de résolution et
`voisinage = 50 m`, cela fait ~316 voisins par cellule. La raison est
géométrique : une arête courte ne peut pas exprimer une pente longitudinale
faible sur terrain raide, et le tracé se met en escalier. Le voisinage 16 de
`dsr_pathfinder()` corrige le biais de métrication, pas celui-ci.

Les arêtes sont **pré-filtrées à la construction** : seules celles dont la pente
`Δz / D` tombe dans `pente_long` sont conservées. Sur terrain de montagne cela
élimine l'écrasante majorité des voisins — le graphe reste manipulable.

### 2.2 Chaque arête est un profil, pas un saut

Pour toute arête candidate, `check_profile()` parcourt la ligne de cellules
entre les deux extrémités et vérifie trois choses :

1. **aucun obstacle** sur le trajet ;
2. **`max |z_terrain − z_théorique| ≤ ecart_z_max × D / voisinage`** — la
   tolérance croît avec la longueur de l'arête, ce qui évite de favoriser
   mécaniquement les arêtes longues qui « sautent » un vallon ;
3. **accumulation** de la longueur en dévers excessif, dont le total sur le
   chemin doit rester `≤ long_travers_max`.

Le point 3 est le premier attribut d'état : il dépend de **tout le chemin
parcouru**, pas de l'arête.

### 2.3 L'état complet

Chaque nœud atteint porte (colonnes de `Best` chez SylvaRoaD) : coût, distance
cumulée, **pente courante**, **azimut courant**, parent, **distance au dernier
lacet**, **longueur cumulée en dévers excessif**, nombre de points du chemin,
distance au but, drapeau lacet.

Il en découle que le problème **n'est pas un Dijkstra** : le coût d'une arête
dépend de l'azimut et de la pente d'arrivée au nœud précédent. SylvaRoaD relaxe
en label-correcting avec réinsertion en frontière — l'optimalité n'est pas
garantie, la faisabilité l'est. **À documenter explicitement** : c'est une
heuristique, pas un optimum, et un utilisateur forestier doit le savoir.

### 2.4 Pénalités et lacets

```
coût(arête) = D
            + penalite_direction × (Δcap / angle_lacet)²
            + penalite_pente     × (Δpente / pente_max_change)²
            + longueur en dévers excessif ajoutée par l'arête
            + [lacet] 100 × (pente_locale / prop_max)²
```

Un virage au-delà de `angle_lacet` est un **lacet**, soumis à trois conditions
supplémentaires :

- la **pente locale** — proportion de cellules dans un rayon `1,25 × rayon`
  dont le dévers dépasse `pente_travers_lacet` (`calc_local_slope()`) — doit
  rester sous un seuil. Un lacet ne se pose pas sur un versant raide ;
- deux lacets doivent être séparés d'au moins `2 × 1,5 × rayon` ;
- un lacet peut aussi être détecté « en deux temps » : deux virages consécutifs
  séparés de moins de `2 × rayon` qui totalisent plus de `angle_lacet`.

### 2.5 Non-auto-intersection

Chaque nouvelle arête est testée contre **tous les segments déjà posés du même
chemin** (`get_intersect()`). Un tracé qui se recoupe est refusé. C'est une
contrainte globale sur le chemin, impossible à exprimer dans un Dijkstra
classique, et c'est le second argument décisif pour un noyau dédié.

### 2.6 Guidage vers le but

Une carte de distance géodésique au point d'arrivée (`calcul_distance_de_cout()`,
Dijkstra 8-connexe sur le masque franchissable) sert de minorant et de
diagnostic : si le départ est à distance infinie de l'arrivée, les obstacles
séparent les deux points et on le dit **avant** de lancer la recherche. En cas
d'échec, SylvaRoaD sauvegarde le chemin le plus proche du but — comportement à
reprendre, il est très utile pour comprendre *où* ça bloque.

---

## 3. Sorties

```r
list(
  trace          = sf LINESTRING,  # par ID_TRONCON, colonnes ci-dessous
  trace_lacets   = sf LINESTRING,  # lacets retracés en arcs de rayon `rayon`
  diagnostic     = data.frame,     # une ligne par tronçon
  pente_locale   = SpatRaster      # % de cellules en dévers > seuil lacet
)
```

Attributs par tronçon : `LONGUEUR_PLANI`, `LONGUEUR_LACETS_CORRIGES`,
`NB_LACETS`, `LONG_DEVERS_EXCESSIF`, `PENTE_LONG_MOY`, `PENTE_LONG_MAX`,
`STATUT` (`"complet"` / `"incomplet"`), `CAUSE_ECHEC`.

Le tracé brut sort en polyligne à sommets anguleux : les lacets doivent être
retracés en arcs (`trace_lace()` chez SylvaRoaD). **`curves.R` fait déjà ce
travail** (`.dsr_lisser_bezier()`, `.dsr_raccorder()`) — c'est la réutilisation
la plus directe du paquet existant.

---

## 4. Le risque qui peut tuer ce lot

**Le coût mémoire du graphe.** La table de voisinage est de taille
`n_cellules_franchissables × n_voisins`, matérialisée en dur. À 5 m et
`voisinage = 50 m`, un corridor de 4 km² = 160 000 cellules × 316 voisins ×
(2 + 4 + 2 octets) ≈ **400 Mo**, avant tout calcul. À 1 m, c'est 25× plus.

Trois parades, à trancher à l'implémentation :

1. **N'accepter que le régime corridor.** `dsr_corridor()` existe déjà et réduit
   l'emprise d'un ordre de grandeur. À imposer par défaut, pas à proposer.
2. **Ne pas matérialiser la table** : recalculer les voisins à la volée dans le
   noyau Rust. Coût CPU contre mémoire ; avec `dsr_ncores()` c'est probablement
   le bon échange.
3. **Filtrer avant de stocker** : le pré-filtre par pente longitudinale élimine
   déjà la majorité des voisins en montagne — ne stocker que les survivants, en
   liste d'adjacence compressée (CSR) plutôt qu'en matrice dense.

L'option 2 + 3 est la seule qui passe à 1 m. À vérifier par un banc avant
d'écrire le noyau, sur le modèle de `dev/02_bench_corridor.R`.

---

## 5. Ce que dessertR apporterait en plus

SylvaRoaD ne connaît que le MNT. dessertR dispose du nuage classé, donc :

- **Obstacles dérivés du MNH** plutôt que saisis à la main : peuplement à forte
  valeur, gros bois, zone de régénération.
- **`sigma_surf` comme modulateur de coût** : traverser une zone déjà tassée ou
  déjà roulable coûte moins cher à construire.
- **Réutilisation de la desserte détectée** par `dsr_detecter()` : un tracé neuf
  qui reprend une ancienne piste effacée est très en dessous du coût d'un tracé
  vierge. C'est le lien le plus intéressant entre les deux moitiés du paquet —
  et il n'existe dans aucun outil de conception actuel.

Ce dernier point est l'argument qui justifierait d'ouvrir cet axe : dessertR
sait où sont les anciennes emprises, SylvaRoaD non.

---

## 6. Estimation

| Étape | Charge |
|---|---|
| Noyau Rust (graphe CSR, état étendu, non-auto-intersection) | 3–4 sem |
| Couche R (entrées, obstacles, foncier, diagnostic) | 1,5 sem |
| Retraçage des lacets (adaptation `curves.R`) | 1 sem |
| Validation sur le bloc wsfi + confrontation à SylvaRoaD | 2 sem |

**≈ 8 semaines.** À comparer au lot L4 (pathfinder de repositionnement), qui en
a demandé 3–4 : le surcoût vient entièrement de l'état étendu et du voisinage
large.

---

## 7. Licence

Le dépôt SylvaRoaD porte un `LICENSE` **GPL-3.0** ; les en-têtes de source
disent « version 2 of the License, or (at your option) any later version ». La
distribution effective est donc GPL-3, et dessertR est en **GPL (>= 3)** —
compatible dans les deux lectures. Deux régimes possibles :

- **réimplémentation depuis la spec** (ce document) : aucune contrainte au-delà
  de la citation académique, et c'est le régime recommandé ;
- **portage de code** : GPL héritée, obligation de citer SylvaLab et l'ONF.

Dans les deux cas, citer explicitement Dupire / SylvaLab / ONF Pôle RDI Chambéry
dans `CITATION.cff` et le `NEWS.md` du lot. La paternité de la méthode leur
revient.
