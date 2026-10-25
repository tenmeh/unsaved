#' Customise Unsaved Dialog Text
#' @param title Dialog heading.
#' @param message Template with `{n}` and `{s}` placeholders.
#' @param keep Keep editing button text.
#' @param discard Discard button text.
#' @param save Save and continue button text.
#' @param saving Text while saving.
#' @param save_failed Alert after a failed save.
#' @param save_incomplete Alert when edits made during a save remain unsaved.
#' @param unsaved Screen-reader text for changed fields.
#' @param reason Label for the required reason text area.
#' @param reason_title Heading for the reason-only dialog.
#' @param reason_cancel Cancel button in the reason-only dialog.
#' @param reason_save Save button in the reason-only dialog.
#' @param reason_missing Inline error for an empty reason.
#' @param reason_count Counter template with `{n}` and `{max}` placeholders.
#' @param reason_cut Alert template with the `{max}` placeholder for cut text.
#' @return A classed list for unsaved_track().
#' @examples
#' unsaved_text(title = "Profile changes")
#' @export
unsaved_text <- function(title = "Save your changes?",
                         message = paste("You have {n} unsaved change{s}.",
                                         "They will be lost if you continue without saving."),
                         keep = "Keep editing", discard = "Discard and continue",
                         save = "Save and continue", saving = "Saving...",
                         save_failed = "Could not save. Your changes are still here. Try again or keep editing.",
                         unsaved = "Unsaved change", reason = "Reason for change (required)",
                         reason_title = "Why are you making this change?",
                         reason_cancel = "Keep editing", reason_save = "Save",
                         save_incomplete = "Saved. Some changes were made while saving and are not saved yet.",
                         reason_missing = "Enter a reason to save.",
                         reason_count = "{n} of {max} characters",
                         reason_cut = "The reason was shortened to {max} characters.") {
  text <- list(
    title = title, message = message, keep = keep, discard = discard,
    save = save, saving = saving, save_failed = save_failed, unsaved = unsaved,
    reason = reason, reason_title = reason_title,
    reason_cancel = reason_cancel, reason_save = reason_save,
    save_incomplete = save_incomplete, reason_missing = reason_missing,
    reason_count = reason_count, reason_cut = reason_cut
  )
  for (id in names(text)) {
    value <- text[[id]]
    if (!is.character(value) || length(value) != 1L || is.na(value)) {
      stop("`", id, "` must be a single non-NA string.", call. = FALSE)
    }
  }
  structure(text, class = "unsaved_text")
}
