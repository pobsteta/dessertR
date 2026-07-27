# Mise en place de l'environnement de developpement -----------------------
# A executer une fois.

install.packages(c("devtools", "roxygen2", "testthat", "pkgdown",
                   "sf", "terra", "rlas", "data.table", "cli"))

# lasR n'est pas sur le CRAN
install.packages("lasR", repos = "https://r-lidar.r-universe.dev")

# Verification immediate : lasR lit-il un COPC de l'IGN ?
# C'est le premier point bloquant potentiel du projet, a lever avant tout.
# packageVersion("lasR")
# ... ouvrir la doc de la version installee et tester sur une vraie dalle.

devtools::document()
devtools::load_all()
devtools::test()
