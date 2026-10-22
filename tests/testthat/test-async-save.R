test_that("promise results acknowledge TRUE and warn once for each failure", {
  skip_if_not_installed("promises")
  skip_if_not_installed("later")
  shiny::testServer(function(input, output, session) {
    log <- capture_messages(session)
    state <- new.env()
    tracker <- unsaved_track("name", on_save = function() {
      if (identical(state$mode, "reject")) {
        promises::promise_reject(simpleError("private rejection detail"))
      } else {
        promises::promise_resolve(state$value)
      }
    })
  }, {
    session$setInputs(name = "Ada")
    instance <- log$messages[[1]]$message$instance
    for (mode in c("true", "false", "reject", "na")) {
      state$mode <- mode
      state$value <- switch(mode, true = TRUE, false = FALSE, na = NA)
      session$setInputs(name = mode)
      warnings <- character()
      withCallingHandlers({
        session$setInputs(unsaved_save_requested = list(instance = instance, at = mode))
        settle_save(session)
      }, warning = function(w) {
        warnings <<- c(warnings, conditionMessage(w))
        invokeRestart("muffleWarning")
      })
      ok <- identical(mode, "true")
      expect_length(warnings, if (ok) 0L else 1L)
      if (!ok) {
        expected <- switch(mode, false = "resolved to FALSE", na = "resolved to NA",
                           reject = "rejected: private rejection detail")
        expect_match(warnings, expected, fixed = TRUE)
      }
      expect_equal(tracker$baseline(), list(name = "true"))
      expect_equal(tracker$is_dirty(), !ok)
      expect_equal(tail(save_replies(log), 1)[[1]]$message,
                   list(instance = instance, ok = ok))
    }
    expect_length(save_replies(log), 4L)
  })
})

test_that("edits during a pending save stay dirty and duplicate requests are ignored", {
  skip_if_not_installed("promises")
  skip_if_not_installed("later")
  shiny::testServer(function(input, output, session) {
    log <- capture_messages(session)
    state <- new.env()
    state$calls <- 0L
    tracker <- unsaved_track("name", on_save = function() {
      state$calls <- state$calls + 1L
      promises::promise(function(resolve, reject) state$resolve <- resolve)
    })
  }, {
    session$setInputs(name = "Ada")
    instance <- log$messages[[1]]$message$instance
    session$setInputs(name = "Grace")
    session$setInputs(unsaved_save_requested = list(instance = instance, at = 1))
    expect_length(save_replies(log), 0L)
    expect_equal(tracker$baseline(), list(name = "Ada"))
    session$setInputs(name = "Later edit")
    expect_warning(
      session$setInputs(unsaved_save_requested = list(instance = instance, at = 2)),
      "A save is already pending", fixed = TRUE
    )
    expect_equal(state$calls, 1L)
    state$resolve(TRUE)
    settle_save(session)
    expect_equal(tracker$baseline(), list(name = "Grace"))
    expect_equal(tracker$is_dirty(), TRUE)
    expect_equal(tracker$changed(), "name")
    states <- Filter(function(sent) sent$type == "unsaved:state", log$messages)
    expect_equal(tail(states, 1)[[1]]$message$dirty, TRUE)
    expect_length(save_replies(log), 1L)
    expect_equal(save_replies(log)[[1]]$message$ok, TRUE)
    session$setInputs(unsaved_save_requested = list(instance = instance, at = 3))
    expect_equal(state$calls, 2L)
    state$resolve(TRUE)
    settle_save(session)
    expect_equal(tracker$is_dirty(), FALSE)
    expect_length(save_replies(log), 2L)
  })
})
