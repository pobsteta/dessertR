# dessertR (cycle de developpement)

## Le sous-type de parcellaire ne se devine pas non plus

[dsr_classer()] annonce desormais sa supposition quand un `parcellaire` est
fourni sans `sous_type_parcelle` -- meme regle que le `regime` de
[dsr_cubature()] : une valeur qui ne se lit pas dans la geometrie ne se suppose
pas en silence. Les limites d'un parcellaire de GESTION forestiere sont les
layons materialises au sol (`cutline=section`) ; celles d'un parcellaire
CADASTRAL ne sont que des limites de propriete (`cutline=border`). Meme
geometrie, tag different.

La documentation avertit d'un piege voisin : **des contours d'unites de gestion
ne sont pas des limites cadastrales.** Une unite taillee dans une portion de
parcelle a des cotes de decoupe interne, qui ne correspondent a rien sur le
terrain ; les fournir ferait classer en layon des lineaires qui suivent une
limite purement administrative. Ce sont les limites des parcelles elles-memes
qu'il faut passer.

## La cubature dit sur quel terrain elle croit travailler

[dsr_cubature()] prend un argument `regime` : `"elargissement"` (le MNT porte
deja la plateforme -- cas du Lidar HD) ou `"construction"` (terrain vierge).
Chiffrer une construction sur un MNT qui contient deja la route donne un
resultat faux et vraisemblable, ce qui est le pire des cas.

Il est **sans valeur par defaut**. `dev/SPEC_CUBATURE.md` le voulait obligatoire ;
le rendre tel aurait casse tous les appels existants, d'ou un compromis assume :
omissible, mais **jamais silencieux** -- l'omission suppose `"elargissement"` et
le dit, et le regime retenu part dans `resume$regime`.

**La declaration est verifiee contre le terrain.** En regime `"construction"`,
chaque profil compare la pente en travers de la bande centrale a celle des
bandes qui la flanquent : sur un versant vierge les deux se valent, sur un
versant terrasse le replat trahit l'emprise. Au-dela de la moitie des profils,
la fonction signale que le MNT contient probablement la route -- sans bloquer,
la decision restant a l'appelant. Le controle **s'abstient** sous 10 % de pente
en travers, ou un replat ne se distingue de rien.

# dessertR 1.3.0

Version de **la norme lue et du detecte qualifie**. La 1.2.0 remettait
l'instrument d'aplomb ; celle-ci fait parler ce qu'il produit -- et surtout ce
qu'il produit hors de la desserte.

Le fil conducteur est un constat : deux jeux de reference dormaient dans le
paquet sans que rien ne les lise.

* **La fiche Certu ne servait a rien.** Aucune fonction n'en lisait les
  colonnes, et elle echouait sur l'extrait livre avec le paquet. Elle est
  reparee, sa transcription verifiee ligne a ligne contre le PDF d'origine
  (97 lignes, aucun ecart), et [dsr_ecart_norme()] la met au travail dans
  [dsr_rapport()] -- dans un seul sens : la mesure informe sur ce que la norme
  suppose.
* **Ce que la detection remonte hors reference n'etait pas qualifie.** En foret
  geree, ce n'est pas majoritairement de la desserte : ce sont des
  cloisonnements et des layons. [dsr_classer()] leur donne une classe et
  propose un balisage OSM aligne sur le consensus de la communaute --
  `man_made=cutline` pour ce qui n'est pas une voie de circulation.

Ces deux sorties partagent une regle : **elles ne concluent pas ce qu'elles ne
peuvent pas etablir.** `BORDS_RESOLUS` dit quand un ecart compare une plateforme
a une chaussee, `CLASSE_CONF` chiffre la part de criteres renseignes, `access=`
n'est jamais infere du lidar mais peut etre atteste par une source, et le
pare-feu comme la place de depot restent hors classement faute de critere.

## Classer ce que la detection remonte, et proposer un balisage

[dsr_classer()] attribue une classe forestiere a chaque lineaire -- desserte,
route, piste, cloisonnement d'exploitation, layon parcellaire -- et propose le
balisage OpenStreetMap correspondant. Point de depart : le fil OSM-fr « Layons,
cloisonnements d'exploitation en forets publiques » (juillet 2026), ou l'ONF
decrit exactement notre methode (MNT Lidar HD) et demande comment baliser. Le
consensus qui en sort est repris tel quel : `man_made=cutline` (+ sous-type),
pas `highway=*`, pour ce qui n'est pas une voie de circulation.

Ce que la detection remonte hors reference, en foret geree, n'est pas
majoritairement de la desserte. Le traiter comme du bruit serait faux, comme
des routes aussi.

**La decision porte sur des structures, pas sur des seuils de largeur.**
[dsr_peignes()] repere les faisceaux de paralleles regulierement espaces -- la
signature d'un cloisonnement, qui n'existe jamais seul -- en **estimant la
periodicite sur la donnee** plutot qu'en posant un espacement a priori. Une
trace intruse retire une dent au peigne, elle ne le fait pas disparaitre.
`BORDS_CHAUSSEE` n'est deliberement pas un critere : il dit si la mesure a
reussi, pas si la route est construite.

**`access=*` n'est jamais infere, il peut etre atteste.** Un panneau ne se lit
pas dans un MNT ; tant que la seule entree est le lidar, aucun tag d'acces n'est
defendable. L'argument `panneaux` accepte des releves -- terrain, ou photos
geolocalisees d'un jumeau numerique -- et fait alors emettre `access=` avec sa
provenance dans `source:access`. Deux panneaux contradictoires n'emettent rien
et le motif le dit.

Le pare-feu et la place de depot ne sont pas classes automatiquement : le
premier demande un critere de crete que le paquet ne calcule pas, la seconde
n'est pas un lineaire et le fil OSM ne lui donne aucun tag consensuel.

Le parcellaire n'est pas acquis par le paquet : il vient de l'amont, qui seul
sait ce qu'il porte. `sous_type_parcelle` le lui fait dire -- `"section"` pour un
parcellaire de gestion forestiere, dont les limites sont les layons materialises
au sol, `"border"` pour un parcellaire cadastral, qui ne trace que des limites de
propriete. La geometrie est identique dans les deux cas ; le sous-type OSM, non.

La sortie -- `CLASSE`, `CLASSE_CONF`, `CLASSE_MOTIF`, `OSM_TAGS` -- est une
**proposition auditable**, pas un jeu pret a televerser : un import dans OSM
releve des regles de la communaute, pas d'une fonction R.

## L'ecart a la norme entre enfin dans le rapport

La fiche Certu ne servait a rien dans la chaine : aucune fonction ne lisait ses
colonnes. [dsr_ecart_norme()] les met au travail -- elle confronte, troncon par
troncon, la largeur **mesuree** a la largeur **normative**, et
[dsr_rapport()] rend la section correspondante via son nouvel argument `norme`.

Le sens de lecture est fixe et ne s'inverse pas : la mesure informe sur ce que
la norme suppose. Ramener la mesure vers la norme detruirait le signal que le
paquet produit, la fiche rendant une constante de 2 m sur toute la desserte
forestiere.

La sortie porte `BORDS_RESOLUS`, la part de stations ou la rupture
chaussee/accotement a ete tranchee. Sans elle, l'ecart comparerait une
**plateforme** a une largeur de **chaussee** sans le dire : le rapport signale
alors qu'il se lit comme un majorant. Les troncons que la fiche n'apparie pas
sont conserves avec un ecart `NA` plutot que retires -- et quand aucun ne
s'apparie, cas courant en foret ou le classement administratif est vide, la
section le dit au lieu de rester muette.

## La fiche Certu lit les millesimes recents de la BD TOPO

[dsr_emprise_certu()] echouait sur l'extrait BD TOPO **livre avec le paquet** :
les millesimes recents nomment le classement administratif
`cpx_classement_administratif`, absent des alias de detection. Il est ajoute
(avec `classement_administratif`).

`champs` **complete** desormais la detection au lieu de la remplacer. Forcer le
seul champ qui manque obligeait a redonner les quatre autres, sans quoi la
fonction declarait introuvables des colonnes bien presentes. Les noms forces
sont verifies a l'entree : un role inconnu ou une colonne absente echoue tout de
suite, avec la liste des noms attendus.

Le message de champ manquant nommait enfin **les mauvais champs** : les noms
etaient recycles a cote des positions testees, et l'appel signalait `cl_admin`
et `nb_voies` quand seul `cl_admin` manquait.

Rien de tout cela ne change une largeur : la fiche reste une **lecture d'ecart a
la norme**, jamais une reference de calibration.

## Un exemple de bout en bout sur desserte existante

`dev/11_chaine_desserte_existante.R` deroule les dix etapes du cas d'usage
central -- corridor, deux canaux, recalage contraint, etat, mesure, gabarit
libre, praticabilite, ecart Certu, detection hors reference, reseau, export --
sur l'extrait de `inst/extdata`. Contrairement a `dev/03_validation.R`, il ne
demande **aucune donnee externe** : il s'execute tel quel. C'est un exemple de
reference, pas une validation ; 200 m de desserte ne valident rien.

## La calibration devient reproductible

[dsr_calibrer_specs()] accepte `graine` (defaut 1) : deux appels sur la meme
donnee rendent desormais **les memes regles**.

L'AUC y est estimee sur un echantillon de `n` cellules, et l'ecart-type du
tirage vaut environ **0,006** -- assez pour faire entrer ou sortir du jeu un
canal pose au bord de `auc_min`. Une fonction de calibration dont la sortie
bouge a entree constante ne vaut pas grand-chose, et c'etait la derniere source
d'aleatoire du paquet.

`graine = NULL` restaure le comportement precedent, utile pour **mesurer** la
variabilite d'echantillonnage plutot que de l'ignorer. Dans tous les cas l'etat
du generateur de l'appelant est sauvegarde et restaure : poser une graine dans
une fonction de paquet sans la rendre casserait la reproductibilite du code
appelant, ce qui serait pire que le probleme resolu.

**Le harnais de tests est graine aussi** (`tests/testthat/setup.R`). Sans cela,
la **couverture** elle-meme n'etait pas deterministe : selon le tirage, une
branche etait exercee ou non, et codecov rapportait jusqu'a **-0,74 %** sur des
commits ne touchant aucune ligne de R. La suite rend maintenant un nombre
d'assertions **constant** a chaque passage (753 a ce jour), la ou il oscillait
entre 646 et 647.


## Le banc du canal optique passe par `dsr_ortho_ign()`

`dev/05_canaux.R` portait sa propre copie de la requete WMS Geoplateforme.
Elle est retiree au profit de [dsr_ortho_ign()]. Un banc qui reimplemente ce
qu'il est cense exercer ne le valide pas, et la copie avait deja diverge :
elle ne reparait pas le CRS absent -- piege documente du service -- et ne
nommait pas les bandes.

**Ce que la mesure a rendu au passage.** Le NDVI etait jusqu'ici juge sur le
`ndvi.tif` des caches, un produit a **4,4 m** ou une chaussee de 4 m tient dans
un pixel. Acquis a sa resolution nominale de **20 cm** (5000 x 5000 px, 39 s),
il passe de 0,534 a **0,560** d'AUC route / hors-route.

**+0,026.** La faiblesse du canal optique n'etait donc **pas** un artefact de
resolution : mesure a son echelle utile, le NDVI reste loin derriere la
`rugosite` (0,779), `sigma_geo` (0,715) et `openness_pos` (0,663). Il faut le
savoir avant d'investir dans l'acquisition d'ortho a 20 cm en esperant un gain.



# dessertR 1.2.0

Version de **l'instrument avant la mesure**. La 1.1.0 corrigeait des reglages
supposes ; celle-ci s'en prend a ce qui rendait ces reglages inmesurables.

