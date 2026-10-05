make_snapshot <- function() list(name = "Ada", number = 1, nested = list(a = 1))

# Browser helpers shared by several test files.
badge_text <- function(app) {
  app$get_js("document.querySelector('.unsaved-badge').textContent")
}

marker_count <- function(app) {
  app$get_js("document.querySelectorAll('[data-unsaved]').length")
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
