# Spécification — `dsr_cubature()`, déblai / remblai le long d'un tracé

**Équivalent dessertR de CubaRoad** (SylvaLab / ONF Pôle RDI Chambéry, Sylvain
Dupire 2021 ; portage QGIS `github.com/Tijjat/CubaRoad_qgis_plugin`, GPL-3.0)

Statut : spécification, **v0.1** — non implémentée, non arbitrée dans la roadmap
du [BRIEF](BRIEF.md).
Source analysée : `cubaroad/CubaRoad_1_function.py` (3 488 l.) du portage QGIS,
plus le jeu de résultats `ResSimu_35_Res5m_Pas10` qui donne le schéma de sortie
exact.

---

## 0. L'inversion qui rend ce lot plus intéressant que l'original

CubaRoad calcule la cubature d'une route **à construire**, sur un MNT supposé
vierge. dessertR mesure des routes **qui existent**, sur un MNT Lidar HD à 50 cm
où la plateforme est déjà creusée.

Appliquer la même mécanique à une route existante ne donne pas le coût de sa
construction — il est déjà payé. Cela donne le **coût de sa mise au gabarit** :
`dsr_measure()` sort `LARGEUR_ROULABLE`, `dsr_emprise_certu()` sort la largeur
normative visée, la différence entre les deux est un élargissement, et la
cubature de cet élargissement est un chiffre en euros.

C'est la question que se pose réellement un gestionnaire français : non pas
« où créer une route » mais « que coûte de faire passer le grumier sur celle-ci ».
`dsr_trafficability()` répond déjà « ça ne passe pas ». La cubature répond
« et voici combien pour que ça passe ». **C'est le complément manquant de la
sortie métier du paquet**, et il n'existe dans aucun outil actuel.

Deux régimes à prévoir, donc, avec le même noyau :

| Régime | Terrain de référence | Question |
|---|---|---|
| `"construction"` | MNT hors emprise, plateforme absente | Que coûte de construire ce tracé ? |
| `"elargissement"` | MNT Lidar HD, plateforme existante incluse | Que coûte d'élargir cette route au gabarit visé ? |

Le régime `"elargissement"` est celui qui justifie le lot. Le piège associé est
en §5.

---

## 1. Entrées

**Obligatoires**

- `trace` : `sf` `LINESTRING`. Sortie de `dsr_repositionner()`, de
  `dsr_vectoriser()`, ou d'un futur `dsr_tracer()` (voir
  [SPEC_TRACER.md](SPEC_TRACER.md)).
- `mnt` : `SpatRaster`. CubaRoad tourne sur du RGE Alti 5 m ; le MNT Lidar HD
  50 cm de dessertR est deux ordres de grandeur plus fin, ce qui change la
  nature du résultat (§5).

**Attributs par tronçon** (CubaRoad les lit dans le shapefile ; dessertR peut
les **dériver** de `dsr_measure()` et `dsr_emprise_certu()` au lieu de les
exiger, et c'est l'apport principal)

| Attribut | (CubaRoad) | Source dessertR possible |
|---|---|---|
| Largeur de plateforme visée, m | `L_PLAT` | `dsr_emprise_certu()`, ou `dsr_seuils_grumier()` |
| Pente du talus amont, % | `S_UP` | défaut par nature de terrain, à calibrer |
| Pente du talus aval, % | `S_DOWN` | idem |
| Pourcentage de rocher | `P_ROCHER` | à saisir — le nuage ne le donne pas |

**Paramètres**

| Argument | (CubaRoad) | Rôle |
|---|---|---|
| `pas` | `step` | Espacement des points d'analyse, m. 10 m dans le jeu livré. |
| `ripage_max` | `max_exca_slope` | Dévers au-delà duquel **tout** passe en déblai (ripage = 1). |
| `ripage_min` | `min_exca_slope` | Dévers en deçà duquel déblai et remblai s'équilibrent (ripage = 0). |
| `tol_z` | `z_tolerance` | Tolérance altimétrique de détection du point de niveau, m. |
| `tol_xy` | `xy_tolerance` | Rayon de recherche du point de niveau autour de l'axe théorique, m. Défaut : `0,5 × largeur`. |

---

## 2. Le cœur : un profil en travers théorique par point d'analyse

### 2.1 Découpage et transects