Le fil conducteur est une decouverte desagreable : plusieurs conclusions de la
1.1.0 reposaient sur des mesures que l'outil ne pouvait pas porter.

* **Le vectoriseur par agent n'etait pas deterministe.** A entrees identiques,
  seul l'ordre des amorces changeant, le F1 variait de 13 % sur un massif et
  **43 % sur l'autre**. Un balayage de parametre y mesurait l'ordre de
  traitement, pas le parametre. L'ecart-type est desormais **exactement nul**.
* **L'agent sabotait ses propres amorces** : jusqu'a 19 sur 26 mouraient avant
  d'avoir avance d'un pas, parce que le reseau deja decouvert etait rendu
  infranchissable jusque sous leur point de depart.
* **L'AUC etait aveugle a un defaut d'echelle.** Des bornes transportees d'un
  massif a l'autre effondraient le contraste route / fond d'un facteur soixante
  sans que l'AUC, invariante d'echelle, n'en montre rien. C'est ce defaut qui se
  presentait comme un « ecart entre massifs » attribue au terrain.

Deux defauts de valeur ont par ailleurs ete corriges a la mesure : `rugosite`
etait declaree **a l'envers** (+0,175 d'AUC sur les deux massifs, le defaut
precedent passant sous le hasard sur l'un d'eux), et `franchissabilite_min`
etait pose dans la seule fenetre ou l'agent divague.

Enfin, [dsr_calibrer_specs()] rend desormais le **relief** a cote des signes,
sans stratifier : les canaux qui s'inversent entre plaine et montagne sont
exactement ceux qui situent la route dans la forme generale du paysage, et c'est
une prediction que le troisieme massif pourra refuter.

