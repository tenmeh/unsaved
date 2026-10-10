test_that("the tracker signature keeps session last", {
  expect_named(formals(unsaved_track), c(
    "inputs", "guard_nav", "guard_unload", "guard_clicks", "on_save", "on_discard",
    "compare", "text", "session"
  ))
})

test_that("tracking requires a session and validates arguments", {
  expect_error(unsaved_track("x", session = NULL), "No Shiny session found", fixed = TRUE)
  session <- shiny::MockShinySession$new()
  on.exit(session$close())
  for (inputs in list(NULL, character(), 1, NA_character_, "")) {
    expect_error(unsaved_track(inputs, session = session), "at least one non-empty input id")
  }
  expect_error(unsaved_track(session = session), "at least one non-empty input id")
  for (callback in list(1, FALSE, function(x) x, function(...) NULL, sum)) {
    expect_error(unsaved_track("x", on_save = callback, session = session), "function with no arguments")
  }
  expect_error(unsaved_track(inputs = 1, session = session), "at least one non-empty input id")
  expect_error(unsaved_track("x", guard_nav = NA, session = session), "TRUE or FALSE")
})

test_that("file paths never appear in configuration or restore payloads", {
  shiny::testServer(function(input, output, session) {
    messages <- list()
    if (bindingIsLocked("sendCustomMessage", session)) {
      unlockBinding("sendCustomMessage", session)
    }
    session$sendCustomMessage <- function(type, message) {
      messages[[length(messages) + 1L]] <<- list(type = type, message = message)
    }
    tracker <- unsaved_track(c("file", "name"))
  }, {
    upload <- data.frame(
      name = "example.csv", size = 10, type = "text/csv",
      datapath = "/private/server/upload.csv"
    )
    session$setInputs(file = upload, name = "Ada", unsaved_password_ids = character())
    tracker$mark_saved()
    tracker$discard()
    expect_equal(tracker$baseline()$file, upload)
    for (sent in messages) {
      if (sent$type == "unsaved:config") expect_null(sent$message$baseline$file)
      if (sent$type == "unsaved:restore") expect_null(sent$message$inputs$file)
    }
    expect_equal(restorable_values(list(file = upload, name = "Ada")), list(name = "Ada"))
  })
})

test_that("client tab metadata excludes even explicitly requested tab inputs", {
  shiny::testServer(function(input, output, session) {
    tracker <- unsaved_track(c("tabs", "name"))
  }, {
    session$setInputs(tabs = "form", name = "Ada", unsaved_tab_ids = session$ns("tabs"),
                      unsaved_password_ids = list(ids = character()))
    session$setInputs(tabs = "other")
    expect_equal(tracker$changed(), character())
    tracker$mark_saved()
    expect_named(tracker$baseline(), "name")
  })
})

test_that("late tab metadata removes initial navigation values from saved snapshots", {
  shiny::testServer(function(input, output, session) {
    tracker <- unsaved_track(c("tabs", "name"))
  }, {
    session$setInputs(tabs = "form", name = "Ada", unsaved_password_ids = list(ids = character()))
    session$setInputs(unsaved_tab_ids = session$ns("tabs"))
    expect_named(tracker$baseline(), "name")
    session$setInputs(tabs = "other")
    expect_equal(tracker$is_dirty(), FALSE)
    tracker$mark_saved()
    expect_named(tracker$baseline(), "name")
  })
})

test_that("listed late fields join the server and client baselines", {
  shiny::testServer(function(input, output, session) {
    log <- capture_messages(session)
    tracker <- unsaved_track(c("name", "late"))
  }, {
    session$setInputs(name = "Ada")
    session$setInputs(late = "first")
    expect_equal(tracker$baseline()$late, "first")
    expect_equal(tracker$is_dirty(), FALSE)
    configs <- Filter(function(sent) sent$type == "unsaved:config", log$messages)
    expect_equal(tail(configs, 1)[[1]]$message$baseline[[session$ns("late")]], "first")
    session$setInputs(late = "edited")
    expect_equal(tracker$changed(), "late")
    tracker$discard()
    restore <- tail(log$messages, 1)[[1]]
    expect_equal(restore$message$inputs[[session$ns("late")]], "first")
    tracker$mark_saved()
    expect_equal(tracker$baseline()$late, "edited")
  })
})

