# Profil transversal synthetique : plan incline de pente `p`, altitude nulle a
# l'offset 0. Sert de reference analytique -- sur un plan, deblai et remblai ont
# une forme fermee (voir `attendu_plan`), ce qui permet de tester la valeur et
# pas seulement la plausibilite.
plan <- function(p, demi = 20, pas = 0.01) {
  off <- seq(-demi, demi, by = pas)
  list(offsets = off, z = p * off)
}

# Deblai et remblai attendus sur un plan de pente `p`, plateforme de largeur `L`
# posee au niveau du terrain sous l'axe, talus amont `A` et aval `B`, ripage nul
# (donc assise partagee en deux moities egales).
#
#   - sous la demi-plateforme amont : coin de hauteur p*L/2 -> p*L^2/8
#   - au-dela : le talus monte a `A` contre un terrain a `p`, l'ecart p*L/2 se
#     resorbe sur p*L/2/(A-p) -> triangle 0.5 * (p*L/2)^2 / (A-p)
#   - symetrique en remblai avec `B`.
attendu_plan <- function(p, L, A, B) {
  d0 <- p * L / 2
  list(deblai  = p * L^2 / 8 + 0.5 * d0^2 / (A - p),
       remblai = p * L^2 / 8 + 0.5 * d0^2 / (B - p))
}

# Chaine complete sur un profil unique, sans passer par un raster.
cuber_profil <- function(pr, L, A, B, ripage_min = 0.35, ripage_max = 0.60,
                         tol_z = 0.05) {
  off <- pr$offsets
  z <- pr$z
  i_axe <- which.min(abs(off))
  z_plat <- z[i_axe]
  pn <- .dsr_point_niveau(off, z, z_plat, L, NULL, tol_z)
  rp <- .dsr_ripage(off, z, pn$i, z_plat, ripage_min, ripage_max)
  pt <- .dsr_profil_theorique(off, z, pn$i, z_plat, L, if (pn$trouve) rp$ripage else 0,
                              rp$cote, rp$forme, A, B, tol_z)
  c(.dsr_sections(off, z, pt$z_route, diff(off[1:2])),
    list(ripage = rp$ripage, forme = rp$forme, config = pn$config,
         assise_deblai = pt$assise_deblai, assise_remblai = pt$assise_remblai,
         talus_force = pt$talus_force))
}


test_that("sur un plan incline, les sections egalent la forme fermee", {
  cas <- list(
    list(p = 0.30, L = 4, A = 1.0, B = 0.60),
    list(p = 0.20, L = 5, A = 1.0, B = 0.80),
    list(p = 0.30, L = 3, A = 1.5, B = 0.50),
    list(p = 0.10, L = 6, A = 0.67, B = 0.60)
  )
  for (k in cas) {
    res <- cuber_profil(plan(k$p), k$L, k$A, k$B)
    att <- attendu_plan(k$p, k$L, k$A, k$B)
    expect_equal(res$section_deblai, att$deblai, tolerance = 0.01,
                 label = sprintf("deblai p=%.2f L=%g A=%g", k$p, k$L, k$A))
    expect_equal(res$section_remblai, att$remblai, tolerance = 0.01,
                 label = sprintf("remblai p=%.2f L=%g B=%g", k$p, k$L, k$B))
  }
})


test_that("terrain plat : aucun terrassement", {
  # Le piege : le talus part du niveau du terrain et ne le recoupe jamais. Sans
  # garde-fou, il court jusqu'au bout du profil et fabrique un volume fictif.
  res <- cuber_profil(plan(0), L = 4, A = 1, B = 0.6)
  expect_equal(res$section_deblai, 0)
  expect_equal(res$section_remblai, 0)
  expect_equal(res$emprise, 0)
  expect_false(res$talus_force)
})