Le tracé est découpé au `pas`, chaque point d'analyse reçoit un **transect
perpendiculaire**, et le profil du terrain y est extrait puis ré-interpolé au
**centimètre** (`step2 = 0.01`). Les lacets reçoivent un traitement séparé
(points de centre de lacet, `get_profil_L`/`get_profil_L2`).

**`dsr_profils()` fait déjà exactement cela** — il rend `stations`, `offsets`,
la matrice `z` et les `normales`. C'est la brique de réemploi la plus directe :
il suffit de descendre `pas_travers` à 0,01 m et d'élargir `demi_largeur` à
l'emprise attendue. Environ un tiers du travail de CubaRoad est déjà écrit dans
`measure.R`.

### 2.2 Le point de niveau

L'axe théorique du tracé n'est pas à l'altitude du terrain. CubaRoad cherche
donc, dans un rayon `tol_xy` autour de l'axe, le point du profil dont l'altitude
**égale celle de la plateforme** à `tol_z` près : le **point de niveau**. C'est
lui, et non l'axe, qui ancre le profil théorique.

S'il n'existe pas dans `tol_xy`, la recherche est élargie à
`tol_xy + 0,5 × largeur`. S'il n'existe toujours pas, deux cas dégénérés :
plateforme entièrement sous le terrain (`config = 3`, tout en déblai) ou
entièrement au-dessus (`config = 5`, tout en remblai). Les configurations 1 à 6
qualifient chaque point et **doivent être restituées** : elles expliquent les
valeurs aberrantes.

### 2.3 Le ripage — la seule vraie idée du modèle

Le dévers est mesuré de part et d'autre du point de niveau sur ±6 m. Selon les
signes, la situation est classée :

- les deux versants montent → **`hole`**, thalweg, tout en déblai ;
- les deux descendent → **`top`**, croupe, tout en remblai ;
- signes opposés → versant, et le côté amont détermine `left` / `right`.

Sur un versant, le **ripage** interpole linéairement le dévers amont entre les
deux seuils :

```
ripage = (dévers_amont − ripage_min) / (ripage_max − ripage_min), borné à [0, 1]

assise_déblai = largeur / 2 × (1 + ripage²)
assise_remblai = largeur − assise_déblai
```

La lecture physique : sur pente douce (`ripage = 0`) la plateforme est à moitié
en déblai, à moitié en remblai — on équilibre. Sur pente raide (`ripage = 1`)
le remblai ne tient pas et la totalité passe en déblai. **Le carré** rend la
transition tardive : on reste proche de l'équilibre jusqu'à mi-course, puis on
bascule vite. C'est un choix de modélisation, pas une loi — à confronter à des
métrés réels avant de l'adopter tel quel.

### 2.4 Construction du profil théorique

À partir du point de niveau : plateforme horizontale sur l'assise, puis **talus
amont** à `S_UP` prolongé jusqu'à recouper le terrain, **talus aval** à `S_DOWN`
de même. Si le talus ne recoupe jamais le terrain, CubaRoad **durcit la pente
par paliers** — 67 %, 100 %, 150 %, 400 % — jusqu'à intersection. Ce garde-fou
n'est pas cosmétique : sans lui le profil part à l'infini et le volume diverge.
**Il doit être signalé dans la sortie** (le jeu livré marque `100*` la colonne
talus amont quand le palier a été forcé) — un talus à 400 % est un aveu
d'échec du modèle sur ce point, pas un résultat.

### 2.5 Sections, volumes, emprise

```
section_déblai  = Σ (z_terrain − z_route)⁺ × 0,01        [m²]
section_remblai = Σ (z_route − z_terrain)⁺ × 0,01        [m²]
volume          = section × longueur applicable          [m³]
emprise         = distance entre les deux intersections talus/terrain  [m]
volume_roche    = volume_déblai × P_ROCHER / 100
```

Le **volume à évacuer** n'est pas le volume de déblai : sur un profil équilibré
le déblai est réemployé en remblai sur place. CubaRoad ne cumule à l'évacuation
que les points où le réemploi est impossible — dévers supérieur à `ripage_max`,
ou configuration 3 ou 6. C'est le chiffre qui a un prix, et c'est celui qu'il
faut mettre en avant.

---

## 3. Sorties

```r
list(
  points     = sf POINT,        # un par point d'analyse, ~37 attributs
  centre     = sf LINESTRING,   # ligne des centres de plateforme
  niveau     = sf LINESTRING,   # ligne des points de niveau
  assise     = sf POLYGON,      # surface d'assise
  emprise    = sf POLYGON,      # surface d'emprise totale
  transects  = sf LINESTRING,
  resume     = data.frame       # totaux : longueur, V_déblai, V_évacuer,
                                # V_remblai, V_roche, surface d'emprise
)
```

