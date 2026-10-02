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

changed_inputs <- function(baseline, current) {
  ids <- as.character(intersect(names(baseline), names(current)))
  ids[!vapply(ids, function(id) {
    values_equal(baseline[[id]], current[[id]])
  }, logical(1))]
}

# Preserve saved values across removal; only first appearances join the baseline.
join_baseline <- function(baseline, current) {
  new_ids <- setdiff(names(current), names(baseline))
  c(baseline, current[new_ids])
}
