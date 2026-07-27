# Brief de développement — `dessertR`

**Correction, mesure et qualification de la desserte forestière à partir du Lidar HD (IGN) et de la BD TOPO**

Dépôt cible : `github.com/pobsteta/dessertR`
Statut : brief de conception, **v0.2** — entrées arbitrées : MNT + MNH + **nuage de points classé**
Inspiration : ALSroads (Roussel *et al.* 2022) et vecnet (Roussel *et al.* 2023), réécrits pour le contexte français.

*Noms alternatifs : `desserte`, `roadHD`, `lidesserte`.*

---

## 0. Ce que change l'ajout du nuage de points

Décision prise : socle **`lasR` + `terra`**, entrées **MNT 50 cm + MNH 50 cm + dalles LAZ classées**. C'est le bon choix, et pour une raison plus forte que celles listées en v0.1.

**Le MNH ne suffit pas à qualifier l'état d'une route, et ce n'est pas un détail.** Le MNH est une hauteur de sursol dérivée du MNS, donc dominée par le point le plus haut. Sous une futaie fermée, le MNH vaut 25 m au-dessus d'une route parfaitement roulante comme au-dessus d'une piste condamnée par les ronces. Les deux situations sont strictement indiscernables sur le MNH.

Seul le nuage donne le **profil vertical dans l'emprise** : la densité d'échos entre 0,3 et 3 m au-dessus du sol sépare sans ambiguïté « route dégagée sous couvert haut » de « route recolonisée par le sous-étage ». C'est exactement le signal d'abandon recherché, et il n'existe dans aucun raster dérivé.

Conséquence : le canal `sigma_surf` du §3.4 repose désormais sur le nuage, pas sur le MNH. Le MNH garde deux rôles utiles mais secondaires — masque du couvert haut, et calcul rapide en pré-filtrage avant de descendre dans le nuage.

Le nuage apporte aussi quatre choses qu'aucun raster ne donne :

| Apport | Usage |
|---|---|
| Classe **tablier de pont** | Corridors franchissables — résout proprement le problème des ponts (voir §2.1) |
| **Densité de points sol** | Carte de confiance du MNT : là où elle s'effondre, l'openness est du bruit et il faut le savoir |
| **Rugosité brute des points sol** | Écart-type de z après retrait d'un plan local, sans le lissage de l'interpolation du MNT. Sépare l'empierré du terrain naturel |
| Classes **eau / points virtuels / sursol pérenne** | Masques explicites, au lieu de les deviner sur le raster |

---

## 1. Repositionnement de la valeur par rapport à ALSroads

ALSroads répond à un problème québécois : une carte de desserte **mal positionnée** (décalages de 10 à 50 m), sans largeur ni classe. Son innovation centrale — le repositionnement par pathfinder — perd beaucoup de son intérêt avec la BD TOPO, dont la précision planimétrique est déjà métrique.

**En France, la valeur se déplace vers :**

1. **Mesurer** ce que la BD TOPO ne dit pas ou dit mal : largeur roulable réelle, fossés, dévers, pente longitudinale, rayons de courbure.
2. **Qualifier la praticabilité**, en particulier **l'aptitude au grumier** — c'est *la* question métier.
3. **Détecter la desserte absente de la BD TOPO** : pistes forestières, cloisonnements d'exploitation, places de dépôt et de retournement, anciennes RF déclassées. C'est le gisement le plus important : la BD TOPO sous-représente massivement la desserte interne aux massifs.
4. **Diagnostiquer l'état** : tronçon BD TOPO qui n'existe plus, tronçon dégradé, tronçon recolonisé.

Le repositionnement reste utile mais devient un **module de raffinement**, pas le cœur. À traduire dans la roadmap : ne pas mettre quatre semaines sur le pathfinder avant d'avoir livré la mesure de largeur.

---

## 2. Données d'entrée

### 2.1 Lidar HD (IGN, licence ouverte Etalab)