Trois defauts de comportement changent (`rugosite`, `franchissabilite_min`,
determinisme de l'agent), aucune API n'est cassee. Le detail suit, avec les
chiffres.

## La calibration rend desormais le terrain a cote des signes

[dsr_calibrer_specs()] rend deux elements de plus : `par_massif`, la mesure
brute avant agregation, et `terrain`, des descripteurs de relief mesures sur la
pile fournie (`pente_med`, `pente_p90`, `rugosite_med`, `relief_iqr`). Aucun
defaut ne change, aucun calcul n'est ajoute -- les descripteurs sortent des
canaux deja presents.

**Pourquoi.** Le test `stable` ecarte les canaux dont le sens differe d'un
massif a l'autre. C'est prudent, mais ca jette de l'information reelle :
`pente` discrimine a 0,61 sur **les deux** massifs de validation, simplement
dans des sens opposes. L'hypothese naturelle -- ces signes sont stables **a
l'interieur d'une classe de relief** -- n'est pas tranchable avec deux massifs :
il en faudrait au moins deux par classe, sans quoi on calibrerait une
classification sur un seul echantillon, exactement l'erreur que cette fonction
existe pour eviter. On instrumente donc, sans stratifier.

**Une regularite apparait, et elle est falsifiable.** Les canaux qui s'inversent
sont exactement ceux qui situent la route dans la forme GENERALE du paysage ;
ceux qui restent stables decrivent la route ELLE-MEME :

| canal | ltcp (pente med. 2,2 deg) | wsfi (22,3 deg) |
|---|---|---|
| `pente` | +1 (0,610) | **-1** (0,607) |
| `slrm` | +1 (0,571) | **-1** (0,547) |
| `rugosite` — texture | +1 (0,744) | +1 (0,759) |
| `openness_neg` / `openness_pos` / `svf` — forme du voisinage | -1 | -1 |
| `vesselness` — linearite | +1 (0,578) | +1 (0,612) |

En montagne, une route suit le moindre pendage : elle est **moins** pentue que
son environnement. En plaine, il n'y a pas de pendage a suivre, et ce qui la
marque est sa forme construite -- bombement, fosses -- donc **plus** pentue
qu'un terrain plat. Les autres canaux decrivent la route et non sa place dans le
paysage.

Deux massifs n'etablissent pas une loi. Mais la prediction est nette et
refutable, et elle reduit beaucoup le probleme : si elle tient, **seuls `pente`
et `slrm` demandent un conditionnement au terrain** -- pas les cinq autres.

Les quatre descripteurs sont rendus a dessein : rien ne dit d'avance lequel
predit les inversions, et sur deux massifs ils se separent tous d'un facteur 3
a 10. C'est aux donnees de trancher, quand il y en aura.


## Le vectoriseur par agent devient deterministe

Le reseau decouvert ne se met plus a jour qu'**entre** les tours, jamais au sein
d'un tour. Tous les agents d'un meme tour voient donc le meme etat, et le
resultat ne depend plus de l'ordre des amorces.

**Le defaut, mesure.** Avec une mise a jour au fil de l'eau, chaque reussite
modifiait l'entree des amorces suivantes. Memes entrees, seul l'ordre des
amorces change, 8 tirages :

| | wsfi | ltcp |
|---|---|---|
| F1 | 0,454 - 0,517 (**±13 %**) | **0,299 - 0,470 (±43 %)** |
| precision | 0,607 - 0,782 (±26 %) | **0,398 - 0,797 (±68 %)** |
| km produits | ±26 % | **±55 %** |

L'ordre des amorces n'a aucune signification physique. **Un balayage de
parametre sur ltcp mesurait donc l'ordre de traitement, pas le parametre** : le
balayage de `franchissabilite_min` y couvrait 0,248 a 0,319, entierement a
l'interieur de ce bruit. Apres correction, l'ecart-type sur les 8 ordres est
**exactement nul** sur les deux massifs et sur toutes les metriques.

**Ce que ca change sur la qualite.** Les agents d'un meme tour ne s'arretent
plus les uns les autres, donc ils vont plus loin :

| | wsfi avant | wsfi apres | ltcp avant | ltcp apres |
|---|---|---|---|---|
| rappel | 0,381 | **0,442** | 0,287 | **0,481** |
| precision | 0,607 | **0,640** | **0,817** | 0,489 |
| ecart median | 3,20 m | **2,82 m** | **1,79 m** | 5,41 m |
| F1 | 0,468 | **0,523** | 0,425 | **0,485** |

Sur wsfi, mieux sur **tout**. Sur ltcp, c'est un arbitrage assume : rappel
+68 %, mais precision -40 % et ecart median de 1,79 a 5,41 m.

**Reserve sur cette mesure, a charge.** Le banc retire deliberement la reference
comme barriere -- il demande a l'agent de la retrouver, il ne peut donc pas la
lui donner. Le chemin nominal, lui, passe la reference comme reseau
infranchissable des le premier tour : la surproduction mesuree ici est en partie
un artefact du protocole, d'une ampleur que nous ne pouvons pas chiffrer faute
de verite terrain hors reference.

Le determinisme, lui, est acquis sans reserve -- et c'est un **prerequis** :
sans lui, aucun reglage n'est mesurable, ce que ce cycle a appris a ses depens.

Les doublons d'un meme tour sont retires par [dsr_dedupe_paralleles()], qui trie
par longueur decroissante et reste donc lui aussi independant de l'ordre.
Largeur reglable par `dedupe_largeur` (defaut 3 m).


## L'ecart entre massifs venait surtout du protocole de mesure

ltcp rendait systematiquement bien moins que wsfi (F1 0,30 contre 0,48 ; rappel
0,21 contre 0,39), et l'explication naturelle etait un massif plus difficile --
plaine, faible relief, empreinte geomorphologique tenue. **Les deux tiers de
l'ecart venaient du protocole.**

**Le mecanisme.** Les harnais calibrent sur un massif DISJOINT pour eviter la
circularite, ce qui est juste. Mais depuis que [dsr_calibrer_specs()] rend des
bornes absolues, ils transportaient aussi les **bornes**. Or une borne est dans
l'unite du canal : celles d'une plaine appliquees a une montagne poussent tout
au plafond, et inversement.

| massif | bornes | mediane | contraste route / fond | AUC |
|---|---|---|---|---|
| wsfi | croisees | 0,578 | **+0,003** | 0,658 |
| wsfi | propres | 0,101 | **+0,176** | 0,776 |
| wsfi | sans bornes, croise | 0,252 | +0,140 | 0,708 |
| ltcp | croisees | 0,087 | **+0,017** | 0,643 |
| ltcp | propres | 0,112 | **+0,112** | 0,693 |
| ltcp | sans bornes, croise | 0,192 | +0,115 | 0,682 |

**L'AUC etait aveugle au defaut.** Elle bouge de quelques centiemes la ou le
contraste est divise par **six a soixante**. C'est un critere de RANG, donc
invariant d'echelle : elle survit intacte a l'effondrement du contraste. L'agent,
lui, consomme des **valeurs** -- son cout admissible vaut
`portee / conductivite_min` -- et divague des que l'echelle se deplace. Juger une
carte a la seule AUC masque cette classe de defaut.

**L'effet une fois corrige**, agent amorce par la reference, calibration croisee
avec `bornes = FALSE` :

| protocole | massif | rappel | precision | ecart median | F1 |
|---|---|---|---|---|---|
| bornes croisees | wsfi | 0,336 | 0,622 | 2,62 m | 0,437 |
| bornes croisees | ltcp | 0,208 | 0,556 | 4,06 m | 0,303 |
| **sans bornes** | wsfi | 0,381 | 0,607 | 3,20 m | **0,468** |
| **sans bornes** | ltcp | **0,287** | **0,817** | **1,79 m** | **0,425** |

L'ecart entre massifs tombe de **0,134 a 0,043**, et l'ecart median de ltcp
descend a **1,79 m -- meilleur que wsfi**. Ce massif n'est pas intrinsequement
difficile.

**Le garde-fou.** [dsr_conductivite()] et [dsr_sigma_surf()] signalent desormais
les canaux dont l'appartenance sature a plus de 80 % d'un seul cote, ce qui est
la signature de bornes etrangeres a la donnee. Le controle ne porte que sur les
bornes **explicites** : avec des bornes quantilees, la saturation est
structurelle et non un defaut. Silence par
`options(dessertR.verifier_bornes = FALSE)`.

`dev/04` et `dev/07` passent a `bornes = FALSE`, leur calibration etant croisee.

**Ce qui reste.** Un ecart residuel, bien plus petit, coherent avec le relief :
pente mediane **2,3 deg sur ltcp contre 23,3 deg sur wsfi**. Une route de plaine
laisse moins d'empreinte, et c'est une limite physique, pas un reglage.


## `franchissabilite_min` passe de 0,4 a 0,45

Le defaut etait pose dans la seule zone de l'intervalle ou l'agent divague.

**Pourquoi rejouer le balayage.** Le premier passage avait conclu au maintien de
0,4. Deux lots l'ont invalide depuis : [dsr_calibrer_specs()] rend des bornes
absolues, donc `sigma_geo` et le seuil derive de sa distribution ne sont plus
les memes ; et surtout [dsr_conduire()] ne tue plus les amorces posees sur le
reseau deja decouvert. **Le premier passage comparait des seuils sur un agent
qui perdait 19 amorces sur 26 sur ltcp**, et dont le resultat dependait de
l'ordre de traitement. Ses conclusions chiffrees etaient sans valeur.

**Le F1 ne tranche pas.** Neuf seuils, deux massifs
(`dev/07_calibrer_franchissabilite.R`) : une fois lisse, le F1 moyen tient entre
**0,355 et 0,367** sur toute la plage. Le profil est *chaotique* -- un petit
deplacement du seuil change quelles amorces aboutissent, et la cascade se
propage par le reseau accumule. Prendre l'argmax d'un tel profil serait du
surajustement, et c'est d'ailleurs ce qui faisait « preferer » 0,55 a ltcp et
0,40 a wsfi.

**C'est l'ecart a la reference qui tranche :**

| seuil | ecart median wsfi | ecart median ltcp | moyenne |
|---|---|---|---|
| 0,375 | 2,27 m | **13,37 m** | 7,82 m |
| **0,40 (ancien defaut)** | 2,57 m | **12,91 m** | **7,74 m** |
| **0,45 (nouveau)** | 2,62 m | **4,06 m** | **3,34 m** |
| 0,50 | 2,24 m | 6,93 m | 4,58 m |
| 0,55 | 2,86 m | 4,58 m | 3,72 m |

Sur ltcp l'ecart vaut 4 a 7 m partout **sauf entre 0,375 et 0,40**, ou il
explose a 13 m -- juste au-dessus du mode, la ou le plancher ecrase le contraste
sur les deux tiers de la carte et laisse l'agent divaguer. L'ancien defaut
etait dans cette fenetre etroite. 0,45 en sort au premier cran, **sans rien
couter sur wsfi** (2,62 contre 2,57 m) et en divisant l'ecart moyen par deux.

**Une regle enoncee en 1.1.0 ne survit pas.** Elle disait « ce qui compte est le
cote du mode : au-dessus, l'ecart tombe a 2-3 m sur les deux massifs ». C'etait
mesure sur l'agent defaillant. Corrige, `sigma_surf` inchange, l'affirmation est
fausse sur ltcp : juste au-dessus du mode est precisement le pire endroit. Le
mecanisme du mode (il vient du calcul, pas du terrain) reste valide, lui -- il
ne depend pas de l'agent.


## L'agent sabotait ses propres amorces

[dsr_conduire()] rendait le reseau deja decouvert infranchissable **y compris
sous le point de depart de l'amorce suivante**. Comme les amorces viennent du
reseau de reference et que le reseau decouvert le recouvre par construction,
**plus l'agent reussissait tot, plus il tuait ses amorces suivantes**.

**Le diagnostic.** Le motif d'arret le disait, encore fallait-il le regarder :
sur ltcp, **19 amorces sur 26** mouraient en `depart_infranchissable` sans avoir
avance d'un seul pas, et **32 sur 54** sur wsfi. Le chiffre etait *identique avec
et sans contrainte de franchissabilite* -- ce qui disqualifie l'explication
retenue jusqu'ici, qui attribuait le deficit de rappel a une contrainte trop
serree.

**La correction.** Un trou de la taille du `tampon` dans le masque du reseau,
autour du point de **depart fige** -- pas de la position courante, sinon le
reseau deviendrait franchissable partout et la detection de jonction tomberait.
La jonction se joue de toute facon a `portee` metres devant, tres au-dela du
trou. C'est la symetrie de ce que le code faisait deja pour la trace de l'agent
lui-meme.

**Mesure A/B**, code identique au correctif pres, agent amorce par la reference :

| | amorces mortes | routes | km | rappel | precision | F1 |
|---|---|---|---|---|---|---|
| wsfi sans | 32 / 54 | 17 | 4,21 | 0,335 | 0,661 | 0,445 |
| wsfi **avec** | **0** | 26 | 5,45 | **0,390** | 0,637 | **0,484** |
| ltcp sans | 19 / 26 | 6 | 2,51 | 0,175 | 0,306 | 0,223 |
| ltcp **avec** | **0** | 18 | 3,55 | **0,213** | 0,322 | **0,257** |

Rappel **+16 % sur wsfi et +22 % sur ltcp**, F1 +9 % et +15 %, precision quasi
inchangee.

**Le cout, et ce qui n'est pas resolu.** L'ecart median a la reference se
degrade sur ltcp (9,36 -> 12,91 m) : les amorces reanimees produisent aussi du
lineaire plus eloigne. Et le deficit de rappel de ltcp est **reduit, pas
supprime** -- il reste tres en dessous de wsfi.

Ce defaut expliquait par ailleurs l'instabilite des mesures sur ltcp d'un
passage a l'autre : le resultat dependait de l'ordre de traitement des amorces,
puisque chaque reussite condamnait les suivantes.


## `rugosite` etait utilisee a l'envers dans les regles par defaut

[dsr_specs_geomorpho()] declare desormais `rugosite` **croissante**. Le canal le
plus discriminant du jeu etait utilise a l'envers depuis l'origine.

**Le constat n'est pas neuf, la condition pour agir l'est.** La 1.0.0 avait
mesure l'inversion, et avait choisi de ne PAS toucher au defaut : figer un signe
qu'un troisieme jeu pourrait dementir aurait reproduit l'erreur qu'on venait de
corriger. Trois jeux concordent maintenant -- wsfi, ltcp, et une dalle Lozere
mesuree independamment par l'audit ForetAccess -- et la calibration conjointe
rend `stable = TRUE`.

| massif | AUC `rugosite` | sens |
|---|---|---|
| wsfi (1,5 km2) | 0,759 | +1 |
| ltcp (1,5 km2) | 0,744 | +1 |
| conjoint | **0,753** | **+1, stable** |

**Ce que la correction rapporte**, AUC route / hors route de `sigma_geo` avec
les regles par defaut :

| massif | avant | apres |
|---|---|---|
| wsfi | 0,530 | **0,705** |
| ltcp | **0,479** | **0,654** |

**+0,175 sur chacun**, gain identique. A noter : sur ltcp le defaut precedent
tombait **sous le hasard** -- il n'etait pas seulement inutile, il degradait.

**Pourquoi l'intuition trompait.** Une route est censee etre lisse. A 50 cm de
resolution c'est faux : une piste empierree a ornieres est plus rugueuse qu'un
versant forestier localement plan, et dans une fenetre de quelques cellules
c'est le profil en travers -- fosse, talus, devers -- qui domine, pas l'etat de
la chaussee.

**Les autres signes sont inchanges.** `pente` et `slrm` s'inversent d'un massif
a l'autre (`stable = FALSE`) et n'ont rien a faire dans un defaut.
`openness_neg` mesure `-1` sur les deux massifs, mais `+1` sur la dalle Lozere
-- qui recouvre wsfi -- avec une AUC de 0,527 la ou le signe se decide : trop
proche du hasard pour trancher. Il reste `croissante`.

Ces regles restent un point de depart ; [dsr_calibrer_specs()] demeure le chemin
recommande.


## La faiblesse de `sigma_surf` n'est pas un artefact de calcul

Resultat **negatif**, et il ferme une piste que le cycle precedent laissait
ouverte. Aucun changement de code : seulement une hypothese testee et abandonnee.

**L'hypothese.** La version 1.1.0 constatait que les bornes quantilees saturent
la moitie de `sigma_surf` -- `mu(taux_penetration) = 0` et
`mu(densite_sousetage) = 1` par construction -- et suggerait que son AUC
mediocre (0,578 et 0,607) pourrait n'etre qu'un artefact de cette saturation.
[dsr_calibrer_specs()] rendant desormais des bornes absolues, l'hypothese
devenait testable (`dev/09_bornes_surface.R`).

| massif | regles | AUC `sigma_surf` | saturation |
|---|---|---|---|
| wsfi | defaut | 0,583 | 50,1 % |
| wsfi | calibre nu, croise | 0,528 | 30,4 % |
| wsfi | calibre + bornes, croise | 0,524 | 31,7 % |
| wsfi | calibre + bornes, *propre* | 0,577 | 58,3 % |
| ltcp | defaut | 0,599 | 34,0 % |
| ltcp | calibre nu, croise | 0,613 | 57,3 % |
| ltcp | calibre + bornes, croise | 0,604 | 23,5 % |
| ltcp | calibre + bornes, *propre* | **0,645** | 43,1 % |

**La saturation n'explique rien.** Sur wsfi, la faire tomber de 50,1 % a 31,7 %
fait *baisser* l'AUC a 0,524 ; et le meilleur reglage du massif (0,577) est
celui ou elle *monte* a 58,3 %. Les deux grandeurs ne sont pas liees.

**Et le plafond est bas.** Le protocole « propre » calibre sur le massif
lui-meme, donc les regles ont vu les reponses : c'est un majorant optimiste,
pas une mesure. Meme la, le gain est nul sur wsfi (-0,006) et modeste sur ltcp
(+0,045).

**Les bornes ne se transportent pas**, comme annonce en 1.1.0 : calibrees sur
l'autre massif elles coutent -0,059 sur wsfi. Une borne est dans l'unite du
canal, et `taux_penetration` brut differe d'un facteur 7 entre les deux
massifs. Le protocole croise est le seul honnete, et c'est le moins bon.

**Conclusion.** La faiblesse de `sigma_surf` pour LOCALISER une route est
physique, pas computationnelle -- coherent avec ce qui etait deja etabli sur
`densite_sousetage` : ce canal mesure un **etat**, et on lui pose la mauvaise
question en lui demandant ou est la route. Inutile d'investir davantage dans
son reparametrage ; le levier est ailleurs.


# dessertR 1.1.0

Version de la **mesure contre l'intuition**. Quatre reglages qui reposaient sur
un raisonnement physique plausible mais jamais verifie ont ete confrontes a deux
massifs Lidar HD, et trois d'entre eux se sont reveles faux :

* le canal de surface pesait **quatre fois trop lourd** dans la detection -- son
  ancien poids etait la pire valeur de tout l'intervalle testable, moins bonne
  que retirer le canal ;
* `densite_sousetage`, presente comme le signal qui justifiait a lui seul
  l'ajout du nuage de points, ne discrimine pas la **presence** d'une route --
  il mesure un etat, et une route recolonisee reste une route ;
* la detection **dependait de l'etendue analysee** : le meme terrain rendait
  1727 m ou 2328 m de desserte selon la taille de la fenetre soumise.

Aucune de ces corrections n'a demande de nouvelle donnee : seulement de mesurer
ce qui etait suppose. Le quatrieme reglage, le seuil de franchissabilite, a
survecu a son balayage -- mais pour une raison differente de celle qu'on lui
pretait.

Deux defauts de comportement changent (`poids` du canal de surface,
[dsr_calibrer_specs()] qui rend desormais des bornes), et trois entrees d'API
s'ajoutent ([dsr_c_vessel()], `franchissabilite`, `c_vessel`). Le detail suit,
avec les chiffres.

## La detection ne depend plus de l'emprise qu'on lui passe

Signale par un audit ForetAccess sur le commit `cb9376c` : `dsr_detecter()`
rendait des resultats **differents pour le meme terrain** selon l'etendue du
raster soumis. Le `seuil` n'etait pas une quantite absolue mais un **rang dans
la population de l'emprise fournie** -- donc deux sites d'etendues differentes
n'etaient pas comparables, et le regime `corridor`, qui restreint l'emprise,
changeait le bareme du chantier.

**Deux causes independantes, aucune suffisante seule.**

1. [dsr_appartenance()] derive ses bornes des quantiles de la donnee recue
   quand `a`/`b` ne sont pas fournis -- et ni [dsr_specs_geomorpho()] ni
   [dsr_specs_surface()] ne les fournissent jamais.
2. `dsr_frangi()` derive son `c` du maximum de la norme de Frobenius du Hessien
   **de l'image**. Celui-ci agit **en amont** des fonctions d'appartenance :
   aucune borne ne peut le rattraper. Mesure sur wsfi, `c` derive sur 3,12 km2
   contre 0,25 km2 : **x1,65 / x2,14 / x2,27** aux echelles 1 / 2 / 4 m.

**Les corrections.**

- [dsr_c_vessel()] (nouveau) calcule le `c` d'une emprise de reference, une
  valeur par echelle. [dsr_vesselness()] accepte desormais un vecteur en plus
  du scalaire, et [dsr_layers_dtm()] le relaie via `c_vessel`. Un scalaire
  unique ne convient pas : `c` varie de **x3,20** entre les echelles d'un meme
  site, et l'aplatir fausserait la selection du maximum multi-echelle.
- [dsr_calibrer_specs()] rend maintenant les bornes `a` et `b` avec les regles
  (`bornes = TRUE`), en unites du canal. La rampe va du typique de
  l'environnement au franchement routier : `croissante` -> `a` = q50(absence),
  `b` = q75(presence) ; `decroissante` -> `a` = q25(presence), `b` = q50(absence).
  Les quantiles sortent de la boucle qui calcule deja l'AUC, donc sans surcout.

**La preuve** (`dev/08_ancrage_emprise.R`, wsfi, fenetre de 0,25 km2 comparee a
elle-meme vue depuis 3,12 km2, interieur hors marge de bord) :

| reglage | ecart max sur `sigma_geo` | lineaire detecte, fenetre vs bloc |
|---|---|---|
| aucun ancrage (etat audite) | 2,6e-01 | 1727 m vs 2328 m (**26 % d'ecart**) |
| bornes seules | 1,9e-01 | — |
| `c` seul | 2,3e-01 | — |
| **bornes + `c`** | **2,1e-14** | **2552 m vs 2552 m (0 %)** |

A la precision machine. Et les deux corrections sont bien necessaires : chacune
prise seule laisse un ecart de l'ordre de 0,2 sur `sigma_geo`.

**Ce que ca change en pratique.** [dsr_calibrer_specs()] devient suffisant a lui
seul pour produire des regles absolues, ce qui etait sa vocation affichee. Une
reserve demeure : une borne est dans l'unite du canal et ne se transporte pas
forcement d'un massif a l'autre -- le taux de penetration brut varie d'un
facteur 7 entre les deux massifs de validation. Avec plusieurs massifs les
bornes sont medianes, et **calibrer sur les massifs qu'on va effectivement
traiter reste la bonne pratique**.

`bornes = FALSE` restaure l'ancien comportement, relatif a l'emprise.

**Interaction avec le lot suivant, a lire.** Le seuil `franchissabilite_min` de
[dsr_conduire()] vaut 0,4 parce qu'il se place juste au-dessus du mode que les
bornes **quantilees** creent dans `sigma_surf` (section suivante). Calibrer les
regles de SURFACE avec `bornes = TRUE` et les passer a [dsr_sigma_surf()]
deplace ce mode et **invalide le defaut de 0,4**. Le cas ne se presente pas par
defaut -- [dsr_specs_surface()] reste sans bornes, et calibrer le canal de
surface a de toute facon ete mesure comme contre-productif -- mais qui le fait
doit recalibrer son seuil.


## Le seuil de franchissabilite est un critere de rang deguise

`franchissabilite_min` reste a **0,4**, mais on sait desormais pourquoi il
marche -- et ce n'est pas ce que son nom annonce.

**Le balayage.** Huit seuils, deux massifs (`dev/07_calibrer_franchissabilite.R`) :

| seuil | F1 wsfi | F1 ltcp | ecart median wsfi | ecart median ltcp |
|---|---|---|---|---|
| aucune contrainte | 0,351 | 0,289 | 5,17 m | 16,13 m |
| 0,30 | 0,382 | 0,346 | 5,06 m | 3,42 m |
| 0,35 | 0,358 | **0,369** | 4,54 m | 2,73 m |
| 0,365 | 0,362 | 0,313 | 4,39 m | 11,18 m |
| 0,375 | **0,459** | 0,338 | 2,67 m | 2,97 m |
| **0,40** | 0,444 | 0,350 | 2,40 m | 2,06 m |
| 0,45 | 0,442 | 0,359 | 3,13 m | 2,31 m |
| 0,50 | 0,418 | 0,331 | 2,62 m | 3,52 m |
| 0,60 | 0,413 | 0,319 | 2,12 m | 3,33 m |

Entre 0,375 et 0,45 les F1 sont indiscernables (ltcp ne produit que 3 a 6
lignes : ces chiffres sont instables). **Ce qui compte n'est pas la valeur mais
le cote du mode** de `sigma_surf` : au-dessus, l'ecart median tombe a 2,1-3,1 m
sur les deux massifs ; en dessous il remonte a 4,4-11,2 m.

**Le mode vient du calcul, pas du terrain.** [dsr_specs_surface()] laisse ses
bornes d'appartenance a `NULL`, donc [dsr_appartenance()] les derive des
quantiles : `a` = mediane, `b` = 95e centile. Par construction, la moitie des
cellules ont donc `mu(taux_penetration) = 0` -- ramene au plancher `sigma_min`
-- et `mu(densite_sousetage) = 1`. Leur fusion vaut
`exp((2*log(1) + log(0,05))/3) = 0,368`, et c'est bien la que se concentre la
masse : **50 % des cellules sur wsfi, 34 % sur ltcp**.

Le seuil de 0,4 se pose juste au-dessus. Il ne mesure donc pas une fermeture de
sous-etage : il retient les cellules dont le **taux de penetration depasse sa
propre mediane**. Physiquement : ne pas circuler la ou le lidar ne voit pas le
sol -- ce qui est raisonnable, mais n'est pas ce que le parametre annonce.

**Deux consequences.** La bonne : le seuil se transporte bien mieux qu'un seuil
absolu ne le devrait. Le taux de penetration brut vaut **0,04 sur wsfi et 0,31
sur ltcp**, un facteur 7, et le meme 0,4 convient aux deux -- la normalisation
par quantiles absorbe l'ecart en amont. Le doute consigne au cycle precedent
(« le seuil frole un mode susceptible de se deplacer ») tombe : le mode est au
meme endroit sur tout massif.

La genante : fixer `a` et `b` explicitement dans `specs` deplace le mode et
**invalide le defaut de 0,4**. C'est documente dans [dsr_conduire()].

**Une piste ouverte au passage.** Si la moitie de `sigma_surf` est saturee par
construction, le canal porte beaucoup moins d'information qu'il n'y parait --
et c'est une explication candidate a son AUC mediocre (0,578 et 0,607). Des
bornes d'appartenance calees plutot que quantilees sont a instruire.

**Ce qui a ete essaye et rejete.** Exprimer le seuil en quantile plutot qu'en
valeur absolue, pour le rendre robuste par construction. La parametrisation est
**degeneree** : entre les seuils 0,365 et 0,375, le quantile correspondant saute
de 0,183 a 0,685 sur wsfi et de 0,304 a 0,645 sur ltcp. Les quantiles 0,2 a
0,69 pointent tous sur la meme valeur ; un seuil ne s'adresse pas par quantile
ici.

Calibrer le seuil sur une verite d'ETAT a egalement ete envisage, puis abandonne
faute de matiere : sur les deux fenetres, OSM ne porte **aucun** tag de cycle de
vie (`abandoned:`/`disused:`/`razed:highway` : zero) et quasiment aucun attribut
de praticabilite (`surface` 0 et 1 voie, `tracktype` 0 et 5, sur 25 et 14
voies). Le parametre se regle contre la metrique qui compte -- ce que l'agent
retrouve de la reference -- sans avoir besoin de cette verite.


## L'agent suit une carte et se fait arreter par une autre

[dsr_conduire()] accepte `franchissabilite` (+ `franchissabilite_min`, defaut
0,4) : un raster, typiquement [dsr_sigma_surf()], qui ne dit pas ou est la
route mais **ou l'on ne passe plus**. [dsr_detecter()] le transmet
automatiquement quand `sigma_surf` est fourni et que la methode est l'agent.

**Ce qui l'a rendu necessaire.** Ramener le poids du canal de surface de 2 a
0,5 ameliore la carte (AUC 0,698 -> 0,738) et le vectoriseur par squelette avec
elle, mais degradait l'agent. La cause, mesuree : l'ancien poids ecrasait la
carte partout ou le sous-etage est ferme, ce qui **retenait** l'agent. Un
garde-fou reel, mais accidentel -- une ponderation de DETECTION jouait une
regle de FRANCHISSABILITE, et se payait d'une carte degradee.

Rendue explicite, la contrainte fait mieux que restaurer l'ancien
comportement. Sur deux massifs, agent amorce par la reference, meme `sigma_geo`
et meme `sigma_surf` :

| | rappel | precision | ecart median | F1 |
|---|---|---|---|---|
| **wsfi** — poids 2, couple | 0,342 | 0,577 | 3,34 m | 0,429 |
| poids 0,5, sans contrainte | 0,273 | 0,492 | 5,17 m | 0,351 |
| poids 0,5 + franchissabilite | 0,317 | **0,740** | **2,40 m** | **0,444** |
| **ltcp** — poids 2, couple | 0,321 | 0,509 | 4,64 m | **0,394** |
| poids 0,5, sans contrainte | 0,232 | 0,381 | 16,13 m | 0,289 |
| poids 0,5 + franchissabilite | 0,224 | **0,800** | **2,06 m** | 0,350 |

La derive positionnelle est corrigee sur les deux massifs, et spectaculairement
sur ltcp (16,1 m -> 2,1 m). La precision monte de 28 et 57 points relatifs.

**Ce qui n'est pas resolu, et qu'il faut lire avant de s'y fier.** Sur ltcp le
F1 reste sous le montage couple d'origine (0,350 contre 0,394) : la contrainte
y coupe le rappel, la production tombant de 2,91 a 1,28 km.

*(Mise a jour apres `dev/07` : le doute sur la fragilite du seuil, lui, est
leve -- voir la section suivante. Le deficit de rappel sur ltcp reste.)*

Le plancher est applique **sans** rendre les cellules infranchissables : un
`NA` interdirait a l'agent de traverser vingt metres de ronces pour retrouver
une piste degagee, et le hacherait a chaque fourre. C'est le mecanisme de
trouee (`trouee_max`) qui arbitre sur la longueur du passage difficile.


## Le canal de surface pesait quatre fois trop lourd dans la detection

[dsr_indice_detection()] et [dsr_detecter()] passent de `surf = 2` a
`surf = 0.5`. L'ancien defaut n'etait pas approximatif : mesure sur deux
massifs, il etait **la pire valeur de tout l'intervalle teste, moins bonne que
retirer le canal purement et simplement**.

AUC route / hors route de l'indice, 15 tirages par point, ecart-type 0,006
(`dev/06_calibrer_surface.R`) :

| poids `surf` | wsfi | ltcp |
|---|---|---|
| 0 (canal retire) | 0,715 | 0,667 |
| 0,25 | 0,734 | 0,682 |
| **0,5** | **0,739** | **0,684** |
| 1 | 0,727 | 0,679 |
| 2 (ancien defaut) | 0,697 | 0,666 |

Les deux massifs placent leur maximum au meme endroit. Bien dose, le canal
apporte un gain net -- +0,024 (4 ecarts-types) sur wsfi, +0,017 (2,8) sur ltcp
--, ce qui ecarte la conclusion paresseuse qui aurait ete de le supprimer.

**Ce que l'intuition avait mal lu.** Le raisonnement d'origine (BRIEF section
3.9) tenait qu'une piste se lit d'abord dans la discontinuite du sous-etage,
d'ou le poids double. Or `densite_sousetage` ne discrimine pas la presence
d'une route : AUC **0,535** et **0,521**, le hasard. Ce n'est pas une
defaillance du canal, c'est un malentendu sur la question qu'on lui pose. Il
mesure un **etat** -- emprise degagee ou recolonisee -- et une route
recolonisee reste une route. Un canal qui detecterait parfaitement la
recolonisation aurait une AUC de 0,5 sur la question « y a-t-il une route
ici ? ». Il garde donc toute sa valeur dans [dsr_etat()], ou c'est sa
divergence avec `sigma_geo` qui parle ; il n'en a guere pour localiser.

Le canal de surface reellement discriminant est `h_couvert` (AUC 0,660 sur
ltcp), qui marque les routes par une vegetation haute plus basse : il lit
l'ouverture de la canopee. C'est utile a faible poids, et c'est exactement
pourquoi il ne faut pas le laisser dominer -- une coupe rase ou une ligne
electrique l'allument autant qu'une route, soit le faux positif « trouee sans
route » que la table de divergence du BRIEF section 3.4 cherche a ecarter.

**Calibrer `sigma_surf` a ete essaye, et rejete.** Le reflexe, apres
[dsr_calibrer_specs()], etait d'appliquer la meme recette au canal nuage. La
mesure dit le contraire : les regles calibrees font tomber l'indice a 0,626 sur
wsfi et 0,658 sur ltcp, sous le jeu par defaut. La calibration donne le poids
fort a `h_couvert` et fabrique un detecteur de clairieres. Les signes de
[dsr_specs_surface()] sont d'ailleurs confirmes corrects par la mesure --
`densite_sousetage` decroissante, `taux_penetration` croissante. Contrairement
au canal geomorphologique, ou le signe de la rugosite etait inverse, **le
defaut de surface n'etait pas faux ; seule sa ponderation dans la fusion
l'etait.**


## Les regles de conductivite se calibrent au lieu de se supposer

[dsr_calibrer_specs()] mesure, canal par canal, ce qui distingue reellement une
route de son environnement sur **vos** donnees, et en deduit des regles
utilisables telles quelles par [dsr_conductivite()].

**Ce qui l'a rendue necessaire.** Les regles par defaut reposaient sur une
intuition physique jamais mesuree : une route est lisse, elle occupe un creux,
elle est lineaire. Confrontee a deux blocs Lidar HD, l'intuition sur la
rugosite est **fausse, et inversee** -- une piste empierree a ornieres est plus
rugueuse, a 50 cm, qu'un versant forestier localement plan. Le canal le plus
discriminant des deux jeux (AUC 0,78 et 0,68) etait donc utilise a l'envers, et
`openness_neg` avec lui. La conductivite qui en resultait tombait au niveau du
hasard :

| massif | regles par defaut | regles calibrees |
|---|---|---|
| wsfi (montagne, 4 dalles) | 0,523 | **0,787** |
| ltcp (25 dalles) | 0,531 | **0,688** |

Deux hypotheses ont ete testees et ecartees avant de conclure : un artefact de
densite de points sol (correlation rugosite / `densite_sol` : **-0,02**), et un
effet de bord capte par le tampon de mesure (a 1 m de l'axe, sur la chaussee
meme, l'AUC monte a **0,803**). Les routes forestieres sont bel et bien plus
rugueuses a 50 cm.

**Pourquoi une fonction plutot qu'un nouveau defaut.** Parce qu'un des canaux
n'est pas stable. La `pente` marque les routes par le bas sur wsfi et par le
haut sur ltcp : calibree sur un seul massif elle entre dans les regles,
calibree sur les deux elle en est ecartee. Figer un signe qu'un troisieme
massif pourrait dementir reproduirait l'erreur qu'on vient de corriger. La
fonction accepte donc **une liste de massifs** et ne retient un canal que si
son sens concorde partout -- le `diagnostic` porte une colonne `stable` qui le
dit.

Le diagnostic est rendu meme quand aucune regle n'est produite : savoir
qu'aucun canal ne discrimine est un resultat, et c'est ce qu'il faut lire avant
de s'etonner d'une detection mediocre.

La reference sert par sa POSITION seulement -- la BD TOPO convient, sa largeur
n'entre pas dans le calcul. Un reseau approximatif deplacerait les echantillons
« presence » hors de l'emprise reelle et calibrerait du bruit.

`dsr_specs_geomorpho()` est inchangee : le defaut reste le defaut, et il est
maintenant possible de le mesurer.


## Acquisition : OpenStreetMap et ortho IGN

Deux sources que le paquet ne produit pas mais dont il a besoin, entrees sans
aucune dependance nouvelle.

[dsr_osm()] telecharge les lineaires `highway`, **dalle par dalle** sur la
grille kilometrique du Lidar HD -- donc celle de [dsr_catalog()] et du reste du
traitement. Une requete unique sur un massif entier depasse les quotas et
echoue en bloc ; decoupee, elle devient une suite de requetes courtes dont
chacune est relancable, et une dalle qui echoue n'emporte pas les autres. Les
voies a cheval sur deux dalles sont dedupliquees par `osm_id`.

**Pourquoi c'est utile.** La question de [dsr_detecter()] -- « quelle desserte
la BD TOPO ignore-t-elle ? » -- n'a pas de verite terrain par construction. OSM
en couvre une partie : sur le bloc wsfi (4 km2), il porte 29,1 km contre 15,5 km
a la BD TOPO, et **56 % de ce lineaire est a plus de 20 m de toute route de la
reference**. C'est la premiere verite partielle disponible pour mesurer le
rappel de la detection. Avec la meme reserve que pour toute sortie d'un autre
algorithme : ni metre etalon de largeur, ni verite de position -- une part du
lineaire forestier y est tracee sur trace GPS agregee (`source=strava heatmap`).

[dsr_ortho_ign()] telecharge l'ortho IRC de la Geoplateforme **a sa resolution
native**, en tuilant la requete. Au-dela d'environ 4096 pixels de cote, un appel
unique force a degrader la resolution ; comme tout l'interet du canal optique
est d'etre a l'echelle d'une chaussee, on decoupe pour preserver le 20 cm.

Trois pieges du WMS, tous silencieux, tous rencontres et documentes : le service
**impose `VERSION=1.3.0`** ; en `EPSG:2154` l'ordre des axes est **(X, Y)** et un
BBOX inverse rend un GeoTIFF valide et **entierement vide** ; le GeoTIFF rendu
**n'a pas toujours de CRS**, ce qui fait sortir des `CRS do not match` a chaque
croisement ulterieur.

**Une lecon, chere.** Une instance Overpass saturee ne rend pas d'erreur : elle
rend un XML bien forme de quelques centaines d'octets, ou elle fait attendre.
Les deux cas ont ete pris pour « aucune donnee ici » pendant la validation --
la meme requete relancee rendait 194 ko. La rotation d'instances est reprise de
`foretaccess` (GPL-3), avec deux corrections qui la rendent effective :
`osmdata::osmdata_sf()` boucle en backoff au lieu d'echouer, donc une rotation
qui ne bascule que sur erreur n'est jamais atteinte, et `setTimeLimit()` n'y
change rien puisqu'il n'interrompt pas un socket bloque dans du C. Le backend
est donc `curl`, dont `--max-time` borne l'appel au niveau du processus. Une
reponse portant un `<remark>` est un refus et declenche la bascule ; une reponse
sans `<way>` ni `<remark>` est un vide legitime ; toutes instances refusant,
**on leve une erreur** plutot qu'un resultat vide.


## `dsr_layers_pc()` et `dsr_gabarit_libre()` acceptent plusieurs dalles

Leur garde testait `!file.exists(dalle)` dans un `if` : elle erre des que le
vecteur depasse un element (`'length = 4' in coercion to 'logical(1)'` sous
R >= 4.2), et la variante catalogue ne gardait que la **premiere ligne**,
silencieusement.

Consequence qui depasse la limitation : la strategie `concurrent_files`
introduite plus bas dans ce meme cycle ne pouvait **jamais** se declencher,
puisque `length(dalle)` valait toujours 1. Du code mort, documente comme
fonctionnel, qu'aucun test n'a vu parce qu'ils exercaient
`dsr_strategie_lasr()` isolement et jamais son integration.

Les deux fonctions passent par `dsr_valider_dalles()`, qui accepte un vecteur
ou un catalogue entier et nomme les fichiers manquants.


## Le vectoriseur ne depend plus de `vecnet`

`dsr_vectoriser()` s'appuyait, quand il etait installe, sur le paquet `vecnet`
(Roussel *et al.* 2023). Cette dependance posait trois problemes : `vecnet`
importe `sp`, `raster` et `gdistance` -- la pile spatiale en fin de vie -- alors
que dessertR est terra/sf ; il n'est ni sur le CRAN ni sur un r-universe, donc
non installable declarativement ; et il s'annonce « proof of concept », sans
commit depuis septembre 2023.

L'algorithme est desormais **natif** : [dsr_conduire()] reimplemente l'agent
conducteur en terra/sf, sur le noyau Rust du paquet. La route est vectorisee en
la **parcourant** -- depuis une amorce orientee, l'agent avance par pas, regarde
en eventail devant lui et part vers la direction la moins couteuse.

C'est une difference de nature avec [dsr_pathfinder()], et c'est pourquoi les
deux coexistent : le pathfinder relie deux points **connus**, il sait ou il va ;
l'agent ne le sait pas, il suit la conductivite. D'ou deux proprietes que ni le
pathfinder ni le squelette n'ont -- il **franchit les trouees** de detection (le
cout admissible est module par la *profondeur* du creux dans le profil
angulaire, pas par sa seule valeur), et il **decouvre les embranchements**, les
directions ecartees a chaque pas devenant les amorces du tour suivant.

Le noyau Rust n'a pas eu a bouger : `dst` n'y servant qu'a un test d'egalite,
une destination hors grille vide le tas et rend un champ de cout complet. Le
un-vers-tous dont l'agent a besoin etait deja la. Le modele de cout, lui, etait
deja celui de `gdistance` (resistance moyenne x distance), mais sur 16 voisins
au lieu de 8 -- sans le biais de metrication.

[dsr_amorces()] fabrique les amorces. Deux sources, dont une qui n'a pas
d'equivalent dans `vecnet` : les **extremites libres du reseau de reference**.
Elles pointent exactement la ou la desserte cartographiee s'arrete, donc la ou
commence celle qui manque -- c'est le cas d'usage central du paquet, et `vecnet`
ne dispose d'aucune reference pour le servir. A defaut, les entrees de route sur
le bord de l'emprise sont balayees directement, la ou `vecnet` fait rouler un
agent le long d'un contour interieur pour obtenir la meme chose.

`methode = "vecnet"` reste accepte et vaut `"agent"` : aucun code existant ne
casse, et plus rien n'est charge. `"auto"` prend `"agent"`, avec repli annonce
sur le squelette si aucune amorce n'est exploitable.

**Un piege, corrige.** Une trouee de detection (valeur basse) et une absence de
donnee (`NA`) ne sont pas la meme chose. Les confondre -- ce que fait `vecnet`,
ou une conductivite nulle donne malgre tout un cout infini -- laissait l'agent
sortir de l'emprise qu'on lui avait fixee. Les `NA` restent infranchissables, et
le regime `corridor` tient. De meme, une amorce dont le depart tombe hors donnee
est ecartee : sans quoi un troncon de reference debordant de l'emprise ressortait
tel quel comme une « route decouverte », alors que l'agent n'avait pas avance
d'un metre. `n_troncons` permet desormais de distinguer les deux.


## Cubature deblai / remblai

[dsr_cubature()] chiffre, tous les `pas` metres, les volumes qu'exige la mise a
un gabarit donne, par construction d'un profil en travers theorique confronte au
terrain. Methode reimplementee d'apres CubaRoad (Dupire, SylvaLab / ONF, 2021).

L'interet ne tient pas a la reprise de l'outil mais a son **inversion** :
CubaRoad chiffre une route a construire sur MNT vierge, dessertR mesure des
routes qui existent sur un MNT Lidar HD ou la plateforme est deja creusee. Le
meme calcul repond alors a la question metier francaise -- non pas « ou creer
une route » mais « que coute la mise au gabarit de celle-ci ».
[dsr_trafficability()] dit que le grumier ne passe pas ; la cubature dit combien
pour qu'il passe.

Le partage de l'assise entre deblai et remblai est arbitre par le **ripage**,
interpolation du devers amont entre deux seuils : `largeur / 2 * (1 + ripage^2)`.
Sur pente douce, deblai et remblai s'equilibrent ; sur pente raide, le remblai
ne tient pas et tout passe en deblai. Le volume **a evacuer** n'est pas le
volume de deblai : sur un profil equilibre, le deblai est reemploye sur place.

Verifie analytiquement plutot que par non-regression : sur un plan incline,
deblai et remblai ont une forme fermee. Pente 30 %, largeur 4 m, talus
100 %/60 % -- theorie 0,857 m2 et 1,200 m2, calcul 0,857 et 1,202.

Deux ecarts assumes avec CubaRoad : l'intersection talus/terrain est retenue au
**changement de signe** et non sous une tolerance, qui echoue quand le
croisement tombe entre deux echantillons ; et le point de niveau est choisi sur
**l'altitude**, l'axe n'arbitrant qu'a egalite -- l'autre regle biaisait
l'ancrage de 0,17 m sur un versant a 30 %. Un defaut absent de la spec, trouve
en ecrivant les tests : sur terrain plat le talus part du niveau du sol et ne le
recoupe jamais, donc il courait jusqu'au bord du profil et fabriquait un volume
entierement fictif.

Restent a faire : le regime construction (comblement prealable de l'emprise
existante), les lacets, et les sorties SIG assise/emprise.


## Deux specs de lots non arbitres

`dev/SPEC_TRACER.md` et `dev/SPEC_CUBATURE.md` decrivent les equivalents
dessertR de SylvaRoaD et CubaRoad, ecrits depuis la lecture du code des portages
QGIS et non de leurs READMEs. La premiere pose surtout pourquoi la conception de
trace neuf **n'est pas** `dsr_pathfinder()` avec d'autres parametres : le cout
d'une arete y depend de l'azimut et de la pente au noeud precedent, de la
longueur cumulee en devers excessif et de la distance au dernier lacet, et
chaque arete est testee en non-auto-intersection contre tout le chemin deja
pose. Le probleme n'est pas markovien, un noyau dedie est necessaire.


## Check : plus aucun warning imputable au paquet

`R CMD check` passe de trois WARNING a zero. `LICENSE` devient `LICENSE.md`
(deja ignore a la construction), `CITATION.cff` sort de l'archive, `tools` quitte
les Imports ou il ne servait a rien, et le lien Rd vers l'objet interne
`DSR_CANAUX_DTM` devient du code inline.


## Parallelisation : tous les coeurs sauf un

`lasR` alloue par defaut la moitie des coeurs ([lasR::half_cores()]). C'est un
reglage prudent pour un usage interactif, trop prudent pour un traitement de
bloc ou `lasR::exec()` est le poste dominant du temps de calcul : sur une
machine a 16 coeurs, la moitie du parc reste inutilisee pendant toute la
lecture du nuage.

[dsr_ncores()] pose la politique du paquet : **tous les coeurs sauf un**, au
minimum 1. En garder un de libre laisse la machine utilisable et evite
d'affamer les threads GDAL/terra qui tournent entre deux etages du pipeline.

La base de calcul est [lasR::ncores()] -- le nombre de threads que `lasR` peut
reellement utiliser, soit 1 si la version installee est compilee sans OpenMP --
et non `parallel::detectCores()`, qui annoncerait des coeurs inexploitables.

Trois garde-fous. L'option `dessertR.ncores` impose une valeur fixe. Le
resultat est plafonne a 2 sous `R CMD check` (`_R_CHECK_LIMIT_CORES_`), comme
l'exige la politique du CRAN. Enfin, une strategie posee globalement par
[lasR::set_parallel_strategy()] reste prioritaire sur ce reglage : c'est `lasR`
qui arbitre, le paquet ne fait que proposer un defaut moins timide.

La strategie suit le nombre de dalles a traiter. Une seule dalle parallelise
les **points** : il n'y a qu'un fichier a lire, rien a repartir entre threads
de lecture. Plusieurs dalles parallelisent les **fichiers**, ou le gain est
franc. Les deux appels `lasR::exec()` du paquet ([dsr_layers_pc()] et
[dsr_gabarit_libre()]) sont cables dessus, ainsi que le script
`data-raw/make_example.R` -- ce dernier en dur, puisqu'il tourne avant et
independamment de l'installation du paquet.

Aucun changement d'interface ni de resultat : a nombre de coeurs egal, les
sorties sont identiques. Seul le temps de calcul bouge.


# dessertR 1.0.0

Premiere version complete. La chaine fonctionnelle du BRIEF est implementee de
bout en bout (catalogage, canal geomorphologique + nuage, conductivite
`sigma_geo` / `sigma_surf`, pathfinder anisotrope Rust, repositionnement
contraint par la BD TOPO, etat par divergence, mesure de la geometrie,
praticabilite grumier, topologie reseau, detection hors reference vectorisee,
conductivite apprise, canal optique, export GPKG/QGIS), avec noyau Rust, jeu de
validation reproductible sur donnees Lidar HD reelles et dalle d'exemple
versionnee.


## Premier passage du harnais de validation sur donnee reelle

Le harnais `dev/03_validation.R` avait ete ecrit mais jamais execute. Un
premier passage sur l'extrait Lidar HD livre avec le paquet (200 x 200 m,
montagne, 4 troncons BD TOPO, 222 stations) a fait tomber deux defauts et
produit trois observations.

### Corrige

* `dsr_catalog()` echouait sur `Can not cast an empty data.table` quand aucun
  nom de fichier ne suivait la convention Lidar HD. Le cas n'est pas
  theorique : il suffit qu'un bloc soit stocke sous une autre convention. Le
  message nomme maintenant le probleme, la cle attendue et les noms vus.
* La detection de fosse emettait un avertissement par station des qu'une
  fenetre laterale sortait de l'emprise du MNT -- donc pour tout troncon
  atteignant un bord de dalle, donc sur tout massif. Le verdict etait deja bon
  (aucun fosse) ; ce sont des milliers d'avertissements qui noyaient ceux qui
  comptent.
* `dsr_measure()` rendait `PENTE_LONG_MAX = -Inf` avec un avertissement quand
  le MNT n'a aucune valeur sous le trace (troncon hors emprise, trou de
  donnee). Il rend `NA`, qui dit ce qui s'est passe.
