test_that("text retain defaults and validate every field", {
  text <- unsaved_text()
  expect_s3_class(text, "unsaved_text")
  expect_equal(unclass(text), list(
    title = "Save your changes?",
    message = paste("You have {n} unsaved change{s}.",
                    "They will be lost if you continue without saving."),
    keep = "Keep editing", discard = "Discard and continue", save = "Save and continue",
    saving = "Saving...", save_failed = "Could not save. Your changes are still here. Try again or keep editing.",
    unsaved = "Unsaved change", reason = "Reason for change (required)",
    reason_title = "Why are you making this change?",
    reason_cancel = "Keep editing", reason_save = "Save",
    save_incomplete = "Saved. Some changes were made while saving and are not saved yet.",
    reason_missing = "Enter a reason to save.", reason_count = "{n} of {max} characters",
    reason_cut = "The reason was shortened to {max} characters."
  ))
  for (id in names(text)) {
    for (bad in list(NULL, character(), NA_character_, c("a", "b"), 1)) {
      expect_error(do.call(unsaved_text, setNames(list(bad), id)), id, fixed = TRUE)
    }
    expect_equal(do.call(unsaved_text, setNames(list(""), id))[[id]], "")
  }
})