- **Nuage classé** : LAZ 1.4 (souvent COPC), dalles 1 km × 1 km, ≥ 10 impulsions/m², **11 classes** — sol, végétation basse (0–50 cm) / moyenne (50 cm–1,50 m) / haute (> 1,50 m), bâtiment, eau, **tablier de pont**, non classé, sursol pérenne, points virtuels, divers bâtis. ~200 Mo par dalle COPC.LAZ.
- **MNT** : GeoTIFF 50 cm, dalles 1 km, dérivé des points *sol*, *eau* et *points virtuels*.
- **MNH** : GeoTIFF 50 cm, différence MNS − MNT, produit diffusé (pas besoin de le recalculer).
- Couverture métropolitaine : ~80 % fin 2025, complète annoncée fin 2026.

**Pièges à traiter explicitement dans le code :**

- **Version de classification.** L'IGN a basculé sur une classification dite **V5**, sur laquelle sont calés les MNT/MNS/MNH cibles, avec identification dans le nuage des points retenus pour la modélisation (meilleure gestion des recouvrements et des forts dévers, notamment canopées et **bords de ponts**). Des dalles antérieures circulent encore. **Le catalogue doit lire la version dans l'en-tête et refuser ou signaler les mélanges** : sinon les métriques ne sont pas comparables d'un bloc à l'autre, et les campagnes de validation deviennent ininterprétables.
- **Les tabliers de pont ne sont pas dans le MNT.** Sous un pont, le MNT descend dans le talweg : la route « plonge » et la conductivité s'effondre. Avec le nuage, c'est direct — la classe *tablier de pont* fournit les corridors franchissables. Beaucoup plus propre que le `sigma_min` global d'ALSroads, qu'on garde néanmoins comme garde-fou.
- **Points virtuels** : à **exclure systématiquement** avant tout calcul de rugosité ou de densité sol. Ce sont des points synthétiques ; les inclure fabrique des plateformes lisses fictives, exactement le faux positif à éviter.
- **L'intensité n'est pas calibrée** : plusieurs prestataires, capteurs et années. Une normalisation intra-bloc (distance de visée, angle) est indispensable, et même normalisée elle ne transfère pas d'un bloc à l'autre. **Ne pas faire reposer l'état sur l'intensité** — la densité d'échos et le taux de pénétration sont bien plus stables. Intensité en option désactivée par défaut.
- **Hétérogénéité temporelle** : blocs échelonnés sur plusieurs années, BD TOPO mise à jour en continu. Propager la date d'acquisition du bloc dans les sorties, sans quoi un « tronçon disparu » peut n'être qu'un tronçon créé après le vol.
- **Saison d'acquisition** : sous couvert feuillu en feuilles, la densité de points sol chute. C'est mesurable — d'où l'intérêt de la couche de confiance ci-dessus.

### 2.2 BD TOPO (IGN, licence ouverte)

| Thème | Usage |
|---|---|
| `troncon_de_route` | Carte de référence. Attributs `nature`, `importance`, `largeur_de_chaussee`, `nb_voies`, `etat_de_l_objet`, `acces_vehicule_leger`, `position_par_rapport_au_sol`. *Vérifier les noms exacts selon la version BD TOPO 3.x.* |
| `troncon_hydrographique` | Barrière molle + franchissements. Attribut `persistance` : un cours d'eau intermittent n'est pas une barrière. |
| `surface_hydrographique` | **Barrière dure**, hors ponts. |
| `construction_lineaire` / ouvrages | Ponts, passerelles, buses — en complément de la classe *tablier de pont*. |
| `zone_de_vegetation` | Emprise d'étude, et covariable (feuillus / conifères / mixte). |
| `batiment` | Masque. |

Le package doit accepter **n'importe quelle carte de référence `sf`**, pas seulement la BD TOPO : couches de desserte ONF, coopératives, parcellaire.

---

## 3. Architecture fonctionnelle

```
dessertR/
├── R/
│   ├── catalog.R        # catalogage dalles LAZ + MNT/MNH, index spatial, VRT, régimes de lecture
│   ├── layers_dtm.R     # canal géomorphologique (MNT)
│   ├── layers_pc.R      # canal surface + qualité (nuage, via lasR)
│   ├── conductivity.R   # sigma_geo / sigma_surf
│   ├── pathfinder.R     # interface R du noyau C++
│   ├── measure.R        # largeur, fossés, pente, dévers, sinuosité
│   ├── state.R          # divergence des canaux → état
│   ├── trafficability.R # aptitude grumier, places de dépôt
│   ├── network.R        # cohérence topologique
│   ├── detect.R         # détection hors référence (v2)
│   └── io.R             # export GPKG, styles QGIS, rapport
├── src/                 # pathfinder anisotrope (cpp11)
├── inst/extdata/        # 1 dalle LAZ écrêtée + MNT + MNH + extrait BD TOPO
└── vignettes/
```

