test_that("late password reports scrub baselines, diff and every client payload", {
  shiny::testServer(function(input, output, session) {
    log <- capture_messages(session)
    # Simulate an app whose first values precede the client metadata.
    session$setInputs(unsaved_password_ids = NULL)
    tracker <- unsaved_track(c(Name = "name", Password = "secret"))
  }, {
    session$setInputs(name = "Ada", secret = "private-first")
    expect_length(tracker$baseline(), 0L)
    configs <- Filter(function(sent) sent$type == "unsaved:config", log$messages)
    expect_length(configs[[1]]$message$baseline, 0L)
    # Use rootScope(), not MockShinySession's artificial namespace prefix.
    expect_identical(session$rootScope(), session)
    session$setInputs(unsaved_password_ids = "secret")
    expect_equal(tracker$baseline(), list(name = "Ada"))
    session$setInputs(secret = "private-edited")
    expect_equal(tracker$is_dirty(), FALSE)
    expect_equal(nrow(tracker$diff()), 0L)
    session$setInputs(unsaved_password_ids = list(ids = character()))
    expect_equal(tracker$baseline(), list(name = "Ada"))
    session$setInputs(secret = "private-after-unbind")
    expect_equal(tracker$is_dirty(), FALSE)
    tracker$mark_saved()
    tracker$discard()
    payloads <- paste(vapply(log$messages, function(sent) {
      paste(capture.output(str(sent$message)), collapse = " ")
    }, character(1)), collapse = " ")
    expect_equal(grepl("private-", payloads), FALSE)
    expect_equal(tracker$baseline(), list(name = "Ada"))
  })
})

test_that("password reports match module-local inputs and keep other modules independent", {
  module <- function(id) {
    shiny::moduleServer(id, function(input, output, session) {
      log <- capture_messages(session)
      tracker <- unsaved_track(c("name", "secret"))
    })
  }
  shiny::testServer(module, args = list(id = "editor"), {
    session$setInputs(name = "Ada", secret = "private",
                      unsaved_password_ids = c("editor-secret", "other-name"))
    expect_named(tracker$baseline(), "name")
    session$setInputs(secret = "edited")
    expect_equal(tracker$changed(), character())
    tracker$discard()
    restore <- tail(log$messages, 1)[[1]]$message$inputs
    expect_equal(restore, list("editor-name" = "Ada"))
    config <- Filter(function(sent) sent$type == "unsaved:config", log$messages)[[1]]$message
    expect_equal(config$passwordInput, "editor-unsaved_password_ids")
  })
})