* `dsr_calibrer_largeur()` n'avait aucun test. Elle en a quatre, dont la
  stratification par confiance du MNT -- le mecanisme qui repond a « la largeur
  se degrade-t-elle la ou le sol est mal vu ? » -- qui n'avait jamais ete
  executee.

### Observe, puis corrige dans les sections suivantes

* **Le controle ordinal passe** : `Route empierree` ressort plus large que
  `Chemin` (2,83 m contre 2,07 m apres les corrections ci-dessous). Premiere
  confirmation sur donnee reelle que la mesure de largeur est coherente --
  coherente, pas calibree.
* **`FOSSES` n'etait pas exploitable en devers.** Le critere ne testait que la
  descente sous le bord de plateforme dans une fenetre de 4 m. Sur une route en
  deblai-remblai le versant aval est plus bas de 3 m : la condition etait vraie
  partout. Mesure sur le troncon 1 : axe a +3,19 m du bord amont et a -2,96 m
  du bord aval, fosse declare a 68 stations sur 70.
* **Les deux bords de plateforme ne se comportent pas pareil.** Ecart
  interquartile de la position du bord le long du troncon : 0,50 m cote amont,
  1,00 a 1,25 m cote aval. C'est ce qui a mis sur la piste de l'accotement.

## Fosses : un creux, pas une descente

