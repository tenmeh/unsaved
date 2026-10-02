test_that("badge carries assets and an accessible live region", {
  badge <- unsaved_badge(class = "custom")
  expect_match(as.character(badge), 'aria-live="polite"')
  expect_match(as.character(badge), "unsaved-badge custom")
  expect_equal(htmltools::htmlDependencies(badge)[[1]]$name, "unsaved")
  expect_equal(unsaved_dependency()$script, "unsaved.js")
  expect_error(unsaved_badge(NA_character_), "single string")
})