test_that("save callbacks acknowledge success and keep baselines on failure", {
  shiny::testServer(function(input, output, session) {
    log <- capture_messages(session)
    # testServer() copies plain locals into the test scope; an environment is
    # shared by reference, so the test can read calls and change the mode.
    save_state <- new.env()
    save_state$mode <- "success"
    save_state$calls <- 0L
    tracker <- unsaved_track("name", on_save = function() {
      save_state$calls <- save_state$calls + 1L
      if (save_state$mode == "error") stop("private error detail")
      if (save_state$mode == "false") return(FALSE)
      TRUE
    })
  }, {
    session$setInputs(name = "Ada")
    config <- Filter(function(sent) sent$type == "unsaved:config", log$messages)[[1]]$message
    expect_equal(config$canSave, TRUE)
    session$setInputs(name = "Grace")
    session$setInputs(unsaved_save_requested = list(instance = "other", target = "tab", at = 1))
    expect_equal(save_state$calls, 0L)
    session$setInputs(unsaved_save_requested = list(instance = config$instance, target = "tab", at = 2))
    expect_equal(save_state$calls, 1L)
    expect_equal(tracker$baseline()$name, "Grace")
    expect_equal(tracker$is_dirty(), FALSE)
    # Other observers may send state messages after the reply, so look for
    # the latest save reply rather than the latest message.
    last_reply <- function() {
      replies <- Filter(function(sent) sent$type == "unsaved:saved", log$messages)
      tail(replies, 1)[[1]]$message
    }
    expect_equal(last_reply()$ok, TRUE)
    for (failure in c("false", "error")) {
      save_state$mode <- failure
      session$setInputs(name = failure)
      session$setInputs(unsaved_save_requested = list(instance = config$instance, target = "tab", at = failure))
      expect_equal(last_reply(), list(instance = config$instance, ok = FALSE))
      expect_equal(tracker$baseline()$name, "Grace")
      expect_equal(tracker$is_dirty(), TRUE)
    }
  })
})
test_that("asynchronous save results warn and keep changes unsaved", {
  skip_if_not_installed("promises")
  shiny::testServer(function(input, output, session) {
    log <- capture_messages(session)
    result <- new.env()
    result$value <- promises::promise_resolve(TRUE)
    tracker <- unsaved_track("name", on_save = function() result$value)
  }, {
    session$setInputs(name = "Ada")
    session$flushReact()
    config <- Filter(function(sent) sent$type == "unsaved:config", log$messages)[[1]]$message
    session$setInputs(name = "Grace")
    session$flushReact()
    warning_text <- paste0(
      "on_save() returned an object of class promise. ",
      "on_save() must return TRUE after it has finished saving. ",
      "The changes are kept as unsaved."
    )
    expect_warning(
      session$setInputs(unsaved_save_requested = list(instance = config$instance, at = 1)),
      warning_text, fixed = TRUE
    )
    session$flushReact()
    expect_equal(tracker$baseline(), list(name = "Ada"))
    expect_equal(tracker$is_dirty(), TRUE)
    replies <- Filter(function(sent) sent$type == "unsaved:saved", log$messages)
    expect_equal(tail(replies, 1)[[1]]$message, list(instance = config$instance, ok = FALSE))
  })
})

test_that("ExtendedTask save results warn and keep changes unsaved", {
  skip_if_not_installed("shiny", "1.8.1")
  shiny::testServer(function(input, output, session) {
    log <- capture_messages(session)
    task <- shiny::ExtendedTask$new(function() TRUE)
    tracker <- unsaved_track("name", on_save = function() task)
  }, {
    session$setInputs(name = "Ada")
    session$flushReact()
    config <- Filter(function(sent) sent$type == "unsaved:config", log$messages)[[1]]$message
    session$setInputs(name = "Grace")
    session$flushReact()
    expect_warning(
      session$setInputs(unsaved_save_requested = list(instance = config$instance, at = 1)),
      "on_save() returned an object of class ExtendedTask", fixed = TRUE
    )
    session$flushReact()
    expect_equal(tracker$baseline(), list(name = "Ada"))
    expect_equal(tracker$is_dirty(), TRUE)
    replies <- Filter(function(sent) sent$type == "unsaved:saved", log$messages)
    expect_equal(tail(replies, 1)[[1]]$message, list(instance = config$instance, ok = FALSE))
  })
})