`FOSSES` exige maintenant que le profil **descende puis remonte** de
`prof_fosse` de part et d'autre d'un point bas, au lieu de se contenter de la
descente. Un versant qui descend sans jamais remonter n'est plus un fosse.

Sur l'extrait Lidar HD livre avec le paquet, le compte passe de 211 fosses
declares sur 222 stations a **zero** — et zero est la bonne reponse : le profil
median montre une plateforme de -1,5 a +2,5 m puis une descente **monotone**
jusqu'a -3,31 m a 8 m de l'axe, sans aucun creux. Cote amont le terrain remonte
des le bord : le talus de deblai attaque directement, sans fosse.

Ce que cela ne prouve pas : que le detecteur trouve les vrais fosses. Zero
detection sur une route qui n'en a pas ne dit rien de ce point. Ce sont les
profils de synthese qui l'etablissent — fosse d'un cote, des deux cotes, aucun,
et un fosse plus faible que le seuil.

## La largeur mesure la CHAUSSEE, plus la plateforme

`dsr_measure(methode_largeur = "chaussee")` devient le defaut. Entre l'axe et le
bord de plateforme, le profil compte au plus deux segments -- la chaussee, puis
l'accotement, plus penche. Une droite brisee a deux segments est ajustee et le
bord retenu est l'**intersection des deux droites**. Aucun seuil de pente : la
donnee place la rupture.