### 3.1 `catalog.R` — le socle qui conditionne les performances

Les dalles LAZ et les dalles MNT/MNH partagent la **même grille kilométrique**. Le catalogue peut donc être indexé sur l'identifiant de dalle, ce qui simplifie beaucoup l'appariement. Points de conception :

- Index spatial `sf` des emprises, regroupement des tronçons **par dalle** (jamais l'inverse : le défaut d'ALSroads est de relire les données par segment).
- **Deux régimes de lecture, à exposer explicitement :**
  - `regime = "corridor"` — lecture du nuage restreinte à un tampon autour du réseau de référence (30–50 m). Sur une dalle forestière, c'est typiquement 5 à 10 % des points. **C'est ce qui rend le traitement d'un massif entier réaliste.** Régime par défaut pour la correction et la mesure.
  - `regime = "complet"` — dalle entière, nécessaire uniquement pour la détection de desserte hors référence (§3.9). Coût sans commune mesure, à réserver aux zones d'intérêt.
- Laisser `lasR` gérer le tuilage et les buffers pour les couches issues du nuage — c'est son travail et il le fait en C++ multi-thread. Utiliser `terra` + VRT pour les couches issues du MNT. **Le point délicat est l'alignement final des deux familles de rasters** : imposer une grille de référence unique dérivée du MNT et y aligner toutes les sorties `lasR`, plutôt que de rééchantillonner après coup.
- Cache disque des couches, avec empreinte des paramètres, pour rejouer sans recalculer.
- Ordre de grandeur à garder en tête : un massif de 5 000 ha ≈ 50 dalles ≈ 10 Go de LAZ. Un département en régime `complet` est hors de portée sans infrastructure dédiée — le dire dans la doc.

### 3.2 `layers_dtm.R` — canal géomorphologique

Couches **continues et non étirées** : on ne fabrique pas un composite RVT type VAT/CVAT, on en reprend les ingrédients en bandes brutes.

| Couche | Rôle | Note |
|---|---|---|
| Pente | Base | Rayon 1–2 m |
| Rugosité résiduelle | Une route est anormalement lisse | Voir §3.3 : la version issue des points sol est meilleure |
| Openness négative multi-échelle | Fossés latéraux — marqueur le plus discriminant | Rayons 2 / 5 / 10 m |
| Openness positive | Plateforme et remblais | Idem |
| SVF | Routes en déblai sous couvert | Corrélé aux précédents |
| SLRM / MSTP | Route comme terrasse locale plane, robuste à la largeur (3 à 12 m) | L'apport multi-échelle est le vrai gain sur ALSroads |
| Vesselness (Hessien / Frangi) | Probabilité de linéarité **et orientation θ** | Alimente le pathfinder anisotrope |

Deux remarques d'implémentation :

- Openness et SVF sont coûteux (balayage directionnel) : C++ obligatoire, ou pré-traitement RVT externe. Chiffrer avant de choisir — une dépendance Python dans un package R est un coût de maintenance durable.
- **Le MNT à 50 cm est trop fin pour les couches multi-échelles.** Rééchantillonner à 1 m réduit le bruit d'interpolation et divise le coût par 4. Garder le 50 cm pour la mesure de largeur et la détection de fossés uniquement.

### 3.3 `layers_pc.R` — canal surface et qualité, via `lasR`

C'est le module qui justifie l'ajout du nuage. Toutes les métriques sont calculées sur une grille alignée sur le MNT, à 1 m (2 m suffit pour les métriques de couvert).