test_that("baseline, save, pause, resume and independent trackers work", {
  shiny::testServer(function(input, output, session) {
    first <- unsaved_track("x")
    second <- unsaved_track("y")
  }, {
    session$setInputs(x = 1, y = "a", unsaved_password_ids = list(ids = character()))
    session$flushReact()
    expect_equal(first$baseline(), list(x = 1))
    session$setInputs(x = 2)
    expect_equal(first$changed(), "x")
    expect_equal(first$count(), 1L)
    expect_equal(first$is_dirty(), TRUE)
    expect_equal(second$is_dirty(), FALSE)
    first$pause()
    expect_equal(first$is_dirty(), TRUE)
    session$setInputs(x = 3)
    first$resume()
    expect_equal(first$is_dirty(), TRUE)
    first$mark_saved()
    expect_equal(first$baseline(), list(x = 3))
    expect_equal(first$is_dirty(), FALSE)
    session$setInputs(x = 4, new = 1)
    first$discard()
    expect_equal(first$is_dirty(), TRUE)
    session$setInputs(x = 3)
    expect_equal(first$is_dirty(), FALSE)
  })
})
test_that("missing values convert to JSON null without losing names", {
  converted <- na_to_null(list(x = NA_real_, date = as.Date("2026-01-01")))
  expect_equal(converted, list(x = NULL, date = "2026-01-01"))
  expect_equal(NULL %||% 1, 1)
  expect_equal(0 %||% 1, 0)
  time <- as.POSIXct("2026-01-02", tz = "UTC")
  expect_equal(na_to_null(time), as.numeric(time))
})

test_that("a tracker works in testServer() without a browser report", {
  # testServer() has no browser, so no password report ever arrives. The
  # tracker must still snapshot, or app authors cannot test their servers.
  shiny::testServer(function(input, output, session) {
    tracker <- unsaved_track("name")
  }, {
    session$setInputs(name = "Ada")
    expect_equal(tracker$baseline(), list(name = "Ada"))
    session$setInputs(name = "Grace")
    expect_equal(tracker$is_dirty(), TRUE)
    expect_equal(tracker$changed(), "name")
  })
})
test_that("paused queries stay truthful and reactive while guards are suppressed", {
  shiny::testServer(function(input, output, session) {
    log <- capture_messages(session)
    tracker <- unsaved_track("name")
    query <- shiny::reactive(list(
      tracker$is_dirty(), tracker$count(),
      tracker$changed(), tracker$diff(), tracker$is_paused()
    ))
  }, {
    session$setInputs(name = "Ada")
    expect_equal(query()[[5]], FALSE)
    session$setInputs(name = "Grace")
    tracker$pause()
    expect_equal(query()[c(1, 2, 3, 5)], list(TRUE, 1L, "name", TRUE))
    expect_equal(query()[[4]]$saved, list("Ada"))
    for (value in c("Next", "Ada", "Last")) {
      session$setInputs(name = value)
      expect_equal(query()[[1]], value != "Ada")
      expect_equal(query()[[2]], as.integer(value != "Ada"))
      if (value != "Ada") expect_equal(query()[[4]]$current, list(value))
      states <- Filter(function(x) x$type == "unsaved:state", log$messages)
      expect_equal(tail(states, 1)[[1]]$message$ids, list())
      expect_equal(tail(states, 1)[[1]]$message$count, 0L)
      expect_equal(tail(states, 1)[[1]]$message$dirty, FALSE)
    }
    configs <- Filter(function(x) x$type == "unsaved:config", log$messages)
    config <- tail(configs, 1)[[1]]$message
    expect_equal(config[c("guardNav", "guardClicks", "guardUnload")],
                 list(guardNav = FALSE, guardClicks = FALSE, guardUnload = FALSE))
    tracker$resume()
    expect_equal(query()[[5]], FALSE)
    expect_equal(query()[[1]], TRUE)
    tracker$pause()
    tracker$mark_saved()
    expect_equal(query()[[1]], FALSE)
    expect_equal(tracker$baseline(), list(name = "Last"))
    expect_equal(query()[[5]], TRUE)
  })
})

