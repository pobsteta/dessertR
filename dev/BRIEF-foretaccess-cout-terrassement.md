# BRIEF cœur `foretaccess` — le coût de terrassement, et un défaut silencieux de `pondere_cout`

> **À traiter dans une session de dev dédiée sur `/home/pascal/dev/foretaccess`**
> (un repo = une session). Repo concerné : `pobsteta/foretaccess`.
> Écrit depuis `dessertR 1.3.0`, le 2026-08-11.
> **Le code est déjà écrit et commité chez vous** : branche `feat/cout-terrassement`,
> 2 commits, **non poussée**. Ce brief demande un arbitrage, pas une implémentation.

---

## 1. Verdict, d'abord

Deux choses, d'inégale importance.

**La petite, mais qui saigne aujourd'hui** : `reseau_desserte()` accepte un objet
`foretaccess_cout_construction` puis, avec `pondere_cout = FALSE` — le défaut —, **n'en utilise
que le masque `franchissable`**. La surface en €/m est calculée, payée, et jetée. `nemetonshiny`
la calculait à chaque « Générer la desserte », phase « cout » comprise dans la barre de
progression, et produisait un tracé purement géométrique. Personne ne l'a vu pendant des mois
parce que rien ne le dit.

**La grande** : le terme de pente de la surface de coût est un barème en escalier. On propose de
lui substituer un coût de terrassement, continu et sensible à la largeur de plateforme. Le code
est écrit ; il n'est **pas activé**.

---

## 2. `pondere_cout` : un argument qui jette silencieusement son entrée

### Le fait

```r
reseau_desserte(pre, cout, parcelles, desserte_existante, skidding_m = 300)
# -> pondere_cout = FALSE -> .desserte_grille_cout() rend une grille neutre a 1.0
# -> trace purement geometrique, `cout$cout` jamais lu
```

La doc dit « Default `FALSE` (SylvaRoad behaviour) », ce qui est exact et insuffisant : elle
décrit le comportement du solveur, pas ce qu'il advient de l'argument `cout` qu'on vient de lui
passer. Un appelant qui construit une surface de coût le fait rarement pour son masque.

### Ce qu'on demande

Au choix, par ordre de préférence décroissante :

1. **Avertir** quand `cout` porte une surface `cout` exploitable et que `pondere_cout` vaut
   `FALSE` sans avoir été demandé explicitement — la même discipline que `dsr_cubature(regime=)`
   côté dessertR : une valeur qui change tout ne se suppose pas en silence.
2. **Basculer le défaut** à `TRUE`. Plus franc, mais casse la parité SylvaRoad revendiquée par le
   Lot 15 et change tous les tracés existants.
3. Ne rien changer et **le dire dans la doc de `cout`**, pas seulement dans celle de
   `pondere_cout`.

Côté `nemetonshiny`, le correctif est déjà appliqué (`pondere_cout = TRUE`) et fait l'objet de son
propre brief.

---

## 3. Coût de terrassement — spec 029, déjà écrite chez vous

### Le problème

| pente | surcoût du barème |
|---|---|
| 0–15 % | 0 €/m |
| 15–35 % | 25 €/m |
| 35–60 % | 90 €/m |
| ≥ 60 % | non constructible |

Discontinu — 65 €/m d'écart entre 34,9 % et 35,1 % — et **aveugle à la largeur de plateforme**,
alors que le volume déblayé croît comme son **carré**. Une piste de 3 m et une route de 6 m y
coûtent le même surcoût sur le même versant.

### Ce qui est livré

- `specs/029-cout-terrassement.md` — la spec, avec ses limites énoncées ;
- `cout_terrassement(pente_pct, largeur_m, config)` — un €/m continu, par la forme fermée des
  sections de déblai et remblai sur profil en travers plan. **Aucun transect à échantillonner** :
  c'est ce qui le rend utilisable dans un raster, là où un portage du moteur par profil ne le
  serait pas ;
