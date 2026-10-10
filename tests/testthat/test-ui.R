test_that("badge carries assets and an accessible live region", {
  badge <- unsaved_badge(class = "custom")
  expect_match(as.character(badge), 'aria-live="polite"')
  expect_match(as.character(badge), "unsaved-badge custom")
  expect_equal(htmltools::htmlDependencies(badge)[[1]]$name, "unsaved")
  expect_equal(unsaved_dependency()$script, "unsaved.js")
  expect_error(unsaved_badge(NA_character_), "single string")
})
test_that("badge classes accept character vectors and reject missing or non-text values", {
  for (bad in list(NA_character_, list(a = 1), 1, c("a", NA_character_))) {
    expect_error(unsaved_badge(class = bad),
                 "`class` must be NULL or a character vector without missing values.", fixed = TRUE)
  }
  expect_equal(unsaved_badge(class = c("a", "b"))$attribs$class, "unsaved-badge a b")
  expect_equal(unsaved_badge(class = NULL)$attribs$class, "unsaved-badge")
  expect_equal(unsaved_badge(class = character())$attribs$class, "unsaved-badge")
})
