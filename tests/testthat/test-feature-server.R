test_that("new tracker arguments validate", {
  session <- shiny::MockShinySession$new()
  on.exit(session$close())
  for (bad in list(NULL, list(), "text")) {
    expect_error(unsaved_track("x", text = bad, session = session), "unsaved_text")
  }
  for (bad in list(1, FALSE, function(x) x, function(...) NULL, sum)) {
    expect_error(unsaved_track("x", on_discard = bad, session = session), "function with no arguments")
  }
  for (bad in list(1, list(identity), list(y = identical), list(x = 1),
                   setNames(list(identical, identical), c("x", "x")))) {
    expect_error(unsaved_track("x", compare = bad, session = session), "compare", fixed = TRUE)
  }
})

test_that("server discard calls once and catches errors with baseline available", {
  shiny::testServer(function(input, output, session) {
    log <- capture_messages(session)
    state <- new.env()
    state$calls <- 0L
    state$fail <- FALSE
    tracker <- unsaved_track(
      "name", text = unsaved_text(title = "Profile"),
      compare = list(name = unsaved_compare_text()), on_discard = function() {
        state$calls <- state$calls + 1L
        state$baseline <- tracker$baseline()
        state$current <- input$name
        if (state$fail) stop("discard failure")
      }
    )
  }, {
    session$setInputs(name = "Ada")
    config <- Filter(function(sent) sent$type == "unsaved:config", log$messages)[[1]]$message
    expect_equal(config$text$title, "Profile")
    expect_equal(config$navInput, session$ns("unsaved_nav_blocked"))
    expect_equal(config$discardInput, session$ns("unsaved_discard_requested"))
    session$setInputs(name = " Ada ")
    expect_equal(tracker$is_dirty(), FALSE)
    session$setInputs(name = "Grace")
    expect_equal(tracker$is_dirty(), TRUE)
    tracker$discard()
    expect_equal(state$calls, 1L)
    expect_equal(state$baseline, list(name = "Ada"))
    expect_equal(state$current, "Grace")
    session$setInputs(unsaved_discard_requested = list(instance = "other"))
    expect_equal(state$calls, 1L)
    session$setInputs(unsaved_discard_requested = list(instance = config$instance, at = 1))
    expect_equal(state$calls, 2L)
    state$fail <- TRUE
    expect_warning(tracker$discard(), "on_discard() failed: discard failure", fixed = TRUE)
    expect_equal(state$calls, 3L)
    session$setInputs(name = "Ada")
    expect_equal(tracker$is_dirty(), FALSE)
  })
})

test_that("module server compares local ids and sends namespaced configuration", {
  module <- function(id) {
    shiny::moduleServer(id, function(input, output, session) {
      log <- capture_messages(session)
      tracker <- unsaved_track("name", compare = list(name = unsaved_compare_text()))
    })
  }
  shiny::testServer(module, args = list(id = "first"), {
    session$setInputs(name = "Ada")
    config <- Filter(function(sent) sent$type == "unsaved:config", log$messages)[[1]]$message
    expect_equal(config$navInput, "first-unsaved_nav_blocked")
    expect_equal(config$saveInput, "first-unsaved_save_requested")
    expect_equal(config$discardInput, "first-unsaved_discard_requested")
    expect_named(config$baseline, "first-name")
    session$setInputs(name = " Ada ")
    expect_equal(tracker$is_dirty(), FALSE)
    session$setInputs(name = "Grace")
    expect_equal(tracker$changed(), "name")
    tracker$discard()
    expect_equal(tail(log$messages, 1)[[1]]$message$inputs, list("first-name" = "Ada"))
  })
})
