`%||%` <- function(x, y) if (is.null(x)) y else x

require_session <- function(session) {
  if (is.null(session)) {
    stop(
      "No Shiny session found. Call unsaved_track() inside your server function.",
      call. = FALSE
    )
  }
  capabilities <- c("ns", "rootScope", "sendCustomMessage", "sendInsertUI",
                    "onFlushed", "onSessionEnded")
  valid <- (is.environment(session) || is.list(session)) &&
    all(vapply(capabilities, function(name) is.function(session[[name]]), logical(1))) &&
    shiny::is.reactivevalues(session$input)
  if (!valid) {
    stop("`session` must be a Shiny session; got ",
         if (is.numeric(session)) "a numeric value" else describe_value(session),
         ".", call. = FALSE)
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

# Keep diagnostics bounded and avoid printing arbitrary objects or payloads.
describe_value <- function(value) {
  if (is.null(value)) return("NULL")
  if (is.object(value)) return(paste0("an object of class ", paste(class(value), collapse = "/")))
  if (is.atomic(value) && length(value) == 1L) {
    if (is.character(value)) return(encodeString(substr(value, 1L, 60L), quote = '"'))
    return(as.character(value))
  }
  paste0(typeof(value), " (length ", length(value), ")")
}

check_flag <- function(value, name) {
  if (!is.logical(value) || length(value) != 1L || is.na(value)) {
    stop("`", name, "` must be TRUE or FALSE; got ", describe_value(value), ".", call. = FALSE)
  }
  invisible(NULL)
}

check_callback <- function(value, name, allow_null = TRUE) {
  if (allow_null && is.null(value)) return(invisible(NULL))
  if (!is.function(value) || is.primitive(value) || length(formals(value)) != 0L) {
    stop("`", name, "` must be ", if (allow_null) "NULL or " else "",
         "a function with no arguments.", call. = FALSE)
  }
  invisible(NULL)
}