test_that("ambiguous save results fail once without changing the baseline", {
  shiny::testServer(function(input, output, session) {
    log <- capture_messages(session)
    state <- new.env()
    tracker <- unsaved_track("name", on_save = function() state$result)
  }, {
    session$setInputs(name = "Ada")
    config <- Filter(function(x) x$type == "unsaved:config", log$messages)[[1]]$message
    session$setInputs(name = "Grace")
    results <- list(NULL, NA, 1, "yes", logical(), c(TRUE, TRUE), list(ok = TRUE), function() TRUE)
    descriptions <- c("NULL", "NA", "1", '"yes"', "logical (length 0)",
                      "logical (length 2)", "list (length 1)", "closure (length 1)")
    for (i in seq_along(results)) {
      state$result <- results[[i]]
      warnings <- list()
      withCallingHandlers(
        session$setInputs(unsaved_save_requested = list(instance = config$instance, at = i)),
        warning = function(w) {
          warnings[[length(warnings) + 1L]] <<- w
          invokeRestart("muffleWarning")
        }
      )
      expect_length(warnings, 1L)
      expect_null(conditionCall(warnings[[1]]))
      expect_equal(conditionMessage(warnings[[1]]), paste0(
        "on_save() returned ", descriptions[i], ". ",
        "on_save() must return TRUE after it has finished saving. ",
        "The changes are kept as unsaved."
      ))
      expect_equal(tracker$baseline(), list(name = "Ada"))
      expect_equal(tracker$is_dirty(), TRUE)
      replies <- Filter(function(x) x$type == "unsaved:saved", log$messages)
      expect_equal(tail(replies, 1)[[1]]$message$ok, FALSE)
    }
  })
})

test_that("guard flags configure independent client policies", {
  shiny::testServer(function(input, output, session) {
    log <- capture_messages(session)
    tracker <- unsaved_track("name", guard_nav = FALSE, guard_unload = FALSE)
    second <- unsaved_track("other", guard_clicks = FALSE)
  }, {
    session$setInputs(name = "Ada", other = "first")
    configs <- Filter(function(x) x$type == "unsaved:config", log$messages)
    policies <- lapply(configs, function(x) x$message[c("guardNav", "guardUnload", "guardClicks")])
    nav_off <- list(guardNav = FALSE, guardUnload = FALSE, guardClicks = TRUE)
    expect_true(any(vapply(policies, identical, logical(1), nav_off)))
    clicks_off <- list(guardNav = TRUE, guardUnload = TRUE, guardClicks = FALSE)
    expect_true(any(vapply(policies, identical, logical(1), clicks_off)))
  })
})

test_that("flag and session errors identify the argument and bad value", {
  session <- shiny::MockShinySession$new()
  on.exit(session$close())
  for (name in c("guard_nav", "guard_unload", "guard_clicks")) {
    for (bad in list("tru", NULL, NA, 1, c(TRUE, FALSE))) {
      args <- c(list(inputs = "name", session = session), setNames(list(bad), name))
      expect_error(do.call(unsaved_track, args),
                   paste0("`", name, "` must be TRUE or FALSE; got ", describe_value(bad), "."),
                   fixed = TRUE)
    }
  }
  expect_error(unsaved_track("name", session = 1),
               "`session` must be a Shiny session; got a numeric value.", fixed = TRUE)
  expect_error(unsaved_track("name", session = list()), "`session` must be a Shiny session", fixed = TRUE)
  expect_error(unsaved_track("name", session = new.env()), "`session` must be a Shiny session", fixed = TRUE)
  expect_error(unsaved_track(character()),
               "`inputs` must contain at least one non-empty input id.", fixed = TRUE)
  expect_error(unsaved_track("name", session = session, compare = list(nmae = identical)),
               "`compare` has unknown input id `nmae`. Tracked ids: name.", fixed = TRUE)
})