| Métrique | Filtre | Interprétation |
|---|---|---|
| `densite_sousetage` | échos 0,3–3 m au-dessus du sol, rapportés au total | **Recolonisation de l'emprise.** Le signal d'abandon. Inaccessible au MNH |
| `taux_penetration` | points sol / points totaux | Ouverture de la canopée au-dessus de l'emprise |
| `densite_sol` | classe sol, hors points virtuels, pts/m² | **Couche de confiance du MNT**, pas de détection |
| `rugosite_sol` | écart-type de z des points sol après retrait d'un plan local | Rugosité vraie, non lissée. Sépare empierré / terre battue |
| `h_couvert` | percentile haut de la végétation haute | Contexte, corroboré par le MNH |
| `masque_pont` | classe tablier de pont | Corridors franchissables |
| `masque_exclusion` | eau, points virtuels, sursol pérenne, bâtiment | Zones neutralisées |
| `intensite_norm` | *optionnel, désactivé par défaut* | Normalisation intra-bloc obligatoire si activé |

Sur `lasR` : le paquet fonctionne par **pipelines** (lecteur + étages + écriture) exécutés sur un catalogue, avec gestion native du tuilage, des buffers et du multi-threading. Le schéma est `reader → filtres → rasterize(résolution, expression) → exec()`. **Vérifier les noms exacts des fonctions et des filtres dans la version courante** — l'API a bougé entre les versions et le brief ne doit pas les figer. Prévoir aussi de contrôler le comportement sur les fichiers **COPC** dès le lot 0 : c'est le format de diffusion majoritaire du Lidar HD et un blocage ici arrêterait tout.

### 3.4 `conductivity.R` — le point de conception le plus important

**Ne pas fusionner en un score unique.** Deux rasters distincts :

- `sigma_geo` — probabilité d'une **empreinte de route dans le terrain** (canal géomorphologique, mémoire longue)
- `sigma_surf` — probabilité que cette empreinte soit **encore dégagée et circulable** (canal nuage, état présent)

Le pathfinder tourne sur `sigma_geo`, robuste à la végétation. L'état se lit dans la **divergence** entre les deux le long du tracé retenu :

| `sigma_geo` | `sigma_surf` | Interprétation |
|---|---|---|
| fort | fort | Route en service |
| fort | faible | **Route abandonnée / recolonisée** |
| faible | fort | Trouée sans route (coupe rase, ligne électrique, layon) — faux positif à filtrer |
| faible | faible | Pas de route |

Plus propre et plus interprétable que le `SCORE` composite d'ALSroads, et directement défendable dans une publication.

