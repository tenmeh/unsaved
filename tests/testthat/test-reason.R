test_that("reason callbacks and flags are validated", {
  session <- shiny::MockShinySession$new()
  on.exit(session$close())
  for (bad in list(1, function() TRUE, function(x) TRUE, function(...) TRUE,
                   function(reason, extra) TRUE)) {
    expect_error(unsaved_track("x", require_reason = TRUE, on_save = bad,
                               session = session), "exactly one argument, `reason`")
  }
  expect_error(unsaved_track("x", require_reason = NA, session = session), "TRUE or FALSE")
  expect_error(unsaved_track("x", on_save = function(reason) TRUE,
                             session = session), "no arguments")
})

test_that("required reasons reach on_save trimmed bounded and never return to the browser", {
  shiny::testServer(function(input, output, session) {
    log <- capture_messages(session)
    received <- shiny::reactiveVal(NULL)
    tracker <- unsaved_track(
      "name", require_reason = TRUE,
      on_save = function(reason) {
        received(reason)
        TRUE
      }
    )
  }, {
    session$setInputs(name = "Ada")
    session$setInputs(name = "Grace")
    config <- Filter(function(x) x$type == "unsaved:config", log$messages)[[1]]$message
    expect_equal(config$requireReason, TRUE)
    send <- function(reason) {
      session$setInputs(unsaved_save_requested = list(instance = config$instance, reason = reason))
    }
    for (bad in list(NULL, "", " \n\t ", NA_character_, c("a", "b"), 2)) {
      send(bad)
      expect_null(received())
      expect_equal(tracker$is_dirty(), TRUE)
    }
    send("  corrected source record  \n")
    expect_equal(received(), "corrected source record")
    expect_equal(tracker$is_dirty(), FALSE)
    send(paste0(" ", strrep("x", 1100), " "))
    expect_equal(nchar(received()), 1000L)
    payloads <- vapply(log$messages, function(x) {
      paste(capture.output(str(x)), collapse = "")
    }, character(1))
    expect_equal(any(grepl("corrected source record", payloads)), FALSE)
  })
})

test_that("ask_reason cancels saves once and ignores stale or invalid replies", {
  shiny::testServer(function(input, output, session) {
    log <- capture_messages(session)
    received <- shiny::reactiveVal(character())
    tracker <- unsaved_track("name")
    action <- function(reason) received(c(received(), reason))
  }, {
    session$setInputs(name = "Ada")
    for (bad in list(NULL, 1, function() NULL, function(...) NULL)) {
      expect_error(tracker$ask_reason(bad), "exactly one argument")
    }
    request <- function() {
      expect_invisible(tracker$ask_reason(action))
      tail(Filter(function(x) x$type == "unsaved:confirm", log$messages), 1)[[1]]$message
    }
    reply <- function(message, choice, reason = NULL) {
      session$setInputs(unsaved_confirm_requested = c(message, list(choice = choice, reason = reason)))
    }
    first <- request()
    expect_equal(first$reasonOnly, TRUE)
    expect_warning(tracker$ask_reason(action), "already open")
    reply(first, "keep")
    expect_length(received(), 0L)
    second <- request()
    reply(first, "save", "stale")
    reply(second, "discard")
    reply(second, "save", "  ")
    expect_length(received(), 0L)
    reply(second, "save", "  corrected  ")
    reply(second, "save", "duplicate")
    expect_equal(received(), "corrected")
    third <- request()
    tracker$destroy()
    reply(third, "save", "destroyed")
    expect_equal(received(), "corrected")
  })
})

test_that("reason callback errors do not disclose the reason in package warnings", {
  shiny::testServer(function(input, output, session) {
    log <- capture_messages(session)
    tracker <- unsaved_track(
      "name", require_reason = TRUE, on_save = function(reason) stop(reason)
    )
  }, {
    session$setInputs(name = "Ada")
    config <- Filter(function(x) x$type == "unsaved:config", log$messages)[[1]]$message
    request <- list(instance = config$instance, reason = "PRIVATE")
    expect_warning(
      session$setInputs(unsaved_save_requested = request),
      "on_save() failed. The changes are kept as unsaved.", fixed = TRUE
    )
  })
})
