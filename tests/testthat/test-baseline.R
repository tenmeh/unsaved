test_that("explicit saved values publish clean then compare browser echoes", {
  shiny::testServer(function(input, output, session) {
    log <- capture_messages(session)
    tracker <- unsaved_track(c("name", "role"))
  }, {
    session$setInputs(name = "Ada", role = "Designer")
    session$setInputs(name = "Edited")
    record <- list(name = "Sam", role = "Developer")
    expect_identical(tracker$mark_saved(values = record), tracker)
    expect_equal(tracker$baseline(), record)
    expect_equal(tail(log$messages, 1)[[1]]$message$dirty, FALSE)
    expect_equal(tail(log$messages, 1)[[1]]$message$ids, list())
    session$setInputs(name = "Still old")
    expect_equal(tracker$count(), 2L)
    session$setInputs(name = "Sam", role = "Developer")
    expect_equal(tracker$is_dirty(), FALSE)
  })
})

test_that("partial saved values use current inputs and preserve NULL entries", {
  shiny::testServer(function(input, output, session) {
    tracker <- unsaved_track(c("name", "role", "late"))
  }, {
    session$setInputs(name = "Ada", role = "Designer")
    session$setInputs(role = "Developer")
    tracker$mark_saved(list(name = "Sam", late = NULL))
    expect_equal(tracker$baseline(), list(name = "Sam", role = "Developer", late = NULL))
    tracker$mark_saved(list())
    expect_equal(tracker$baseline(), list(name = "Ada", role = "Developer"))
    tracker$mark_saved(NULL)
    expect_equal(tracker$is_dirty(), FALSE)
  })
})

test_that("saved values reject unknown ids and malformed lists without changes", {
  shiny::testServer(function(input, output, session) {
    tracker <- unsaved_track(c("name", "role"))
  }, {
    session$setInputs(name = "Ada", role = "Designer")
    before <- tracker$baseline()
    expect_error(tracker$mark_saved(list(other = "Sam")),
                 "Unknown input id in `values`: other. Tracked ids: name, role.", fixed = TRUE)
    for (values in list("Sam", list("Sam"), list(name = 1, name = 2),
                        setNames(list(1), NA_character_), setNames(list(1), ""),
                        data.frame(name = "Sam"))) {
      expect_error(tracker$mark_saved(values), "uniquely named list", fixed = TRUE)
    }
    expect_equal(tracker$baseline(), before)
  })
})

test_that("explicit saved values ignore passwords and keep files on the server", {
  shiny::testServer(function(input, output, session) {
    log <- capture_messages(session)
    tracker <- unsaved_track(c("name", "password", "file"))
  }, {
    session$setInputs(name = "Ada", password = "secret",
                      unsaved_password_ids = list(ids = "password"))
    upload <- data.frame(name = "record.csv", datapath = "/private/record.csv")
    tracker$mark_saved(list(name = "Sam", password = "new secret", file = upload))
    expect_equal(tracker$baseline(), list(name = "Sam", file = upload))
    tracker$discard()
    for (sent in log$messages) {
      if (sent$type == "unsaved:config") {
        expect_null(sent$message$baseline$password)
        expect_null(sent$message$baseline$file)
      }
      if (sent$type == "unsaved:restore") {
        expect_null(sent$message$inputs$password)
        expect_null(sent$message$inputs$file)
      }
    }
  })
})