test_that("le ripage arbitre le partage de l'assise entre ses deux seuils", {
  L <- 4
  # Sous le seuil bas : equilibre, moitie deblai moitie remblai.
  bas <- cuber_profil(plan(0.30), L, 1, 0.6)
  expect_equal(bas$ripage, 0)
  expect_equal(bas$assise_deblai, L / 2)
  expect_equal(bas$assise_remblai, L / 2)

  # Au-dessus du seuil haut : le remblai ne tient pas, tout passe en deblai.
  haut <- cuber_profil(plan(0.70), L, 1.5, 0.6)
  expect_equal(haut$ripage, 1)
  expect_equal(haut$assise_deblai, L)
  expect_equal(haut$assise_remblai, 0)

  # A mi-course exacte entre les seuils : ripage 0.5, assise = L/2 * 1.25.
  mi <- cuber_profil(plan(0.475), L, 1.5, 0.9)
  expect_equal(mi$ripage, 0.5, tolerance = 1e-6)
  expect_equal(mi$assise_deblai, L / 2 * (1 + 0.25), tolerance = 1e-6)
})


test_that("croupe et thalweg sont distingues du versant", {
  off <- seq(-20, 20, by = 0.01)
  expect_equal(.dsr_ripage(off, -0.3 * abs(off), which.min(abs(off)), 0)$forme, "croupe")
  expect_equal(.dsr_ripage(off, 0.3 * abs(off), which.min(abs(off)), 0)$forme, "thalweg")
  expect_equal(.dsr_ripage(off, 0.3 * off, which.min(abs(off)), 0)$forme, "versant")

  # Ni croupe ni thalweg n'arbitrent de ripage : rien a partager.
  expect_equal(.dsr_ripage(off, -0.3 * abs(off), which.min(abs(off)), 0)$ripage, 0)
  expect_equal(.dsr_ripage(off, 0.3 * abs(off), which.min(abs(off)), 0)$ripage, 0)
})


test_that("un aval plus raide que le seuil haut commande le ripage", {
  # Amont doux (20 %), aval raide (80 %) : on ne peut pas asseoir de remblai en
  # contrebas, donc tout doit passer en deblai malgre l'amont doux.
  off <- seq(-20, 20, by = 0.01)
  z <- ifelse(off < 0, 0.80 * off, 0.20 * off)  # descend a 80 % a gauche
  rp <- .dsr_ripage(off, z, which.min(abs(off)), 0)
  expect_equal(rp$forme, "versant")
  expect_equal(rp$cote, 1L)      # l'amont est a droite
  expect_equal(rp$ripage, 1)     # commande par l'aval, pas par l'amont
})


test_that("le talus se durcit par paliers quand il ne recoupe pas le terrain", {
  off <- seq(-20, 20, by = 0.01)
  z <- 0.9 * off                       # terrain a 90 %
  # Talus amont nominal a 50 % : plus doux que le terrain, il ne le rattrape
  # jamais. Le durcissement doit l'amener a un palier superieur a 90 %.
  tl <- .dsr_talus(off, z, i_bord = which.min(abs(off - 2)), z_bord = 0,
                   pente = 0.5, sens = 1L, montant = TRUE)
  expect_true(tl$forcee)
  expect_gt(tl$pente, 0.9)
  expect_true(tl$pente %in% DSR_PALIERS_TALUS)

  # Talus nominal a 150 %, plus raide que le terrain : il recoupe sans forcage.
  ok <- .dsr_talus(off, z, i_bord = which.min(abs(off - 2)), z_bord = 0,
                   pente = 1.5, sens = 1L, montant = TRUE)
  expect_false(ok$forcee)
  expect_equal(ok$pente, 1.5)
})


test_that("le point de niveau qualifie la configuration", {
  off <- seq(-20, 20, by = 0.01)

  # Terrain au niveau de la plateforme sur l'axe : configuration 1.
  pn1 <- .dsr_point_niveau(off, 0.3 * off, z_plat = 0, largeur = 4)
  expect_true(pn1$trouve)
  expect_equal(pn1$config, 1L)
  expect_equal(off[pn1$i], 0, tolerance = 1e-9)

  # Plateforme calee 0,3 m plus haut : le point de niveau se decale sur le
  # versant, configuration 2.
  pn2 <- .dsr_point_niveau(off, 0.3 * off, z_plat = 0.3, largeur = 4)
  expect_true(pn2$trouve)
  expect_equal(pn2$config, 2L)
  expect_equal(off[pn2$i], 1, tolerance = 0.05)

  # Plateforme tres au-dessous du terrain : aucun point de niveau, tout en
  # deblai (configuration 3).
  pn3 <- .dsr_point_niveau(off, 0.3 * off + 50, z_plat = 0, largeur = 4)
  expect_false(pn3$trouve)
  expect_equal(pn3$config, 3L)

  # Tres au-dessus : tout en remblai (configuration 5).
  pn5 <- .dsr_point_niveau(off, 0.3 * off - 50, z_plat = 0, largeur = 4)
  expect_false(pn5$trouve)
  expect_equal(pn5$config, 5L)
})


