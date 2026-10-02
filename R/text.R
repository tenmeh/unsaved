#' Customise Unsaved Dialog Text
#' @param title Dialog heading.
#' @param message Template with `{n}` and `{s}` placeholders.
#' @param keep Keep editing button text.
#' @param discard Discard button text.
#' @param save Save and leave button text.
#' @param saving Text while saving.
#' @param save_failed Alert after a failed save.
#' @param unsaved Screen-reader text for changed fields.
#' @return A classed list for unsaved_track().
#' @examples
#' unsaved_text(title = "Profile changes")
#' @export
unsaved_text <- function(title = "Unsaved changes",
                         message = "You have {n} unsaved change{s}.",
                         keep = "Keep editing", discard = "Discard changes",
                         save = "Save and leave", saving = "Saving...",
                         save_failed = "Could not save. Your changes are still here.",
                         unsaved = "(unsaved)") {
  text <- list(
    title = title, message = message, keep = keep, discard = discard,
    save = save, saving = saving, save_failed = save_failed, unsaved = unsaved
  )
  for (id in names(text)) {
    value <- text[[id]]
    if (!is.character(value) || length(value) != 1L || is.na(value)) {
      stop("`", id, "` must be a single non-NA string.", call. = FALSE)
    }
  }
  structure(text, class = "unsaved_text")
}
