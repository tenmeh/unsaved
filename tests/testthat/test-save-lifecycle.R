test_that("mark_saved publishes real state after a saved snapshot", {
  shiny::testServer(function(input, output, session) {
    log <- capture_messages(session)
    tracker <- unsaved_track("name")
  }, {
    session$setInputs(name = "Ada")
    session$setInputs(name = "Grace")
    snapshot <- list(name = "Grace")
    session$setInputs(name = "Later")
    expect_invisible(tracker$mark_saved(snapshot))
    expect_equal(tracker$baseline(), snapshot)
    expect_equal(tracker$changed(), "name")
    expect_equal(tail(log$messages, 1)[[1]]$message$dirty, TRUE)
    expect_equal(tracker$diff()$saved, list("Grace"))
    expect_equal(tracker$diff()$current, list("Later"))
    tracker$mark_saved(list(name = "Other snapshot"))
    expect_equal(tracker$diff()$saved, list("Other snapshot"))
    expect_error(tracker$load_baseline(), "uniquely named list")
    expect_error(tracker$load_baseline(NULL), "uniquely named list")
    expect_error(tracker$load_baseline(list(other = 1)), "Unknown input id")
  })
})

test_that("save requires on_save and handles clean and synchronous results", {
  shiny::testServer(function(input, output, session) {
    log <- capture_messages(session)
    state <- new.env()
    state$calls <- 0L
    state$mode <- TRUE
    tracker <- unsaved_track("name", on_save = function() {
      state$calls <- state$calls + 1L
      state$during <- tracker$is_saving()
      if (identical(state$mode, "error")) stop("save error")
      state$mode
    })
    no_save <- unsaved_track("other")
  }, {
    session$setInputs(name = "Ada", other = "first")
    expect_error(no_save$save(), "requires `on_save`", fixed = TRUE)
    expect_equal(tracker$is_saving(), FALSE)
    sent <- length(log$messages)
    expect_invisible(tracker$save())
    expect_equal(state$calls, 0L)
    expect_length(log$messages, sent)
    for (mode in list(TRUE, FALSE, "error")) {
      state$mode <- mode
      session$setInputs(name = as.character(mode))
      if (identical(mode, TRUE)) {
        expect_no_warning(tracker$save())
      } else {
        expect_warning(tracker$save(), "on_save() failed", fixed = TRUE)
      }
      expect_equal(state$during, TRUE)
      expect_equal(tracker$is_saving(), FALSE)
      expect_equal(tracker$is_dirty(), !identical(mode, TRUE))
      expect_equal(tracker$baseline(), list(name = "TRUE"))
    }
    expect_equal(state$calls, 3L)
    expect_length(save_replies(log), 0L)
  })
})

test_that("save promises expose pending state and settle TRUE FALSE or rejection", {
  shiny::testServer(function(input, output, session) {
    log <- capture_messages(session)
    state <- new.env()
    tracker <- unsaved_track("name", on_save = function() {
      promises::promise(function(resolve, reject) {
        state$resolve <- resolve
        state$reject <- reject
      })
    })
    saving <- shiny::reactive(tracker$is_saving())
  }, {
    session$setInputs(name = "Ada")
    expect_equal(saving(), FALSE)
    for (mode in c("true", "false", "reject")) {
      session$setInputs(name = mode)
      tracker$save()
      expect_equal(saving(), TRUE)
      expect_warning(tracker$save(), "already pending")
      session$setInputs(name = paste(mode, "later"))
      if (mode == "true") {
        state$resolve(TRUE)
        settle_save(session)
      } else {
        if (mode == "false") state$resolve(FALSE) else state$reject(simpleError("rejected"))
        expect_warning(settle_save(session), "on_save() promise", fixed = TRUE)
      }
      expect_equal(saving(), FALSE)
      expect_equal(tracker$baseline(), list(name = "true"))
      expect_equal(tracker$is_dirty(), TRUE)
    }
    tracker$save()
    tracker$destroy()
    expect_equal(saving(), FALSE)
    sent <- length(log$messages)
    state$resolve(TRUE)
    settle_save(session)
    expect_length(log$messages, sent)
  })
})

test_that("destroyed commands do nothing before validating arguments", {
  shiny::testServer(function(input, output, session) {
    log <- capture_messages(session)
    tracker <- unsaved_track("name")
  }, {
    session$setInputs(name = "Ada")
    session$setInputs(name = "Grace")
    tracker$destroy()
    before <- tracker$baseline()
    sent <- length(log$messages)
    commands <- list(
      function() tracker$mark_saved(1), function() tracker$load_baseline(),
      function() tracker$save(), function() tracker$discard(),
      function() tracker$pause(), function() tracker$resume(),
      function() tracker$confirm(NULL, text = 1), function() tracker$ask_reason(NULL),
      function() tracker$destroy()
    )
    for (command in commands) {
      expect_identical(withVisible(command()), list(value = tracker, visible = FALSE))
    }
    session$flushReact()
    expect_length(log$messages, sent)
    expect_equal(tracker$baseline(), before)
    expect_equal(tracker$is_paused(), FALSE)
  })
})

