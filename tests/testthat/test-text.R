test_that("text retain defaults and validate every field", {
  text <- unsaved_text()
  expect_s3_class(text, "unsaved_text")
  expect_equal(unclass(text), list(
    title = "Unsaved changes", message = "You have {n} unsaved change{s}.",
    keep = "Keep editing", discard = "Discard changes", save = "Save and leave",
    saving = "Saving...", save_failed = "Could not save. Your changes are still here.",
    unsaved = "(unsaved)", reason = "Reason for change",
    reason_title = "Why are you making this change?"
  ))
  for (id in names(text)) {
    for (bad in list(NULL, character(), NA_character_, c("a", "b"), 1)) {
      expect_error(do.call(unsaved_text, setNames(list(bad), id)), id, fixed = TRUE)
    }
    expect_equal(do.call(unsaved_text, setNames(list(""), id))[[id]], "")
  }
})
