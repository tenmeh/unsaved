#' Compare Text Inputs
#' @param trim Trim leading and trailing whitespace from text.
#' @param empty_is_null Treat an empty string and NULL as equal.
#' @return A function taking saved and current values and returning equality.
#' @examples
#' compare <- unsaved_compare_text()
#' compare(" Ada ", "Ada")
#' @export
unsaved_compare_text <- function(trim = TRUE, empty_is_null = TRUE) {
  for (flag in list(trim, empty_is_null)) {
    if (!is.logical(flag) || length(flag) != 1L || is.na(flag)) {
      stop("Text comparison options must be single logical values.", call. = FALSE)
    }
  }
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
    !anyDuplicated(names(compare)) && all(names(compare) %in% inputs) &&
    all(vapply(compare, is.function, logical(1)))
  if (!valid) {
    stop("`compare` must be NULL, a function, or a named list of functions keyed by tracked input id.", call. = FALSE)
  }
  invisible(NULL)
}
