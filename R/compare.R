# Keep snapshot semantics independent of a Shiny session.
snapshot_inputs <- function(values, inputs = NULL, exclude = NULL) {
  ids <- names(values)
  eligible <- !vapply(values, inherits, logical(1), "shinyActionButtonValue")
  ids <- ids[eligible & !grepl("^(\\.|unsaved_)", ids)]
  if (!is.null(inputs)) ids <- intersect(ids, inputs)
  values[setdiff(ids, exclude)]
}

values_equal <- function(a, b) {
  if (is.null(a) || is.null(b)) return(is.null(a) && is.null(b))
  if (length(a) != length(b)) return(FALSE)
  is_time <- inherits(a, c("Date", "POSIXt")) || inherits(b, c("Date", "POSIXt"))
  if (is_time) {
    return(values_equal(as.character(a), as.character(b)))
  }
  if (is.numeric(a) && is.numeric(b)) {
    same <- all.equal(
      as.numeric(a), as.numeric(b),
      tolerance = 1e-8, check.attributes = FALSE
    )
    return(isTRUE(same))
  }
  if (is.list(a) && is.list(b)) {
    if (!is.null(names(a)) || !is.null(names(b))) {
      names_match <- !is.null(names(a)) && !is.null(names(b)) &&
        !anyDuplicated(names(a)) && !anyDuplicated(names(b)) &&
        setequal(names(a), names(b))
      if (!names_match) return(FALSE)
      b <- b[names(a)]
    }
    return(all(vapply(seq_along(a), function(i) {
      values_equal(a[[i]], b[[i]])
    }, logical(1))))
  }
  isTRUE(all.equal(a, b, check.attributes = FALSE))
}

changed_inputs <- function(baseline, current, compare = NULL) {
  ids <- as.character(intersect(names(baseline), names(current)))
  ids[!vapply(ids, function(id) {
    comparator <- if (is.function(compare)) compare else compare[[id]]
    if (is.null(comparator)) comparator <- values_equal
    same <- comparator(baseline[[id]], current[[id]])
    if (!is.logical(same) || length(same) != 1L || is.na(same)) {
      stop("Comparison for input `", id, "` must return a single non-NA logical.", call. = FALSE)
    }
    same
  }, logical(1))]
}

# Preserve saved values across removal; only first appearances join the baseline.
join_baseline <- function(baseline, current) {
  new_ids <- setdiff(names(current), names(baseline))
  c(baseline, current[new_ids])
}

# A plain data frame with stable list columns, using the tracker's comparison.
input_diff <- function(saved, current, inputs, field_names = NULL,
                       compare = NULL, changed = NULL) {
  if (is.null(changed)) changed <- changed_inputs(saved, current, compare)
  ids <- unname(inputs[inputs %in% changed])
  display <- if (is.null(field_names)) ids else unname(field_names[ids])
  missing_names <- is.na(display) | !nzchar(display)
  display[missing_names] <- ids[missing_names]
  out <- data.frame(name = ids, label = display, change = vapply(ids, function(id) {
    format_change(saved[[id]], current[[id]])
  }, character(1)), stringsAsFactors = FALSE, row.names = NULL)
  out$saved <- unname(lapply(ids, function(id) saved[[id]]))
  out$current <- unname(lapply(ids, function(id) current[[id]]))
  out
}

# Follow rewind's short descriptions without depending on rewind at runtime.
format_change <- function(saved, current) {
  if (is.null(saved) && is.null(current)) return("no change")
  if (is.null(saved)) return(paste("set to", format_value(current)))
  if (is.null(current)) return("cleared")
  paste(format_value(saved), "->", format_value(current))
}

format_value <- function(value, max_items = 3L, max_width = 40L) {
  if (is.null(value)) return("(none)")
  if (is.data.frame(value)) {
    n <- nrow(value)
    return(sprintf("a table of %d row%s", n, if (n == 1L) "" else "s"))
  }
  if (!is.atomic(value)) return(sprintf("a list of %d", length(value)))
  if (!length(value)) return("(empty)")
  text <- if (inherits(value, c("Date", "POSIXt"))) format(value) else as.character(value)
  text[is.na(text)] <- "NA"
  text[text == ""] <- '""'
  if (length(text) == 1L) {
    if (nchar(text) <= max_width) return(text)
    return(paste0(substr(text, 1L, max_width - 3L), "..."))
  }
  if (length(text) <= max_items) {
    joined <- paste(text, collapse = ", ")
    if (nchar(joined) <= max_width) return(joined)
  }
  sprintf("%d values", length(text))
}
