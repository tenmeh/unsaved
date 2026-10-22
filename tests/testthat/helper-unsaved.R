make_snapshot <- function() list(name = "Ada", number = 1, nested = list(a = 1))

save_replies <- function(log) {
  Filter(function(sent) sent$type == "unsaved:saved", log$messages)
}

settle_save <- function(session) {
  for (i in seq_len(10L)) {
    later::run_now(0)
    session$flushReact()
  }
}

# Browser helpers shared by several test files.
badge_text <- function(app) {
  app$get_js("document.querySelector('.unsaved-badge').textContent")
}

marker_count <- function(app) {
  app$get_js("document.querySelectorAll('[data-unsaved]').length")
}

# Wait until the page has sent the trackers' field report. A tracker takes its
# saved values when that report arrives, so an edit made by a test before then
# would count as saved. A person cannot type that fast; a test can.
wait_for_tracker <- function(app, timeout = 10000) {
  app$wait_for_js(
    paste0(
      "Object.keys(Shiny.shinyapp.$inputValues).some(function (k) {",
      " return /unsaved_password_ids$/.test(k); })"
    ),
    timeout = timeout
  )
  app$wait_for_idle()
  invisible(app)
}

capture_messages <- function(session) {
  # Emulate the initial client report; do not flush module inputs through root.
  session$setInputs(unsaved_password_ids = character())
  session <- session$rootScope()
  log <- new.env(parent = emptyenv())
  log$messages <- list()
  if (bindingIsLocked("sendCustomMessage", session)) {
    unlockBinding("sendCustomMessage", session)
  }
  session$sendCustomMessage <- function(type, message) {
    log$messages[[length(log$messages) + 1L]] <- list(type = type, message = message)
  }
  log
}
