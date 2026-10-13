test_that("destroy is idempotent and stops all four observers", {
  shiny::testServer(function(input, output, session) {
    log <- capture_messages(session)
    calls <- new.env()
    calls$save <- 0L
    calls$discard <- 0L
    calls$action <- 0L
    tracker <- unsaved_track("name", on_save = function() {
      calls$save <- calls$save + 1L
      TRUE
    }, on_discard = function() calls$discard <- calls$discard + 1L)
  }, {
    session$setInputs(name = "Ada")
    session$setInputs(name = "Grace")
    tracker$confirm(function() calls$action <- calls$action + 1L)
    request <- tail(log$messages, 1)[[1]]$message
    expect_invisible(tracker$destroy())
    removed <- tail(log$messages, 1)[[1]]
    expect_equal(removed$type, "unsaved:remove")
    expect_equal(removed$message, list(instance = request$instance))
    sent <- length(log$messages)
    expect_invisible(tracker$destroy())
    expect_length(log$messages, sent)
    private <- tracker$.__enclos_env__$private
    expect_null(private$.pending)
    session$setInputs(
      name = "Ada",
      unsaved_save_requested = request,
      unsaved_discard_requested = request,
      unsaved_confirm_requested = c(request, list(choice = "discard"))
    )
    session$flushReact()
    expect_equal(tracker$changed(), "name")
    expect_equal(c(calls$save, calls$discard, calls$action), c(0L, 0L, 0L))
    expect_length(log$messages, sent)
    session$close()
    expect_length(log$messages, sent)
  })
})

test_that("destroy before the first flush cannot recreate client state", {
  shiny::testServer(function(input, output, session) {
    log <- capture_messages(session)
    tracker <- unsaved_track("name")
    tracker$destroy()
  }, {
    session$setInputs(name = "Ada")
    session$flushReact()
    expect_equal(vapply(log$messages, function(x) x$type, character(1)),
                 "unsaved:remove")
  })
})

test_that("session destruction hook registers tracker cleanup when available", {
  skip_if_not_installed("shiny", "1.14.0")
  module <- function(id) {
    shiny::moduleServer(id, function(input, output, session) {
      log <- capture_messages(session)
      tracker <- unsaved_track("name")
    })
  }
  shiny::testServer(module, args = list(id = "editor"), {
    session$setInputs(name = "Ada")
    session$destroy()
    expect_equal(tail(log$messages, 1)[[1]]$type, "unsaved:remove")
  })
})
