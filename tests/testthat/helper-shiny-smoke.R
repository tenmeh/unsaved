# Use the same three error surfaces and deferred cleanup as rewind.
collect_shiny_problems <- function(app) {
  problems <- character()
  logs <- as.data.frame(app$get_logs())
  if (nrow(logs) > 0 && all(c("location", "message") %in% names(logs))) {
    is_r_error <- logs$location == "shiny" & grepl("Error", logs$message, fixed = TRUE)
    from_r <- logs$message[is_r_error]
    if (length(from_r) > 0) {
      problems <- c(problems, paste("R stderr:", from_r))
    }
    if ("level" %in% names(logs)) {
      is_error <- !is.na(logs$level) & logs$level == "error"
      from_browser <- logs$message[is_error & logs$location == "chromote"]
      if (length(from_browser) > 0) {
        problems <- c(problems, paste("Browser console:", from_browser))
      }
    }
  }
  in_dom <- app$get_html(".shiny-output-error")
  if (!is.null(in_dom)) {
    problems <- c(problems, paste("Output element in an error state:", in_dom))
  }
  problems
}

expect_no_shiny_errors <- function(app) {
  problems <- collect_shiny_problems(app)
  testthat::expect_equal(
    length(problems), 0L,
    info = paste(problems, collapse = "\n")
  )
  invisible(app)
}

# Write a throwaway app and delete it when the calling test ends.
local_app_file <- function(lines, prefix, .local_envir = parent.frame()) {
  root <- Sys.getenv("UNSAVED_BROWSER_TMP", unset = tempdir())
  path <- tempfile(prefix, tmpdir = root)
  dir.create(path)
  writeLines(lines, file.path(path, "app.R"))
  withr::defer(unlink(path, recursive = TRUE), envir = .local_envir)
  path
}

local_app_driver <- function(app_dir, ..., .local_envir = parent.frame()) {
  testthat::skip_if_not_installed("shinytest2")
  testthat::skip_if_not_installed("withr")
  chrome_root <- Sys.getenv(
    "UNSAVED_BROWSER_TMP",
    unset = tools::R_user_dir("unsaved", "cache")
  )
  chrome_tmp <- tempfile("chromote-", tmpdir = chrome_root)
  dir.create(chrome_tmp, showWarnings = FALSE, recursive = TRUE)
  withr::local_envvar(
    c(TMPDIR = chrome_tmp, TMP = chrome_tmp, TEMP = chrome_tmp),
    .local_envir = .local_envir
  )
  app <- tryCatch(shinytest2::AppDriver$new(app_dir, ...), error = function(e) {
    unlink(chrome_tmp, recursive = TRUE)
    if (identical(Sys.getenv("NOT_CRAN"), "true")) stop(e)
    testthat::skip(paste("Could not start a headless browser:", conditionMessage(e)))
  })
  withr::defer({
    app$stop()
    unlink(chrome_tmp, recursive = TRUE)
  }, envir = .local_envir)
  app
}
