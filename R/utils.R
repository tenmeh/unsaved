`%||%` <- function(x, y) if (is.null(x)) y else x

require_session <- function(session) {
  if (is.null(session)) {
    stop(
      "No Shiny session found. Call unsaved_track() inside your server function.",
      call. = FALSE
    )
  }
  session
}

na_to_null <- function(x) {
  if (is.list(x)) return(lapply(x, na_to_null))
  if (inherits(x, "POSIXt")) x <- as.numeric(x)
  if (inherits(x, "Date")) x <- as.character(x)
  if (is.atomic(x) && anyNA(x)) {
    if (length(x) == 1L) return(NULL)
    return(lapply(x, function(value) if (is.na(value)) NULL else value))
  }
  x
}

# File uploads cannot be restored and contain server-only temporary paths.
restorable_values <- function(values) {
  uploads <- vapply(values, function(value) {
    is.list(value) && "datapath" %in% names(value)
  }, logical(1))
  values[!uploads]
}
