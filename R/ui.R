#' Client Assets for Unsaved Changes
#' @return An HTML dependency containing the script and stylesheet.
#' @examples
#' unsaved_dependency()
#' @export
unsaved_dependency <- function() {
  htmltools::htmlDependency(
    "unsaved", as.character(utils::packageVersion("unsaved")),
    src = c(file = "www"), package = "unsaved",
    script = "unsaved.js", stylesheet = "unsaved.css"
  )
}

#' Display the Page Total of Unsaved Changes
#' @description Show the page total of distinct changed fields across trackers.
#' @param label Text template. `{n}` is the count; `{s}` is the plural suffix.
#' @param class NULL or a character vector of additional CSS classes, without NA.
#' @return A span filled by the client, with the package assets attached.
#' @details Badges show the number of distinct dirty fields across all active
#'   trackers, including modules. Paused trackers do not contribute.
#'   For a module-local count, use a textOutput() in the module UI and
#'   `output$count <- shiny::renderText(tracker$count())` in its server.
#' @seealso [unsaved_track()] for reactive tracker query methods.
#' @examples
#' unsaved_badge()
#' @export
unsaved_badge <- function(label = "{n} unsaved change{s}", class = NULL) {
  if (!is.character(label) || length(label) != 1L || is.na(label)) {
    stop("`label` must be a single string.", call. = FALSE)
  }
  if (!is.null(class) && (!is.character(class) || anyNA(class))) {
    stop("`class` must be NULL or a character vector without missing values.", call. = FALSE)
  }
  badge <- htmltools::tags$span(
    class = paste(c("unsaved-badge", class), collapse = " "),
    `data-unsaved-label` = label,
    `aria-live` = "polite",
    `aria-atomic` = "true"
  )
  htmltools::attachDependencies(badge, unsaved_dependency())
}

#' Guard a Click Against Unsaved Changes
#' @param tag An htmltools tag, such as an action button, modal close button
#'   or plain link. Dirty trackers with guard_clicks = TRUE guard the click.
#' @return The tag with the data-unsaved-guard attribute and client assets.
#' @details Keep editing cancels the click. Discard or a successful save
#'   replays it once. Use tracker$confirm(action) for an action on the server.
#' @examples
#' unsaved_guard(shiny::actionButton("delete", "Delete draft"))
#' unsaved_guard(htmltools::tags$a(href = "#details", "Details"))
#' @export
unsaved_guard <- function(tag) {
  if (!inherits(tag, "shiny.tag")) stop("`tag` must be an htmltools tag.", call. = FALSE)
  tag <- htmltools::tagAppendAttributes(tag, `data-unsaved-guard` = "")
  htmltools::attachDependencies(tag, unsaved_dependency(), append = TRUE)
}
