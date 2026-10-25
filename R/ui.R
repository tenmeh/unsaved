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
#' @param label One non-empty text template, or two non-empty templates named
#'   `one` and `other`. `one` is used for a count of one, `other` otherwise.
#'   `{n}` is the count; `{s}` is the plural suffix.
#' @param class NULL or a character vector of additional CSS classes, without NA.
#' @param live Whether to announce badge changes in a polite live region.
#' @return A span filled by the client, with the package assets attached.
#' @details Badges show the number of distinct dirty fields across all active
#'   trackers, including modules. Paused trackers do not contribute.
#'   For a module-local count, use a textOutput() in the module UI and
#'   `output$count <- shiny::renderText(tracker$count())` in its server.
#' @seealso [unsaved_track()] for reactive tracker query methods.
#' @examples
#' unsaved_badge()
#' @export
unsaved_badge <- function(label = "{n} unsaved change{s}",
                          class = "badge text-bg-warning", live = TRUE) {
  if (!is.character(label) || anyNA(label) || any(!nzchar(trimws(label))) ||
        !(length(label) == 1L || (length(label) == 2L &&
                                    setequal(names(label), c("one", "other"))))) {
    stop("`label` must be one non-empty string or two non-empty strings named `one` and `other`.",
         call. = FALSE)
  }
  if (!is.logical(live) || length(live) != 1L || is.na(live)) {
    stop("`live` must be TRUE or FALSE.", call. = FALSE)
  }
  if (!is.null(class) && (!is.character(class) || anyNA(class))) {
    stop("`class` must be NULL or a character vector without missing values.", call. = FALSE)
  }
  badge <- htmltools::tags$span(
    class = paste(c("unsaved-badge", class), collapse = " "),
    `data-unsaved-label` = if (length(label) == 1L) unname(label) else NULL,
    `data-unsaved-one` = if (length(label) == 2L) label[["one"]] else NULL,
    `data-unsaved-other` = if (length(label) == 2L) label[["other"]] else NULL,
    `aria-live` = if (live) "polite" else NULL,
    `aria-atomic` = if (live) "true" else NULL
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
