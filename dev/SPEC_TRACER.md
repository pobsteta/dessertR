# Conception de desserte neuve — c'est foretaccess, pas dessertR

**Décision du 2026-08-11 : le tracé de desserte neuve n'a pas d'équivalent dans
dessertR et n'en aura pas.** Il est implémenté dans **foretaccess**, et c'est là
qu'il reste.

Ce fichier portait une spécification `dsr_tracer()` (v0.1, ~8 semaines
estimées), écrite le 2026-07-30 depuis la lecture du code du portage QGIS de
SylvaRoaD. Elle n'a jamais été arbitrée, ni ouverte, ni codée — et elle n'aurait
pas dû être écrite : **foretaccess avait porté le même algorithme deux semaines
plus tôt**, le 2026-07-16.

## Où c'est, chez foretaccess

| Besoin | Fonction |
|---|---|
| Tracé point à point sous contraintes de génie civil | `desserte_trace()` — solveur A\* en Rust, spec 015 |
| Réseau desservant N parcelles | `desserte_reseau()` et ses variantes, heuristique MTAP |
| Ne router que ce qui n'est pas déjà desservi | argument `skidding_m` de `desserte_reseau()` |
| Pondérer par le coût de construction (€/m) | `pondere_cout = TRUE` (Lot 14) |

Non-régression validée contre SylvaRoaD lui-même sur le massif `meisenthal2`.
La couche réseau est un apport propre à foretaccess : SylvaRoaD et FRD ne font
que du point à point.

## Pourquoi la frontière est là

dessertR répond à **« où la route est-elle, et que vaut-elle ? »** — signature
géomorphologique d'une plateforme existante, mesure, praticabilité, état.
foretaccess répond à **« où la route pourrait-elle être ? »** — coût de
construction sur terrain vierge, et quelles parcelles méritent d'être desservies.

Les deux coûts sont disjoints, et c'est ce que l'ancienne spec démontrait
correctement — mais en se comparant à `dsr_pathfinder()` au lieu de se comparer
au paquet voisin qui avait déjà résolu le problème.

**[SPEC_CUBATURE.md](SPEC_CUBATURE.md) reste, lui, valide et implémenté**
([`dsr_cubature()`](../R/cubature.R)) : il ne chiffre pas une route à créer, il
chiffre la mise au gabarit d'une route qui existe. C'est une question de
dessertR, pas de foretaccess.
