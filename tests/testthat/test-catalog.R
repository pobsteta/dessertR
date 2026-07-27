test_that("le decodage du nom de dalle retrouve l'emprise", {
  f <- "LHD_FXX_0186_6834_PTS_C_LAMB93_IGF69.copc.laz"
  d <- dsr_parse_dalle(f)

  expect_equal(d$cle, "0186_6834")
  expect_equal(d$xmin, 186000)
  expect_equal(d$ymax, 6834000)
  expect_equal(d$xmax, 187000)
  expect_equal(d$ymin, 6833000)
})

test_that("MNT et LAZ d'une meme dalle partagent la meme cle", {
  laz <- "LHD_FXX_0186_6834_PTS_C_LAMB93_IGF69.copc.laz"
  mnt <- "LHD_FXX_0186_6834_MNT_O_0M50_LAMB93_IGF69.tif"

  expect_equal(dsr_parse_dalle(laz)$cle, dsr_parse_dalle(mnt)$cle)
})

test_that("un nom non conforme ne fait pas planter le decodage", {
  d <- dsr_parse_dalle("un_fichier_quelconque.laz")

  expect_true(is.na(d$cle))
  expect_true(is.na(d$xmin))
})

test_that("le corridor a la bonne surface a peu pres", {
  skip_if_not_installed("sf")

  ligne <- sf::st_sf(
    geometry = sf::st_sfc(
      sf::st_linestring(cbind(c(0, 1000), c(0, 0))),
      crs = 2154
    )
  )
  co <- dsr_corridor(ligne, tampon = 40)

  # 1000 m de long, 80 m de large, plus deux demi-disques de rayon 40
  attendu <- 1000 * 80 + pi * 40^2
  expect_equal(as.numeric(sf::st_area(co)), attendu, tolerance = 0.01)
})