Sur profils de synthese, chaussee de 4,00 m :

| profil | `"planeite"` (plateforme) | `"chaussee"` |
|---|---|---|
| sans accotement | 3,89 m | 3,89 m |
| accotement 0,5 m a 6 % | 4,75 m | 3,67 m |
| accotement 1,0 m a 6 % | 5,57 m | **4,00 m** |
| accotement 1,0 m a 10 % | 5,14 m | **4,00 m** |
| accotement 1,5 m a 12 % | 4,95 m | 3,67 m |

Sur l'extrait Lidar HD livre avec le paquet, l'ecart interquartile de la largeur
au sein d'un meme troncon passe de **1,08 m a 0,72 m**, celui de la position du
bord aval de 1,11 m a 0,78 m. Le controle ordinal tient : `Route empierree`
2,83 m contre `Chemin` 2,07 m.

**Ce qu'elle ne sait pas faire.** La rupture n'est retenue que si elle est
significative (test F contre une droite unique) et contrastee. Deux situations
lui echappent : un accotement dont la pente est trop proche du bombement (4 %
contre 3 %, indiscernables sur un MNT) et un bruit de MNT superieur a environ
5 cm. Dans ces cas elle rend le bord de plateforme plutot qu'un bord invente, et
la nouvelle colonne `BORDS_CHAUSSEE` compte les cotes (0, 1 ou 2) ou la rupture
a ete resolue. **Cette colonne se lit avant la largeur** : sur l'extrait livre
avec le paquet, MNT a 50 cm sous couvert, elle vaut 0 a 162 stations sur 222.

Deux details etablis par la mesure : l'ajustement se fait sur le profil **brut**
(le lissage arrondit la rupture, et la regression segmentee lit cet arrondi
comme un segment -- elle retranchait alors 0,46 m inexistants sur une chaussee
sans accotement), et le bord est l'intersection des droites et non le dernier
echantillon du segment interne, qui tronquait d'un pas par cote. La methode
demande un `pas_travers` <= 0,25 m : a 0,5 m il n'y a pas assez de points.

`"planeite"` reste disponible pour qui veut la plateforme.

## Largeur : les deux bords sont renvoyes separement

`dsr_measure()` ajoute `BORD_G` et `BORD_D`, distance de l'axe a chaque bord de
plateforme (leur somme fait `LARGEUR_ROULABLE`). Une largeur unique masquait une
dissymetrie qui est, sur route de montagne, la premiere chose a regarder.

## Canal optique : une seconde source, independante du lidar

Jusqu'ici tout venait du meme nuage de points. Les canaux derives de l'ortho
(BD ORTHO RVB + IRC, et les modeles de hauteur de canopee predits depuis
celle-ci) ne partagent **aucune erreur** avec le lidar : c'est ce qui manquait
depuis qu'on a ecarte les traces produites par ALSroads, qui n'etaient qu'une
seconde lecture de la meme acquisition.