test_that("confirm action errors warn and leave the session alive", {
  shiny::testServer(function(input, output, session) {
    log <- capture_messages(session)
    tracker <- unsaved_track("name", on_save = function() TRUE)
    action <- function() stop("private action error")
  }, {
    session$setInputs(name = "Ada")
    expect_warning(tracker$confirm(action), "confirmation action failed")
    expect_error(tracker$confirm(action, text = "bad"), "unsaved_text")
    for (choice in c("discard", "save")) {
      session$setInputs(name = choice)
      tracker$confirm(action, text = unsaved_text(title = "This action"))
      request <- tail(log$messages, 1)[[1]]$message
      expect_equal(request$text$title, "This action")
      if (choice == "save") session$setInputs(unsaved_save_requested = request)
      expect_warning(session$setInputs(unsaved_confirm_requested = c(request, list(choice = choice))),
                     "confirmation action failed")
      expect_equal(session$isClosed(), FALSE)
      tracker$mark_saved()
    }
    session$setInputs(name = "Still alive")
    expect_equal(tracker$is_dirty(), TRUE)
    tracker$confirm(function() NULL)
    expect_null(tail(log$messages, 1)[[1]]$message$text)
  })
})

test_that("untracked inputs do not reevaluate tracker values", {
  shiny::testServer(function(input, output, session) {
    log <- capture_messages(session)
    calls <- new.env()
    calls$n <- 0L
    value <- shiny::reactive(1)
    # Count reads of the values reactive, including reads from an invalidated current().
    counted <- function() {
      calls$n <- calls$n + 1L
      value()
    }
    class(counted) <- class(value)
    tracker <- unsaved_track("name", list(Value = counted))
  }, {
    session$setInputs(name = "Ada")
    expect_equal(tracker$baseline(), list(name = "Ada", Value = 1))
    before <- calls$n
    sent <- length(log$messages)
    session$setInputs(untracked = "change")
    tracker$diff()
    expect_equal(calls$n, before)
    expect_length(log$messages, sent)
    session$setInputs(name = "Grace")
    expect_equal(calls$n, before + 1L)
    expect_equal(tracker$changed(), "name")
  })
})

test_that("custom table comparison has a truthful summary fallback", {
  shiny::testServer(function(input, output, session) {
    value <- shiny::reactiveVal(data.frame(x = 1))
    tracker <- unsaved_track(values = list(Table = value), compare = list(Table = identical))
  }, {
    session$flushReact()
    value(data.frame(x = 1 + 1e-10))
    session$flushReact()
    expect_equal(tracker$is_dirty(), TRUE)
    expect_equal(tracker$diff()$change, "table changed")
    expect_identical(tracker$diff()$saved, list(data.frame(x = 1)))
    expect_identical(tracker$diff()$current, list(data.frame(x = 1 + 1e-10)))
  })
})

test_that("managed reason save keeps its dialog slot until completion or cancellation", {
  shiny::testServer(function(input, output, session) {
    log <- capture_messages(session)
    state <- new.env()
    tracker <- unsaved_track("name", on_save = function(reason) {
      state$reason <- reason
      promises::promise(function(resolve, reject) state$resolve <- resolve)
    }, require_reason = TRUE)
  }, {
    session$setInputs(name = "Ada")
    session$setInputs(name = "Grace")
    tracker$save()
    request <- tail(log$messages, 1)[[1]]$message
    expect_equal(request$saveMode, TRUE)
    expect_equal(request$reasonOnly, TRUE)
    expect_equal(tracker$is_saving(), FALSE)
    expect_warning(tracker$save(), "already open")
    session$setInputs(unsaved_save_requested = c(request, list(reason = "  Correction  ")))
    expect_equal(state$reason, "Correction")
    expect_equal(tracker$is_saving(), TRUE)
    expect_warning(tracker$save(), "already pending")
    session$setInputs(unsaved_confirm_requested = c(request, list(choice = "keep")))
    expect_warning(tracker$confirm(function() NULL), "already open")
    state$resolve(FALSE)
    expect_warning(settle_save(session), "must resolve to TRUE")
    expect_equal(tail(save_replies(log), 1)[[1]]$message$ok, FALSE)
    expect_equal(tracker$is_saving(), FALSE)
    session$setInputs(unsaved_save_requested = c(request, list(reason = "Retry", at = 2)))
    state$resolve(TRUE)
    settle_save(session)
    expect_equal(tracker$is_dirty(), FALSE)
    expect_equal(tail(save_replies(log), 1)[[1]]$message$ok, TRUE)
    session$setInputs(unsaved_confirm_requested = c(request, list(choice = "save")))
    session$setInputs(name = "Next")
    tracker$save()
    request <- tail(log$messages, 1)[[1]]$message
    session$setInputs(unsaved_confirm_requested = c(request, list(choice = "keep")))
    expect_no_warning(tracker$save())
  })
})
