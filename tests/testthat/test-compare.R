test_that("snapshot comparison reports only changed common inputs", {
  a <- make_snapshot()
  expect_equal(changed_inputs(a, a), character())
  b <- a
  b$name <- "Grace"
  expect_equal(changed_inputs(a, b), "name")
  b$new <- 1
  b$number <- NULL
  expect_equal(changed_inputs(a, b), "name")
})

test_that("late inputs join once and retain saved values after removal", {
  baseline <- join_baseline(list(x = 1), list(x = 1, late = "first", null = NULL))
  expect_equal(baseline, list(x = 1, late = "first", null = NULL))
  expect_equal(changed_inputs(baseline, list(x = 1, late = "first")), character())
  edited <- list(x = 1, late = "edited")
  expect_equal(join_baseline(baseline, edited), baseline)
  expect_equal(changed_inputs(baseline, edited), "late")
  expect_equal(join_baseline(baseline, list(x = 1)), baseline)
  expect_equal(changed_inputs(baseline, list(x = 1)), character())
  expect_equal(join_baseline(list(), list()), list())
})
test_that("values tolerate ordinary JSON type drift", {
  expect_equal(values_equal(1L, 1), TRUE)
  expect_equal(values_equal(c(2000L, 2026L), c(2000, 2026)), TRUE)
  expect_equal(values_equal(1, 1 + 1e-9), TRUE)
  expect_equal(values_equal(as.Date("2026-01-01"), "2026-01-01"), TRUE)
  expect_equal(values_equal(NULL, NULL), TRUE)
  expect_equal(values_equal(NULL, 0), FALSE)
  expect_equal(values_equal(NA_real_, NA_integer_), TRUE)
  expect_equal(values_equal(1, c(1, 2)), FALSE)
  nested_a <- list(a = list(x = 1), b = NULL)
  nested_b <- list(b = NULL, a = list(x = 1L))
  expect_equal(values_equal(nested_a, nested_b), TRUE)
  expect_equal(values_equal(list(a = 1), list(b = 1)), FALSE)
  expect_equal(values_equal(list(1, list(2)), list(1, list(3))), FALSE)
})
test_that("eligibility filters precede exclusions", {
  a <- list(
    x = 1, y = 2, .internal = 1, unsaved_nav_blocked = 1,
    button = structure(0, class = "shinyActionButtonValue")
  )
  expect_named(snapshot_inputs(a), c("x", "y"))
  expect_named(snapshot_inputs(a, c("x", "y", "button"), "y"), "x")
  expect_equal(snapshot_inputs(list()), list())
})

test_that("custom comparison supports defaults, one function and per-input functions", {
  saved <- list(name = "Ada", other = "Ada", n = 1)
  current <- list(name = " Ada ", other = " Ada ", n = 1 + 1e-10)
  expect_equal(changed_inputs(saved, current, NULL), c("name", "other"))
  expect_equal(changed_inputs(saved, current, unsaved_compare_text()), character())
  expect_equal(changed_inputs(saved, current, list(name = unsaved_compare_text())), "other")
  expect_equal(changed_inputs(list(), list(), identical), character())
  for (bad in list(NULL, NA, logical(), c(TRUE, FALSE), 1, "yes")) {
    compare <- function(saved, current) bad
    expect_error(changed_inputs(saved, current, compare), "input `name`", fixed = TRUE)
  }
})

test_that("text comparison handles empty, missing, whitespace and non-text values", {
  compare <- unsaved_compare_text()
  expect_equal(compare(NULL, ""), TRUE)
  expect_equal(compare("  ", NULL), TRUE)
  expect_equal(compare(" Ada ", "Ada"), TRUE)
  expect_equal(compare(c(" Ada ", NA), c("Ada", NA)), TRUE)
  expect_equal(compare(1, 1 + 1e-10), TRUE)
  expect_equal(compare(list(a = 1), list(a = 1)), TRUE)
  expect_equal(unsaved_compare_text(trim = FALSE)(" Ada ", "Ada"), FALSE)
  expect_equal(unsaved_compare_text(empty_is_null = FALSE)("", NULL), FALSE)
  expect_equal(compare(NA_character_, ""), FALSE)
  for (bad in list(NULL, NA, c(TRUE, FALSE), 1)) {
    expect_error(unsaved_compare_text(trim = bad), "TRUE or FALSE")
    expect_error(unsaved_compare_text(empty_is_null = bad), "TRUE or FALSE")
  }
})
test_that("text flags name invalid values", {
  expect_error(unsaved_compare_text(trim = "yes"),
               '`trim` must be TRUE or FALSE; got "yes".', fixed = TRUE)
  expect_error(unsaved_compare_text(empty_is_null = "yes"),
               '`empty_is_null` must be TRUE or FALSE; got "yes".', fixed = TRUE)
})

test_that("table changes describe cells in row order and bound the summary", {
  saved <- data.frame(value = c(12, 24), flag = c("", "Check"))
  current <- saved
  current$value[1] <- 14
  expect_equal(format_change(saved, current), "row 1, value: 12 -> 14")
  current$flag[1] <- "Checked"
  current$value[2] <- 25
  first_three <- paste(
    'row 1, value: 12 -> 14; row 1, flag: "" -> Checked;',
    "row 2, value: 24 -> 25"
  )
  expect_equal(format_change(saved, current), first_three)
  current$flag[2] <- "Done"
  expect_equal(format_change(saved, current), paste0(first_three, "; and 1 more cells"))
  saved$extra <- c(1, 2)
  current$extra <- c(1, 3)
  expect_equal(format_change(saved, current), paste0(first_three, "; and 2 more cells"))
  expect_equal(format_change(saved, saved), "no change")
  expect_equal(format_change(saved[FALSE, ], saved[FALSE, ]), "no change")
  expect_equal(format_change(data.frame(), data.frame()), "no change")
})

test_that("table cell descriptions use value formatting and comparison", {
  saved <- data.frame(value = c(NA_real_, 12), day = as.Date(c("2026-01-01", "2026-01-02")))
  current <- saved
  current$value <- c(14, 12 + 1e-10)
  current$day[2] <- as.Date("2026-01-03")
  expect_equal(format_change(saved, current),
               "row 1, value: NA -> 14; row 2, day: 2026-01-02 -> 2026-01-03")
  saved <- data.frame(flag = factor("Check"), note = "short")
  current <- data.frame(flag = factor("Done"), note = strrep("x", 60))
  expect_equal(format_change(saved, current), paste0(
    "row 1, flag: Check -> Done; row 1, note: short -> ", format_value(current$note)
  ))
  saved <- data.frame(value = 12)
  current <- data.frame(value = NA_real_)
  expect_equal(format_change(saved, current), "row 1, value: 12 -> NA")
})

test_that("table structure changes retain table summaries", {
  saved <- data.frame(value = c(12, 24), flag = c("", "Check"))
  expect_equal(format_change(saved, saved[1, ]), "a table of 2 rows -> a table of 1 row")
  expect_equal(format_change(saved, saved[FALSE, ]), "a table of 2 rows -> a table of 0 rows")
  expect_equal(format_change(saved, saved[, "value", drop = FALSE]),
               "a table of 2 rows -> a table of 2 rows")
  current <- saved
  names(current)[1] <- "result"
  expect_equal(format_change(saved, current), "a table of 2 rows -> a table of 2 rows")
  expect_equal(format_change(saved, saved[, c("flag", "value")]),
               "a table of 2 rows -> a table of 2 rows")
})
