test_that("confirm validates actions and runs clean or paused actions immediately", {
  shiny::testServer(function(input, output, session) {
    tracker <- unsaved_track("name")
    state <- new.env()
    state$calls <- 0L
    action <- function() state$calls <- state$calls + 1L
  }, {
    session$setInputs(name = "Ada", unsaved_password_ids = list(ids = character()))
    for (bad in list(NULL, 1, function(x) x, sum)) {
      expect_error(tracker$confirm(bad), "function with no arguments")
    }
    expect_invisible(tracker$confirm(action))
    expect_equal(state$calls, 1L)
    session$setInputs(name = "Grace")
    tracker$pause()
    tracker$confirm(action)
    expect_equal(state$calls, 2L)
  })
})

test_that("confirm cancels, discards or saves once and rejects stale replies", {
  shiny::testServer(function(input, output, session) {
    log <- capture_messages(session)
    state <- new.env()
    state$calls <- 0L
    state$discards <- 0L
    state$save_ok <- FALSE
    tracker <- unsaved_track("name", on_save = function() state$save_ok,
                             on_discard = function() state$discards <- state$discards + 1L)
    action <- function() {
      state$calls <- state$calls + 1L
      state$value <- input$name
    }
  }, {
    session$setInputs(name = "Ada")
    session$setInputs(name = "Grace")
    request <- function() {
      tracker$confirm(action)
      messages <- Filter(function(sent) sent$type == "unsaved:confirm", log$messages)
      tail(messages, 1)[[1]]$message
    }
    reply <- function(message, choice) {
      session$setInputs(unsaved_confirm_requested = c(message, list(choice = choice)))
    }
    first <- request()
    reply(first, "keep")
    expect_equal(state$calls, 0L)
    second <- request()
    reply(first, "discard")
    expect_equal(state$calls, 0L)
    session$setInputs(name = "Ada")
    reply(second, "discard")
    reply(second, "discard")
    expect_equal(state$calls, 1L)
    expect_equal(state$discards, 1L)
    expect_equal(state$value, "Ada")
    session$setInputs(name = "Next")
    third <- request()
    session$setInputs(unsaved_save_requested = third)
    expect_equal(tracker$is_dirty(), TRUE)
    expect_equal(state$calls, 1L)
    state$save_ok <- TRUE
    session$setInputs(unsaved_save_requested = c(third, list(at = 2)))
    reply(third, "save")
    expect_equal(state$calls, 2L)
    expect_equal(state$value, "Next")
    expect_equal(tracker$is_dirty(), FALSE)
  })
})

test_that("a second pending confirm warns and only the first action runs once", {
  shiny::testServer(function(input, output, session) {
    log <- capture_messages(session)
    tracker <- unsaved_track("name")
    state <- new.env()
    state$first <- 0L
    state$second <- 0L
    first_action <- function() state$first <- state$first + 1L
    second_action <- function() state$second <- state$second + 1L
  }, {
    session$setInputs(name = "Ada")
    session$setInputs(name = "Grace")
    tracker$confirm(first_action)
    expect_warning(
      tracker$confirm(second_action),
      "A confirmation is already open, so this action was not run.",
      fixed = TRUE
    )
    requests <- Filter(function(sent) sent$type == "unsaved:confirm", log$messages)
    expect_length(requests, 1L)
    expect_equal(state$first, 0L)
    expect_equal(state$second, 0L)
    request <- c(requests[[1]]$message, list(choice = "discard"))
    session$setInputs(name = "Ada", unsaved_confirm_requested = request)
    session$setInputs(unsaved_confirm_requested = request)
    expect_equal(state$first, 1L)
    expect_equal(state$second, 0L)
  })
})

test_that("guard tags preserve their attributes and dependencies", {
  tag <- htmltools::tags$a(href = "#record", class = "link", "Record")
  guarded <- unsaved_guard(tag)
  expect_equal(guarded$attribs$href, "#record")
  expect_equal(guarded$attribs$class, "link")
  expect_equal(guarded$attribs[["data-unsaved-guard"]], "")
  expect_equal(htmltools::htmlDependencies(guarded)[[1]]$name, "unsaved")
  expect_error(unsaved_guard("button"), "htmltools tag")
})
