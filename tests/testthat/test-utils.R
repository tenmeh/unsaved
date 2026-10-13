test_that("callback validation preserves argument-specific messages", {
  expect_invisible(check_callback(NULL, "on_save"))
  expect_invisible(check_callback(function() TRUE, "action", allow_null = FALSE))
  for (name in c("on_save", "on_discard", "action")) {
    nullable <- name != "action"
    for (bad in list(1, FALSE, function(x) x, function(...) NULL, sum)) {
      expect_error(
        check_callback(bad, name, allow_null = nullable),
        paste0("`", name, "` must be ", if (nullable) "NULL or " else "",
               "a function with no arguments."), fixed = TRUE
      )
    }
  }
  expect_error(check_callback(NULL, "action", allow_null = FALSE),
               "`action` must be a function with no arguments.", fixed = TRUE)
})
