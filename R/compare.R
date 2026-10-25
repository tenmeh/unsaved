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
    summary <- format_change(saved[[id]], current[[id]])
    if (identical(summary, "no change") && is.data.frame(saved[[id]]) && is.data.frame(current[[id]])) {
      summary <- "table changed"
    }
    summary
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
  if (is.data.frame(saved) && is.data.frame(current) &&
        identical(names(saved), names(current)) && nrow(saved) == nrow(current)) {
    cells <- character()
    # Skip identical columns first, so a large table costs little per diff().
    changed_columns <- which(!vapply(seq_along(saved), function(column) {
      identical(saved[[column]], current[[column]])
    }, logical(1)))
    positions <- lapply(changed_columns, function(column) {
      which(!cell_values_equal(saved[[column]], current[[column]]))
    })
    count <- sum(lengths(positions))
    if (!count) return("no change")
    # Count with vectors; only inspect the first three cells in row order.
    first <- data.frame(
      row = unlist(lapply(positions, utils::head, 3L)),
      column = rep(changed_columns, pmin(lengths(positions), 3L))
    )
    first <- utils::head(first[order(first$row, first$column), , drop = FALSE], 3L)
    for (i in seq_len(nrow(first))) {
      row <- first$row[i]
      column <- first$column[i]
      cells <- c(cells, sprintf("row %d, %s: %s -> %s", row, names(saved)[column],
                                format_value(saved[[column]][[row]]),
                                format_value(current[[column]][[row]])))
    }
    if (count > 3L) cells <- c(cells, sprintf("and %d more cells", count - 3L))
    return(paste(cells, collapse = "; "))
  }
  paste(format_value(saved), "->", format_value(current))
}

# Match scalar comparison, including its near-zero tolerance and missing values.
cell_values_equal <- function(saved, current) {
  numeric_pair <- is.numeric(saved) && is.numeric(current)
  if (is.list(saved) || is.list(current) || is.object(saved) || is.object(current) ||
        is.complex(saved) || is.complex(current) ||
        (!numeric_pair && typeof(saved) != typeof(current))) {
    return(vapply(seq_along(saved), function(i) values_equal(saved[[i]], current[[i]]), logical(1)))
  }
  same <- saved == current
  same[is.na(same)] <- FALSE
  missing <- is.na(saved) | is.na(current)
  same[missing] <- is.na(saved[missing]) & is.na(current[missing])
  if (numeric_pair) {
    finite <- is.finite(saved) & is.finite(current)
    scale <- ifelse(abs(saved[finite]) > 1e-8, abs(saved[finite]), 1)
    same[finite] <- abs(saved[finite] - current[finite]) / scale <= 1e-8
  }
  same
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
