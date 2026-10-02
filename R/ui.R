#' Client Assets for Unsaved Changes
#' @return An HTML dependency containing the script and stylesheet.
#' @examples
#' unsaved_dependency()
#' @export
unsaved_dependency <- function() {
  htmltools::htmlDependency(
    "unsaved", "0.1.0",
    src = c(file = "www"), package = "unsaved",
    script = "unsaved.js", stylesheet = "unsaved.css"
  )
}

#' Display the Number of Unsaved Changes
#' @param label Text template. `{n}` is the count; `{s}` is the plural suffix.
#' @param class Optional additional CSS classes.
#' @return A span filled by the client, with the package assets attached.
#' @details Badges show the number of distinct dirty fields across all trackers.
#' @examples
#' unsaved_badge()
#' @export
unsaved_badge <- function(label = "{n} unsaved change{s}", class = NULL) {
  if (!is.character(label) || length(label) != 1L || is.na(label)) {
    stop("`label` must be a single string.", call. = FALSE)
  }
  badge <- htmltools::tags$span(
    class = paste(c("unsaved-badge", class), collapse = " "),
    `data-unsaved-label` = label,
    `aria-live` = "polite",
    `aria-atomic` = "true"
  )
  htmltools::attachDependencies(badge, unsaved_dependency())
}