* `dsr_gabarit_lateral()` : largeur de la trouee de canopee centree sur l'axe,
  distance au bord de trouee de chaque cote, et — si la largeur roulable est
  fournie — le **surplomb**, c'est-a-dire de combien les houppiers empietent sur
  l'emprise. Repond a *ou elaguer*, ce qu'aucune sortie ne disait.
* `dsr_trafficability()` gagne le critere **lateral** qui lui manquait : il ne
  verifiait que pente, devers, rayon, largeur et gabarit vertical. Le critere
  n'est pas l'empietement seul mais l'empietement **bas** (`SURPLOMB > 0` **et**
  `HAUT_SURPLOMB < gabarit_min`) : un couvert ferme a 20 m au-dessus d'une route
  ne gene aucun grumier, et en faire une inaptitude declarerait inapte la
  quasi-totalite des routes forestieres.
* `dsr_ndvi()` et `dsr_largeur_ndvi()` : signature spectrale du mineral, avec
  seuil determine par la methode d'Otsu plutot qu'impose — un seuil fixe depend
  du millesime, de la saison et de l'exposition. Le NDVI est la seule grandeur
  optique calculee sur les pixels **natifs** de l'ortho (20 cm), donc la seule
  a l'echelle d'une chaussee forestiere.
* `dsr_canaux_externes()` accepte le vocabulaire optique (`chm`, `mnh`, `ndvi`,
  `gndvi`, `savi`, `ndwi`) et **signale un canal plus grossier que la grille de
  reference**. Apres alignement, plus rien dans la pile ne distingue un canal a
  1,5 m d'un canal a 1 m ; le message le rappelle au moment ou l'information est
  encore disponible.

**Ce qui ne change pas, et ne doit pas changer.** La largeur de chaussee se
mesure sur le MNT. Une trouee de canopee n'est pas une chaussee : sous futaie
mature elle est plus etroite (les houppiers debordent), sur une coupe rase elle
est beaucoup plus large. L'ecart n'est pas constant, il est correle a la
structure du peuplement riverain, donc il change tout au long du troncon. Un
decalage constant se calibre ; celui-la non — on mesurerait surtout l'age du
peuplement voisin. `LARGEUR_DEGAGEE` et `LARGEUR_NDVI` n'alimentent pas
`dsr_calibrer_largeur()`.

Deux limites a connaitre avant d'y lire une mesure fine :

* Un modele de hauteur de canopee predit depuis l'ortho travaille a une maille
  de l'ordre de **1,5 m**. Une chaussee de 4 m n'y couvre que 2,7 cellules. La
  sortie se lit a l'echelle du troncon, pas au decimetre. Sureechantillonne a
  0,20 m, un tel raster *declare* une maille fine sans porter l'information
  correspondante — le paquet ne peut pas le detecter et ne signale que la
  resolution declaree.
* `HAUT_SURPLOMB` est un indicateur **permissif** : un modele de hauteur de
  canopee donne le sommet du houppier, pas le dessous de la branche. Il attrape
  a coup sur la regeneration et les rejets de bord de route (le cas dominant) et
  rate les branches basses des grands arbres. Seul `dsr_gabarit_libre()`, sur le
  nuage classe, donne le dessous de branche.

### Corrige

* `dsr_trafficability()` echouait sur un trace d'une seule station (`vapply`
  degradait la matrice de criteres en vecteur).

## Emprise normative Certu (fiche 1.7)

* `dsr_emprise_certu()` : largeur de chaussee et emprise d'un troncon d'apres
  les largeurs standard de la fiche Certu/CETE 1.7 (2013), a partir des seuls
  attributs BD TOPO. Schemas **v2 et v3** detectes automatiquement ; en v3 le
  franchissement se deduit de `pos_sol`, et la correspondance des valeurs de
  `NATURE` est **deduite, non officielle** — les combinaisons non appariees sont
  signalees plutot que defautees en silence, la table de la fiche etant creuse.
* **Ce n'est pas une reference pour calibrer la largeur, et ce ne peut pas
  l'etre.** Pour `Chemin`, `Route empierree` et `Sentier` — toute la desserte
  forestiere — la fiche rend une **constante de 2 m**. S'y caler forcerait la
  mesure a 2 m partout, donc detruirait le signal que le paquet produit. La
  fiche pose d'ailleurs elle-meme ses limites : elle a ecarte le champ de
  largeur de la BD TOPO (« pas renseigne de facon homogene »), ses valeurs « ne
  delimitent pas avec une precision decimetrique », et la methode « surestime »
  sur la voirie locale.
* Ce qu'elle apporte reellement : le **vocabulaire normatif** du profil en
  travers, qui permet enfin de dire que `LARGEUR_ROULABLE` mesure la
  **chaussee** (comparable a `LARGEUR_CHAUSSEE_CERTU`) et non l'emprise ; et
  l'**ecart a la norme**, lecture utile au gestionnaire — dessertR mesure ce que
  la fiche ne peut que supposer.
* L'appariement est rendu insensible aux accents et a la casse. Sans cela, sous
  une locale non UTF-8, un accent se scinde en deux octets et l'appariement
  echoue en silence, precisement sur « Route empierree ».

## Mesure : deux estimateurs remplaces, et pourquoi

Les deux grandeurs qui commandent l'aptitude grumier etaient mal estimees. Les
chiffres ci-dessous viennent de profils et de traces de synthese a geometrie
connue.

* **Largeur roulable** — `dsr_measure(methode_largeur = "planeite")`, nouveau
  defaut. On ajuste le plan de chaussee sur une fenetre centrale puis on
  s'ecarte tant que la surface reste a moins de `tol_planeite` de ce plan, avec
  interpolation du bord entre echantillons. Sur une plateforme de 4,00 m bombee
  a 3 % :

  | bruit du MNT | `"gradient"` (ancien) | `"planeite"` |
  |---|---|---|
  | aucun | 3,00 m (−1,00) | 3,92 m (−0,08) |
  | 5 cm | 2,56 m (−1,44) | 3,72 m (−0,28) |
  | 10 cm | 0,93 m (−3,08) | 3,66 m (−0,34) |

  Le point decisif n'est pas le gain de biais mais la stabilite : le biais du
  seuil de pente depend du **pas transversal** (−3,74 m a 0,1 m de pas, 0,00 m a
  1 m) autant que de `seuil_devers`. Un seuil cale sur un massif n'aurait valu
  que pour ce pas et ce niveau de bruit — l'ancien estimateur n'etait pas
  calibrable. `tol_planeite` a lui une lecture physique : il doit depasser la
  fleche du bombement (`bombement x largeur / 2`).
* **Ce que coute la grille.** La largeur sort du MNT, donc d'un produit
  interpole, et le bord de plateforme est justement une ligne de rupture. Sur
  une plateforme de synthese de 4,00 m : MNT 50 cm 3,56 m, micro-MNT 25 cm
  3,66 m, points sol bruts 3,78 m, profil parfait finement echantillonne
  3,99 m. L'estimateur est donc **juste** sur une donnee propre, et le
  micro-MNT sur points bruts evoque au BRIEF section 3.6 vaut environ **0,2 m**
  — reel, mais plus modeste qu'annonce. Contre-intuitif : le biais ne bouge pas
  quand la densite de points sol passe de 20 a 1 pt/m2. Pour cette mesure, ce
  n'est pas le nombre de points qui coute, c'est le passage par une grille.
* **Devers** — desormais la pente du plan ajuste. Il est distingue du bombement
  de drainage, qui est symetrique et ne cree aucun devers net.
* **Rayon de courbure** — `base_courbure` (defaut 30 m) : ajustement d'un cercle
  des moindres carres sur une fenetre physique, au lieu du cercle circonscrit a
  trois stations consecutives. Sur un arc de rayon vrai 60 m quantifie au metre
  puis lisse, la mediane des rayons passe de **16,6 m a 56,5 m**. C'etait une
  faute lourde : `dsr_trafficability()` compare `RAYON_COURBURE` a un seuil de
  12 m, donc l'ancien estimateur declarait inapte a peu pres toute route
  courbe. La base de 30 m est aussi l'ordre de grandeur d'un ensemble routier
  grumier. `RAYON_COURBURE_P05` s'ajoute au minimum, moins sensible a une
  station aberrante.
* `dsr_calibrer_largeur()` : balaie une grille de parametres contre une largeur
  de reference et renvoie biais, MAE et RMSE, avec stratification optionnelle
  par confiance du MNT. Un biais constant a MAE faible signale un ecart de
  **definition** (la reference inclut-elle les accotements ?), pas une erreur de
  mesure — la distinction est documentee, elle se tranche avec le gestionnaire.
  La fonction avertit desormais sur ce qui peut faire reference : elle retient
  le reglage qui **minimise** l'ecart, donc la pointer vers la sortie d'un autre
  algorithme ne mesurerait pas le biais de celui-ci, elle le **reproduirait**.
* `dev/03_validation.R` remplace `dev/03_validation_wsfi.R` : il **decouvre** les
  projets nemeton exploitables au lieu d'en coder un en dur, les traite tous, et
  publie un tableau de calibrage croise. Un reglage qui gagne sur un massif et
  perd sur les autres n'est pas un reglage.
  - La racine nemeton est resolue **selon le systeme** : `%LOCALAPPDATA%` sous
    Windows (`nemeton/nemeton/projects`), `Library/Application Support` sous
    macOS, `XDG_DATA_HOME` sous Linux. `DSR_NEMETON` reste prioritaire.
  - L'inventaire liste **tous** les projets avec ce qu'ils portent (dalles, MNT
    mosaique, roads, desserte de reference) plutot que d'ecarter en silence. Un
    projet sans desserte de reference est traite quand meme, aux valeurs par
    defaut : il n'est simplement pas calibrable, et le rapport le dit.
  - `DSR_INVENTAIRE=1` s'arrete apres l'inventaire, pour voir ce qui est trouve
    sans lancer les traitements.
* README reecrit : etat reel de la chaine, fiabilite mesuree grandeur par
  grandeur, et ce qui reste a caler.

## Lissage et raccordement des centre-lignes

* `dsr_vectoriser(lissage = )` : le squelette d'une emprise rasterisee est un
  escalier, et ce n'est pas un defaut cosmetique -- `dsr_measure()` en tire
  `RAYON_COURBURE` et `SINUOSITE`, dont depend l'aptitude grumier. Sur un arc de
  cercle de reference, l'escalier **surestime la longueur de 26 % et la
  sinuosite de 27 %**.
  - `"savitzky-golay"` (defaut, Wang *et al.* 2025) : ajustement polynomial
    local sur `x(t)` et `y(t)`. Ramene l'erreur de longueur a 1,8 %, l'ecart
    median a la courbe vraie de 0,32 m a 0,13 m.
  - `"bezier"` : Bezier cubiques par morceaux ajustees aux moindres carres
    (representation de DOGE, Sun *et al.* 2025, ramenee a un ajustement direct
    sans optimisation differentiable). Courbe C1 par morceaux ; **moins fidele
    que Savitzky-Golay** (0,39 m) et sans gain de sommets une fois
    reechantillonnee en `LINESTRING`. A choisir pour la continuite, pas pour la
    precision.
  - Dans les deux cas les extremites sont figees : elles portent la topologie.
* `dsr_vectoriser(raccorder = )` : relie deux extremites de composantes
  distinctes separees par une trouee de conductivite. Au critere de distance de
  Wang *et al.* s'ajoute un critere d'alignement, sans quoi une piste serait
  soudee au cloisonnement qu'elle croise sans le rejoindre. **Desactive par
  defaut** : cette etape invente de la geometrie la ou la donnee ne montre rien.