test_that("dsr_cubature refuse les entrees incoherentes", {
  mnt <- terra::rast(nrows = 40, ncols = 40, xmin = 0, xmax = 40, ymin = 0,
                     ymax = 40, crs = "EPSG:2154")
  terra::values(mnt) <- 0
  tr <- sf::st_sfc(sf::st_linestring(cbind(c(20, 20), c(5, 35))), crs = "EPSG:2154")

  expect_error(dsr_cubature(tr, mnt, largeur = 0), "strictement positifs")
  expect_error(dsr_cubature(tr, mnt, largeur = -1), "strictement positifs")
  expect_error(dsr_cubature(tr, mnt, largeur = 4, ripage_min = 0.7, ripage_max = 0.6),
               "inferieur")
})


test_that("dsr_cubature agrege volumes et longueurs sur un versant regulier", {
  mnt <- terra::rast(nrows = 200, ncols = 200, xmin = 0, xmax = 100, ymin = 0,
                     ymax = 100, crs = "EPSG:2154")
  terra::values(mnt) <- terra::xFromCell(mnt, seq_len(terra::ncell(mnt))) * 0.3
  tr <- sf::st_sfc(sf::st_linestring(cbind(c(50, 50), c(10, 90))), crs = "EPSG:2154")

  cub <- dsr_cubature(tr, mnt, largeur = 4, s_amont = 1, s_aval = 0.6, pas = 10)

  expect_s3_class(cub$points, "sf")
  expect_equal(nrow(cub$points), 9L)
  # Les longueurs applicables se somment a la longueur du trace : aucun metre
  # compte deux fois, aucun oublie.
  expect_equal(sum(cub$points$long_applicable), 80, tolerance = 1e-6)
  expect_equal(cub$resume$longueur, 80, tolerance = 1e-6)

  # Le versant est regulier : toutes les stations doivent donner la meme section.
  att <- attendu_plan(0.3, 4, 1, 0.6)
  expect_equal(unique(round(cub$points$section_deblai, 3)),
               round(att$deblai, 3), tolerance = 0.01)
  expect_equal(cub$resume$volume_deblai,
               att$deblai * 80, tolerance = 0.02)

  # Devers 30 % < ripage_max : le deblai est reemploye sur place, rien a evacuer.
  expect_equal(cub$resume$volume_evacuer, 0)
  expect_equal(cub$resume$n_talus_force, 0L)
})


test_that("le volume a evacuer n'apparait qu'au-dela du seuil de reemploi", {
  # Versant a 80 % : au-dela de ripage_max, le deblai ne peut plus etre reemploye
  # en remblai sur place et part en evacuation.
  mnt <- terra::rast(nrows = 200, ncols = 200, xmin = 0, xmax = 100, ymin = 0,
                     ymax = 100, crs = "EPSG:2154")
  terra::values(mnt) <- terra::xFromCell(mnt, seq_len(terra::ncell(mnt))) * 0.8
  tr <- sf::st_sfc(sf::st_linestring(cbind(c(50, 50), c(10, 90))), crs = "EPSG:2154")

  cub <- dsr_cubature(tr, mnt, largeur = 4, s_amont = 1.5, s_aval = 0.6,
                      p_rocher = 20, pas = 10)
  expect_true(all(cub$points$ripage == 1))
  expect_equal(cub$resume$volume_evacuer, cub$resume$volume_deblai)
  # 20 % de rocher dans le deblai.
  expect_equal(cub$resume$volume_roche, 0.2 * cub$resume$volume_deblai,
               tolerance = 1e-9)
})
