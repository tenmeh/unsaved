#' Compare Text Inputs
#' @param trim Trim leading and trailing whitespace from text.
#' @param empty_is_null Treat an empty string and NULL as equal.
#' @return A function taking saved and current values and returning equality.
#' @examples
#' compare <- unsaved_compare_text()
#' compare(" Ada ", "Ada")
#' @export
unsaved_compare_text <- function(trim = TRUE, empty_is_null = TRUE) {
  check_flag(trim, "trim")
  check_flag(empty_is_null, "empty_is_null")
  normalise <- function(value) {
    if (trim && is.character(value)) value <- trimws(value)
    if (empty_is_null && identical(value, "")) value <- NULL
    value
  }
  function(saved, current) values_equal(normalise(saved), normalise(current))
}

validate_compare <- function(compare, inputs) {
  if (is.null(compare) || is.function(compare)) return(invisible(NULL))
  valid <- is.list(compare) && !is.null(names(compare)) &&
    !anyNA(names(compare)) && all(nzchar(names(compare))) &&
    !anyDuplicated(names(compare)) &&
    all(vapply(compare, is.function, logical(1)))
  if (!valid) {
    stop("`compare` must be NULL, a function, or a named list of functions keyed by tracked input id.", call. = FALSE)
  }
  unknown <- setdiff(names(compare), inputs)
  if (length(unknown)) {
    stop("`compare` has unknown input id `", substr(unknown[1L], 1L, 60L),
         "`. Tracked ids: ", paste(inputs, collapse = ", "), ".", call. = FALSE)
  }
  invisible(NULL)
}