* Constat qui a conduit a revoir la mesure : le rayon de courbure dependait
  bien plus du pas des stations que du lissage. Il n'a PAS ete corrige en
  touchant a `pas` -- qui doit rester serre pour les profils transversaux --
  mais en decouplant les deux echelles, voir `base_courbure` ci-dessus.

## Conductivite apprise

* `dsr_echantillon()` : table d'apprentissage prelevee sur une pile de canaux --
  positifs sous le reseau connu, negatifs au-dela de `buffer_neg`, **bande grise
  ecartee** (accotements, fosses, imprecision planimetrique de la reference).
* `dsr_apprendre_conductivite()` : ajuste le modele (`glm` par defaut, `ranger`
  en option) et rapporte l'**AUC en validation croisee stratifiee**, pas en
  resubstitution ; l'ecart avec l'AUC d'apprentissage mesure le surapprentissage.
* `dsr_conductivite(method = "model", modele = ...)` et
  `dsr_sigma_surf(method = "model", ...)` : l'interface prevue des l'origine
  est desormais remplie. La voie parametrique reste le defaut.
* Le BRIEF evoquait un petit U-Net ; on ne l'a pas suivi. Avec un seul massif de
  validation et des canaux deja concus pour la tache, une logistique inspectable
  fait aussi bien et n'apporte ni torch, ni GPU, ni dependance Python. Le
  passage a un modele convolutif se fera derriere la meme interface, quand le
  jeu de validation le justifiera.

## Detection hors reference, regime complet et vectorisation

* `dsr_indice_detection()` : carte de probabilite `p_desserte` hors du corridor
  de reference, fusion ponderee de `sigma_geo`, **`sigma_surf`** et
  `vesselness`. Le poids majoritaire va au canal de surface : un cloisonnement
  se lit d'abord dans la **discontinuite du sous-etage**, pas dans le terrain ou
  son empreinte se confond avec les traces fossiles (BRIEF section 3.9).
* `dsr_vectoriser()` : vectoriseur **enfichable**. Defaut interne = amincissement
  de Zhang-Suen puis tracage du graphe du squelette -- chaque chaine entre deux
  noeuds devient une arete, ce qui **conserve les embranchements** la ou la
  centre-ligne par ACP ecrasait toute une composante en une seule ligne (un
  peigne de cloisonnements sort maintenant en autant d'aretes). `vecnet`
  (r-lidar-lab, Roussel *et al.* 2023) est utilise automatiquement s'il est
  installe ; l'ACP reste disponible.
* `dsr_detecter()` : enchaine les deux, accepte `sigma_surf`, et distingue le
  regime `complet` (toute la grille) du regime `corridor` (restreint a une
  `emprise`). Sortie directement exploitable par `dsr_reseau()`.
* Les vectoriseurs appris (SAM-Road, RNGDet++, GLD-Road) dominent sur les jeux
  satellite mais supposent GPU, PyTorch et un corpus annote massif : ecartes
  pour l'instant, l'interface enfichable leur laisse la porte ouverte.

## Jeu de donnees d'exemple versionne

* `inst/extdata/` : secteur reel de 200 x 200 m (nuage classe ~327 000 points,
  MNT/MNH 50 cm, extrait BD TOPO) centre sur un franchissement route x cours
  d'eau, sous licence ouverte Etalab (voir `LICENSE.note`). Genere par
  `data-raw/make_example.R`. Les tests d'integration (catalogage, layers_pc,
  mesure, chaine geomorphologique) tournent desormais dessus, y compris en CI.

## Detection hors reference (v2)

* `dsr_detecter()` : repere les axes de desserte ABSENTS de la reference
  (pistes, cloisonnements, anciennes RF) -- cellules de forte conductivite (et
  linearite) hors du corridor BD TOPO, regroupees en composantes connexes et
  reduites a une centre-ligne par ACP (BRIEF section 3.9). A affiner avec
  `vecnet` pour une vectorisation topologique complete.

## Repositionnement contraint par la BD TOPO

* `dsr_repositionner()` : recale un reseau de reference (BD TOPO) sur le MNT
  lidar via le pathfinder, **sans jamais s'ecarter de plus de `deviation_max`
  metres de l'axe d'origine** (couloir dur + attraction douce vers l'axe). La
  reference fait autorite : le reseau est **integralement conserve** (repli sur
  la geometrie d'origine si le pathfinder echoue). Corrige le probleme revele par
  la validation (le repositionnement libre accroche des lineaires paralleles --
  risque n.1 du BRIEF) : le recalage contraint ne degrade plus la mesure.

## Jeu de validation

* `dev/03_validation.R` : harnais de validation sur un bloc reel de 4 dalles
  Lidar HD (MNT/MNH 50 cm, reseau BD TOPO, desserte de reference foretaccess).
  Chaine complete + comparaison de la largeur roulable a la reference (MAE,
  biais), brute vs repositionnee. Constats : la mesure sous-estime la largeur
  carrossable (seuils a caler) et le repositionnement sur `sigma_geo` seul peut
  accrocher un lineaire parallele (risque n.1 du BRIEF) -- a contraindre par
  l'axe de reference ou `sigma_surf`.
* `dsr_measure()` : detection de la chaussee plus robuste au desalignement de
  l'axe (plage plane la plus proche du centre, plutot que croissance depuis le
  centre exact) ; seuil de devers par defaut releve a 0.15 (cale par validation).

## Export et rapport

* `dsr_export_gpkg()` : ecrit les couches vectorielles d'un massif dans un unique
  GeoPackage, avec les styles QGIS des couches reconnues.
* `dsr_qml_categorise()` : genere un style QGIS `.qml` categorise (etat,
  aptitude), charge automatiquement a cote de la couche.
* `dsr_rapport()` : synthese Markdown d'un traitement (geometrie, praticabilite,
  etat, reseau). Cloture le socle fonctionnel du BRIEF (hors detection v2).

## Coherence topologique du reseau

* `dsr_reseau()` : assemble une collection de traces en reseau valide (BRIEF
  section 3.8) -- collage des noeuds partages ([dsr_coller_noeuds()]),
  deduplication des paralleles ([dsr_dedupe_paralleles()]), analyse des
  composantes et rattachement au reseau public (une desserte qui ne debouche
  nulle part est signalee). Noyau `igraph`.
* `dsr_sfnetwork()` : export en objet `sfnetwork` (graphe spatial valide) quand
  `sfnetworks` est disponible.

## Praticabilite grumier

* `dsr_gabarit_libre()` : hauteur libre sous branches le long du trace, calculee
  sur le nuage classe (lasR) -- critere reel pour un grumier (~4,5 m), absent des
  bases existantes.
* `dsr_trafficability()` + `dsr_seuils_grumier()` : verdict `APTE_GRUMIER` et
  surtout `MOTIF_INAPTITUDE` (quel critere bloque, et ou), sur des seuils
  parametrables a caler avec le gestionnaire (BRIEF section 3.7).
* `dsr_places()` : detection des elargissements locaux (places de depot / de
  retournement).
* `dsr_measure()` expose desormais le rayon de courbure par station
  (`RAYON_COURBURE`) ; `dsr_profils()` accepte `methode` (bilineaire / plus
  proche voisin).

## Mesure de la geometrie

* `dsr_profils()` : profils transversaux preleves perpendiculairement au trace
  tous les `pas` metres, echantillonnes en bilineaire sur le MNT.
* `dsr_measure()` : premier livrable metier (BRIEF section 3.6) -- largeur
  roulable, devers, fosses (0/1/2), pente longitudinale par station, et
  metriques globales de rayon de courbure minimal et de sinuosite ;
  optionnellement `CONFIANCE_MNT` (densite de points sol) et `DEPLACEMENT` a une
  geometrie de reference. Lissage transversal / longitudinal pour amortir le
  bruit du MNT sous couvert. Valide sur profils synthetiques (devers, largeur,
  sinuosite, courbure).

## Etat le long du trace

* `dsr_etat_trace()` : echantillonne `sigma_geo` / `sigma_surf` le long d'un
  trace ([dsr_pathfinder()] ou geometrie BD TOPO), classe l'etat par troncon et
  resume la repartition (longueur et pourcentage par etat). C'est la lecture
  pertinente de l'etat -- en raster plein il est bruite, le long du trace retenu
  il devient interpretable (BRIEF section 3.4). La classification est factorisee
  avec `dsr_etat()`. Valide sur dalle reelle.

## Pathfinder anisotrope

* `dsr_pathfinder()` : recherche de trace de moindre cout sur `sigma_geo`, avec
  noyau Rust -- etat d'orientation (cellule, cap), penalite d'anisotropie (les
  deplacements en travers de `theta` sont penalises), penalite de courbure, et
  voisinage 16 qui supprime le biais de metrication du Dijkstra 8-connexe
  (BRIEF section 3.5). Sortie `sf` `LINESTRING` + champ de cout cumule. Les
  sauts « cavalier » sont verrouilles pour ne pas franchir une barriere `NA`
  d'une cellule. Valide sur dalle reelle (le trace suit la route forestiere).

## Conductivite de surface et etat

* `dsr_sigma_surf()` : conductivite de surface (emprise encore degagee), fondee
  sur `densite_sousetage` -- le signal d'abandon -- avec masque d'exclusion.
* `dsr_divergence()` et `dsr_etat()` : croisement `sigma_geo` / `sigma_surf` en
  quatre etats (en service, abandonnee, trouee sans route, hors route), le
  diagnostic d'etat du BRIEF (section 3.4). Valide sur dalle reelle : les routes
  actives ressortent en `en_service`.

## Canal surface et qualite via le nuage

* `dsr_layers_pc()` : rasterise via `lasR` les metriques du nuage classe sur la
  grille de reference -- `densite_sol` (confiance du MNT), `taux_penetration`,
  `densite_sousetage` (signal d'abandon, 0,3-3 m au-dessus du sol), `h_couvert`,
  `masque_exclusion` et `masque_pont`. Regime corridor par `emprise` / `masque`.
  Valide sur dalle Lidar HD reelle (lecture COPC par lasR).

## Canal geomorphologique complet et conductivite

* `dsr_pente()`, `dsr_rugosite()` (rugosite residuelle), `dsr_slrm()` (relief
  local simplifie multi-echelle) et `dsr_vesselness()` (linearite de Frangi +
  orientation `theta` pour le pathfinder anisotrope).
* `dsr_layers_dtm()` : assemble toute la pile geomorphologique sur la grille de
  reference a partir du seul MNT.
* `dsr_conductivite()` : `sigma_geo` par combinaison parametrique de fonctions
  d'appartenance ([dsr_appartenance()], [dsr_specs_geomorpho()]), plancher
  `sigma_min` et ponderation par une couche de confiance ; interface
  `method = c("param", "model")` prete pour la conductivite apprise.


# dessertR 0.1.0

Premiere version taggee. Socle et noyau natif.

## Socle

* Catalogage des dalles Lidar HD (LAZ, MNT, MNH) et appariement sur la grille
  kilometrique IGN.
* Extraction du corridor autour d'un reseau de reference.
* Script de benchmark du regime corridor (`dev/02_bench_corridor.R`).

## Canal geomorphologique et noyau Rust

* `dsr_grille_reference()` : grille de reference unique calee a 1 m, derivee du
  MNT, sur laquelle toutes les sorties raster sont alignees.
* `dsr_canaux_externes()` : ingestion et alignement de canaux morphometriques
  precalcules (openness, SVF, SLRM, vesselness), avec garde-fou refusant les
  composites de visualisation 8 bits (CVAT / VAT).
* `dsr_micro_relief()` : sky-view factor et openness (positive / negative) via
  un noyau Rust (`extendr`) vendorise, portage valide de la Relief Visualization
  Toolbox. C'est desormais l'unique chaine native du paquet (voir `dev/BRIEF.md`,
  section 3.5).