Pour la fusion vers `sigma_geo` : **commencer par une combinaison paramétrique explicite** (produit ou somme pondérée de fonctions d'appartenance, avec `sigma_min` pour éviter les zéros infranchissables). Ne passer à une conductivité apprise (petit U-Net sur la pile de rasters) qu'après avoir constitué un jeu de validation — sinon rien ne permet d'arbitrer. Prévoir l'interface dès le départ : `conductivity(..., method = c("param", "model"))`.

**Pondérer `sigma_geo` par `densite_sol`.** Là où la densité de points sol s'effondre, l'openness est du bruit : la conductivité doit y être marquée comme incertaine plutôt que faible. C'est le genre de détail qui fait la différence entre un prototype et un outil utilisable en futaie feuillue.

### 3.5 `pathfinder.R` + `src/`

- Noyau C++ (`cpp11`, plus léger que Rcpp), **sans dépendance Boost**.
- **Coût anisotrope avec état (x, y, θ)** et pénalité de courbure. Une route a une direction ; sans cela le chemin coupe les virages et saute sur les linéarités parallèles (fossés, lignes, cloisonnements). C'est l'amélioration qualitative la plus rentable par rapport à ALSroads.
- Voisinage 16 minimum, ou fast marching, pour supprimer le biais de métrication de Dijkstra 8-connexe (tracés en escalier à 0°/45°).
- Sortie : le chemin optimal **et** une incertitude latérale dérivée de la courbure transversale du champ de coût. Savoir où le résultat est douteux vaut autant que le résultat.

### 3.6 `measure.R`

Profils transversaux tous les 2 m. **Deux sources complémentaires** :

- MNT 50 cm pour la géométrie de la plateforme et des fossés ;
- points sol bruts du nuage pour la largeur roulable fine — on peut y recalculer un micro-MNT à 25 cm sur la seule emprise, plus net que le produit IGN.

Attributs : `LARGEUR_PLATEFORME`, `LARGEUR_ROULABLE`, `FOSSES` (0/1/2), `DEVERS`, `PENTE_LONG_MOY`, `PENTE_LONG_MAX`, `RAYON_COURBURE_MIN`, `SINUOSITE`, `DEPLACEMENT` (distance à la géométrie BD TOPO d'origine), `INCERTITUDE_LAT`, `CONFIANCE_MNT`.

### 3.7 `trafficability.R` — la sortie métier

Règles paramétrables, à caler avec un gestionnaire (ONF, coopérative, ETF), jamais figées en dur :

- `APTE_GRUMIER` : largeur roulable, rayon de courbure, pente longitudinale, continuité — chacun avec son seuil.
- `MOTIF_INAPTITUDE` : **quel critère bloque, et où.** Un booléen sans motif est inutilisable sur le terrain.
- `GABARIT_LIBRE` : hauteur libre sous branches le long du tracé, calculée directement sur le nuage. Critère réel pour un grumier (≈ 4,5 m) et totalement absent des bases existantes — c'est une sortie à forte valeur, offerte par le nuage.
- `PLACE_DEPOT` / `PLACE_RETOURNEMENT` : détection des élargissements locaux, sortie à part entière.

### 3.8 `network.R`

Point faible structurel d'ALSroads : chaque tronçon est corrigé indépendamment, donc les jonctions ne coïncident plus et des doublons parallèles apparaissent.

- Contrainte de coïncidence aux nœuds partagés de la BD TOPO.
- Déduplication des tracés parallèles à moins d'une largeur d'écart.
- Vérification de la connectivité au réseau public : une desserte qui ne débouche nulle part est un artefact.
- Export d'un graphe valide (`sfnetworks`), pas une collection de `LINESTRING`.

### 3.9 `detect.R` (v2)

Détection de la desserte absente de la référence, en régime `complet`. Le nuage change ici aussi la donne : les cloisonnements et pistes de débardage se voient surtout par la **discontinuité du sous-étage** et l'ornière, pas par la géomorphologie. Chaîner avec `vecnet` pour la vectorisation plutôt que de réécrire un squelettiseur.

---

## 4. Validation

Sans jeu de validation, le projet n'est pas arbitrable. À constituer **au lot 1, pas à la fin**.

- 2 à 3 massifs contrastés : feuillus de plaine (Bourgogne — terrain proche et Lidar HD disponible), résineux de montagne (forte pente, dévers), plateau calcaire (chemins creux et traces fossiles nombreuses → test du canal géomorphologique).
- Idéalement, choisir au moins un massif où deux saisons d'acquisition ou deux versions de classification coexistent, pour mesurer la sensibilité des métriques.
- Vérité terrain : couches de desserte du gestionnaire, traces GNSS, photo-interprétation sur ortho IGN, échantillon de relevés de largeur.
- Métriques : RMSE latéral, MAE sur la largeur roulable, matrice de confusion sur l'état, précision/rappel sur les tronçons hors BD TOPO et sur `APTE_GRUMIER`.
- Publier ces chiffres dans le README. C'est ce qui séparera un package utilisé d'un dépôt de plus.

---

## 5. Roadmap par lots

| Lot | Contenu | Livrable | Ordre de grandeur |
|---|---|---|---|
| **L0** | Squelette, catalogue dalles LAZ + MNT/MNH, **validation lecture COPC et détection version de classification**, régime `corridor`, CI, jeu d'exemple | Une dalle se lit, un corridor s'extrait | 3–4 sem |
| **L1** | Couches MNT (`sigma_geo` paramétrique) + `densite_sol` + **jeu de validation** | Conductivité inspectable dans QGIS | 4 sem |
| **L2** | Mesure sur géométrie BD TOPO non corrigée, avec points sol bruts | **Premier livrable métier** : largeurs, fossés, gabarit libre | 3 sem |
| **L3** | Canal nuage complet, `sigma_surf`, divergence, état | Classification d'état validée | 3 sem |
| **L4** | Pathfinder anisotrope + incertitude latérale | Tracés corrigés | 3–4 sem |
| **L5** | Praticabilité grumier, places de dépôt et de retournement | Sortie exploitable par un gestionnaire | 2 sem |
| **L6** | Topologie réseau, export `sfnetworks` | Réseau cohérent | 3 sem |
| **L7** | Détection hors référence (régime `complet`), chaînage `vecnet` | v2 | — |
| **L8** | Conductivité apprise, si le jeu de validation le permet | v2 | — |

Deux inversions par rapport à v0.1, conséquences directes de l'ajout du nuage :

- **L2 avant le pathfinder.** Mesurer sur la géométrie BD TOPO existante donne un résultat utile en ~10 semaines sans repositionnement. C'est le moyen le plus rapide d'avoir un retour d'un vrai utilisateur.
- **L3 (état) avant L4 (tracé).** L'état est désormais le point fort du dispositif — c'est là que le nuage paie. Le repositionnement, moins critique en France, passe après.

---

## 6. Choix techniques

- R ≥ 4.2. `terra` (jamais `raster`, retiré), `sf`, **`lasR` en `Imports`**, `data.table`, `cpp11`, `mirai`. `sfnetworks` en `Suggests` puis promu.
- Pas de dépendance Python en `Imports`. Si RVT s'avère nécessaire pour l'openness, l'encapsuler en pré-traitement optionnel documenté.
- Parallélisme : laisser `lasR` gérer ses threads ; paralléliser au niveau dalle uniquement pour les couches `terra` (mono-thread). **Ne pas empiler les deux niveaux** — c'est la recette classique de la sursouscription CPU.
- Tests `testthat` sur un extrait minimal versionné : une dalle LAZ écrêtée à quelques centaines de milliers de points, plus MNT/MNH et extrait BD TOPO croppés. Licence ouverte Etalab côté données, redistribution possible — vérifier la mention d'attribution.
- CI GitHub Actions : `R-CMD-check` Linux/macOS/Windows + job de non-régression numérique. Attention : `lasR` n'est pas sur le CRAN, prévoir son installation dans le workflow.
- Documentation `pkgdown` + vignette « du téléchargement des dalles au GPKG de sortie ».
- **Licence** : vérifier celle d'ALSroads avant tout emprunt de code (probablement GPL-3, comme lidR). Reprendre la *méthode* d'un article publié est libre ; recopier du code ne l'est pas. Citer Roussel *et al.* 2022 et 2023 dans `README` et `CITATION`.
- Contacter Jean-Romain Roussel en amont : r-lidar a basculé sur un modèle de support commercial, `lasR` est son moteur, et une partie de ce brief recoupe peut-être des travaux engagés.

---

## 7. Les quatre risques qui peuvent tuer le projet

1. **Les traces fossiles.** En forêt française, le sol est saturé de linéarités anciennes : chemins creux, voies romaines, limites parcellaires, anciennes RF, cloisonnements abandonnés, fossés de drainage. Le canal géomorphologique va toutes les allumer. La séparation `sigma_geo` / `sigma_surf` est précisément l'arme prévue contre ça, et l'ajout du nuage la rend beaucoup plus tranchante qu'avec le MNH seul — mais il faut le vérifier, **dès le lot 1, sur le massif le plus « pollué » disponible**. Risque n°1, spécifique au contexte français.
2. **Le volume.** 200 Mo par dalle, ~10 Go pour 5 000 ha. Si le régime `corridor` ne tient pas ses promesses, le passage à l'échelle d'un massif devient douloureux et celui d'un département impossible. **À chiffrer au lot 0, sur données réelles, avant d'écrire quoi que ce soit d'autre.**
3. **La qualité du MNT sous couvert dense.** Si la densité de points sol s'effondre en futaie feuillue en feuilles, l'openness à petit rayon devient du bruit. La bonne nouvelle : avec le nuage, cette dégradation est *mesurable* (`densite_sol`) au lieu d'être subie. La mauvaise : si elle est massive sur tes massifs cibles, une partie de l'édifice ne tient plus.
4. **L'absence d'utilisateur identifié.** ALSroads est resté un *proof of concept* sans reprise. Trouver un gestionnaire prêt à donner un retour dès le lot 2 vaut plus que six mois de raffinement algorithmique.
