# Graine globale du harnais.
#
# Une seule fonction du paquet tire au sort -- dsr_calibrer_specs(), qui estime
# l'AUC sur un echantillon -- et elle porte desormais sa propre graine. Mais
# plusieurs tests fabriquent leurs donnees avec runif()/rnorm(), et l'ordre des
# tirages depend de l'ordre d'execution.
#
# Sans cette graine, la COUVERTURE elle-meme n'etait pas deterministe : selon le
# tirage, une branche etait exercee ou non, et codecov rapportait des ecarts
# allant jusqu'a -0,74 % sur des commits ne touchant aucune ligne de R. Un
# controle qui bouge sans que le code bouge n'est plus un controle.
set.seed(20260801)