Le schéma d'attributs par point est donné par `Tab_cubature_pts_tous.csv` du
jeu livré et doit être repris tel quel — il est le fruit d'un usage métier et
n'est pas à réinventer : type de piquet, configuration, pentes gauche/droite,
longueur applicable, largeur d'assise, talus amont/aval, assise et section et
volume en déblai, volume à évacuer, % et volume de roche, assise/section/volume
en remblai, assiettes, piquets de contrôle amont et aval, emprise et surface,
coordonnées du point de niveau et du point central, azimut, distance et pente
longitudinale vers le point suivant.

Prévoir aussi la **figure du profil en travers avant/après** par point : c'est
ce qui rend le résultat vérifiable par un technicien, et c'est trivial avec la
matrice `z` de `dsr_profils()`.

---

## 4. Ce que dessertR apporterait en plus

- **Les entrées deviennent des sorties mesurées.** CubaRoad exige une largeur
  d'assise saisie ; dessertR la mesure. Le couple
  `dsr_measure()` → `dsr_cubature()` boucle la chaîne : mesurer l'existant,
  chiffrer l'écart au gabarit.
- **La confiance se propage.** `CONFIANCE_MNT` qualifie déjà chaque station ; un
  volume calculé sous couvert dense doit sortir avec sa barre d'erreur, pas nu.
  CubaRoad n'a pas cette information — dessertR l'a déjà et ne l'utiliserait
  nulle part ailleurs aussi bien.
- **Les places de dépôt et de retournement** (`dsr_places()`) sont des cubatures
  aussi, et le même noyau les traite.

---

## 5. Les deux risques

**Le MNT Lidar HD contient déjà la route.** En régime `"elargissement"`, le
« terrain » de référence inclut la plateforme existante : la cubature calculée
est celle de l'écart au gabarit, pas celle de la construction. C'est voulu, mais
la confusion est facile et coûteuse. Le régime doit être un argument obligatoire
sans défaut, et le résumé doit rappeler lequel a tourné. En régime
`"construction"` sur MNT Lidar HD, il faut au contraire **combler** l'emprise
existante avant de calculer — sinon on chiffre le creusement d'un fossé déjà
creusé.

**La résolution change le résultat, pas seulement sa précision.** À 5 m, le
profil en travers est lissé et les volumes sont sous-estimés de façon régulière.
À 50 cm, chaque ornière et chaque souche entre dans la section. Un banc
comparatif 50 cm / 1 m / 5 m sur le bloc wsfi est un préalable, pas une
validation *a posteriori* : il faut savoir à quelle résolution le chiffre a un
sens avant de le publier. Un lissage transversal (`liss_travers`, déjà présent
dans `dsr_measure()`) sera probablement nécessaire.

---

## 6. Estimation

| Étape | Charge |
|---|---|
| Transects et profils (adaptation `dsr_profils()`) | 0,5 sem |
| Point de niveau, ripage, profil théorique, paliers de talus | 2 sem |
| Lacets (`get_profil_L` / `L2`) | 1 sem |
| Sections, volumes, bilan d'évacuation | 0,5 sem |
| Sorties SIG et tableur au schéma CubaRoad | 1 sem |
| Régime `"elargissement"` + banc de résolution | 1,5 sem |

**≈ 6,5 semaines**, dont un tiers déjà couvert par `measure.R`. Nettement moins
lourd que [SPEC_TRACER.md](SPEC_TRACER.md) (≈ 8 sem), pour une valeur métier
plus directe dans le contexte français — le BRIEF §1 a déjà arbitré que
mesurer l'existant prime sur concevoir du neuf. **Si un seul des deux lots doit
être ouvert, c'est celui-ci.**

---

## 7. Licence

Le dépôt CubaRoad porte un `LICENSE` **GPL-3.0** (en-têtes de source en « v2 or
later »), dessertR est en **GPL (>= 3)** — compatible.
Comme pour SPEC_TRACER, la réimplémentation depuis cette spec est le
régime recommandé ; le schéma de sortie, lui, peut être repris à l'identique
(c'est un format, pas du code). Citer Dupire / SylvaLab / ONF Pôle RDI Chambéry
dans `CITATION.cff` et le `NEWS.md` du lot.
