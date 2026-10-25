test_that("badge carries assets and an accessible live region", {
  badge <- unsaved_badge(class = "custom")
  expect_match(as.character(badge), 'aria-live="polite"')
  expect_match(as.character(badge), "unsaved-badge custom")
  expect_equal(htmltools::htmlDependencies(badge)[[1]]$name, "unsaved")
  expect_equal(unsaved_dependency()$script, "unsaved.js")
  expect_error(unsaved_badge(NA_character_), "one non-empty string")
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

test_that("badge plural templates and live setting are validated", {
  badge <- unsaved_badge(c(other = "{n} edits", one = "One edit"), live = FALSE)
  expect_equal(badge$attribs$`data-unsaved-one`, "One edit")
  expect_equal(badge$attribs$`data-unsaved-other`, "{n} edits")
  expect_null(badge$attribs$`aria-live`)
  expect_null(badge$attribs$`aria-atomic`)
  expect_equal(badge$attribs$class, "unsaved-badge badge text-bg-warning")
  for (bad in list(NULL, character(), "", " ", NA_character_, 1,
                   c("one", "other"), c(one = "a", one = "b"),
                   c(one = "a", other = ""), c(one = "a", other = NA_character_),
                   c(one = "a", other = "b", third = "c"))) {
    expect_error(unsaved_badge(bad), "`label`", fixed = TRUE)
  }
  for (bad in list(NULL, NA, 1, "TRUE", logical(), c(TRUE, FALSE))) {
    expect_error(unsaved_badge(live = bad), "`live` must be TRUE or FALSE.", fixed = TRUE)
  }
})