- `surface_cout_construction(..., methode_pente = "terrassement", largeur_m = 4)` ;
- prix et pentes de talus en config, validés par `checkmate` ;
- 12 tests, dont l'oracle analytique — la même forme fermée qui sert de référence aux tests de
  cubature de `dessertR`.

### Ce qui a été trouvé en codant, et qui mérite votre œil

**Le ripage déplace la plateforme, il ne transfère pas un volume.** La version naïve — calculer
deux sections symétriques puis basculer une fraction du remblai vers le déblai — transfère une
quantité qui **diverge** quand le terrain approche la pente du talus aval, alors que c'est
précisément la configuration où il n'y a plus de remblai du tout. Le défaut est sorti du test de
continuité : 22,8 €/m de saut entre deux pentes distantes de 0,5 point. Les sections se
recalculent donc sur des demi-largeurs asymétriques, comme `assise_deblai` / `assise_remblai`.

**Barème et terrassement ne signalent pas l'impossible de la même façon** : le barème rend `Inf`,
le terrassement rend `NA`. Les deux doivent aboutir à une cellule infranchissable — un `NA` se
propagerait en silence dans la somme et laisserait passer le solveur. La conversion est faite au
branchement et testée, mais c'est le genre d'asymétrie qui mérite d'être connue du cœur.

---

## 4. Ce qu'on ne peut pas trancher d'ici

**Les prix au m³ n'ont aucune valeur défendable.** Ceux de la config sont des ordres de grandeur
pour que la fonction tourne — 6 € le déblai, 4 € le remblai, 12 € l'évacuation. Il faut un barème
de gestionnaire, comme celui qui a servi à `fraction_reouverture` (spec 026, plafonds d'État du
Puy-de-Dôme et d'AURA). Sans lui, la méthode ne doit pas devenir le défaut.

**Le banc comparatif n'a pas tourné.** Barème contre terrassement sur un massif réel : quels
tracés changent, de combien, et le résultat est-il plus plausible pour un gestionnaire ? C'est
votre donnée, pas la nôtre — `meisenthal2` sert déjà d'oracle au Lot 15.

**La pente transversale n'est pas la pente du terrain** (spec 029 §5). Elle en dépend par l'azimut
de la route, qu'un coût pré-calculé par cellule ignore. On pose `p_transversale = p_terrain`,
c'est-à-dire une route qui suit la courbe de niveau : c'est le cas dominant en versant, où la pente
en long est bornée à 12 % quand le versant en fait 30 à 60 %, et c'est **majorant**. Le lever
demanderait de porter le coût **sur les arêtes** du graphe plutôt que sur les cellules. La
structure existe (ADR-008), c'est un autre lot — à arbitrer par vous, pas par nous.

---

## 5. Ce que ce brief ne demande pas

- Pas de portage de `dsr_cubature()`. La cubature de `dessertR` chiffre la **mise au gabarit d'une
  route qui existe** ; le terrassement d'ici chiffre une **route à créer**. Même géométrie de
  profil, deux questions différentes, deux dépôts.
- Pas de conception de tracé côté `dessertR`. `dev/SPEC_TRACER.md` a été réduit à un renvoi vers
  vous : le tracé de desserte neuve est chez `foretaccess`, et y reste.

---

## 6. Actions demandées

| # | Action | Qui |
|---|---|---|
| 1 | Arbitrer `pondere_cout` : avertir, basculer, ou documenter (§2) | cœur |
| 2 | Relire et pousser `feat/cout-terrassement`, ou demander des reprises | cœur |
| 3 | Fournir un barème de prix au m³ | gestionnaire |
| 4 | Faire tourner le banc barème / terrassement sur un massif réel | cœur |
| 5 | Arbitrer le coût porté sur les arêtes (lève la limite du §4) | cœur |

Rien n'est urgent sauf le **1**, qui fausse des tracés aujourd'hui chez tous les appelants qui
construisent une surface de coût sans passer le drapeau.
