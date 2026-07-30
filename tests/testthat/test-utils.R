test_that("dsr_ncores laisse un coeur libre et ne descend jamais sous 1", {
  skip_if_not_installed("lasR")
  withr::local_envvar(`_R_CHECK_LIMIT_CORES_` = "")

  n <- dsr_ncores()
  expect_type(n, "integer")
  expect_gte(n, 1L)
  expect_equal(n, max(1L, lasR::ncores() - 1L))

  # Reserve plus large, et plancher a 1 meme si la reserve depasse le parc.
  expect_equal(dsr_ncores(reserve = 2L), max(1L, lasR::ncores() - 2L))
  expect_equal(dsr_ncores(reserve = 1000L), 1L)
})

test_that("dsr_ncores respecte l'option et le plafond de R CMD check", {
  withr::local_options(dessertR.ncores = 3)
  withr::local_envvar(`_R_CHECK_LIMIT_CORES_` = "")
  expect_equal(dsr_ncores(), 3L)

  withr::local_envvar(`_R_CHECK_LIMIT_CORES_` = "TRUE")
  expect_equal(dsr_ncores(), 2L)
})

test_that("dsr_strategie_lasr choisit points ou fichiers selon le nombre de dalles", {
  skip_if_not_installed("lasR")
  withr::local_options(dessertR.ncores = 2)
  withr::local_envvar(`_R_CHECK_LIMIT_CORES_` = "")

  une <- dsr_strategie_lasr(1L)
  plusieurs <- dsr_strategie_lasr(4L)
  expect_equal(attr(une, "strategy"), "concurrent-points")
  expect_equal(attr(plusieurs, "strategy"), "concurrent-files")
  expect_equal(as.integer(une), 2L)
  expect_equal(as.integer(plusieurs), 2L)
})
