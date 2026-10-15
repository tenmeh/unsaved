make_visits <- function(n = 2L) data.frame(visit = seq_len(n), score = rep(1, n))

test_that("server tables track dirty clean diff saved snapshots and discard", {
  shiny::testServer(function(input, output, session) {
    log <- capture_messages(session)
    visits <- shiny::reactiveVal(make_visits())
    tracker <- unsaved_track(
      values = list(Visits = visits),
      value_outputs = c(Visits = "visits_table"),
      on_discard = function() visits(tracker$baseline()$Visits)
    )
  }, {
    session$flushReact()
    expect_equal(tracker$is_dirty(), FALSE)
    expect_equal(tracker$baseline(), list(Visits = make_visits()))
    visits(make_visits(3L))
    session$flushReact()
    expect_equal(tracker$is_dirty(), TRUE)
    expect_equal(tracker$count(), 1L)
    expect_equal(tracker$changed(), "Visits")
    delta <- tracker$diff()
    expect_equal(delta$label, "Visits")
    expect_equal(delta$change, "a table of 2 rows -> a table of 3 rows")
    expect_equal(delta$saved[[1]], make_visits())
    expect_equal(delta$current[[1]], make_visits(3L))
    visits(make_visits())
    session$flushReact()
    expect_equal(tracker$is_dirty(), FALSE)
    visits(make_visits(3L))
    session$flushReact()
    tracker$mark_saved()
    expect_equal(tracker$baseline()$Visits, make_visits(3L))
    expect_equal(tracker$count(), 0L)
    tracker$mark_saved(values = list(Visits = make_visits(4L)))
    tracker$discard()
    session$flushReact()
    expect_equal(visits(), make_visits(4L))
    expect_equal(tracker$is_dirty(), FALSE)
    expect_equal(nrow(tracker$diff()), 0L)
    configs <- Filter(function(x) x$type == "unsaved:config", log$messages)
    config <- tail(configs, 1)[[1]]$message
    expect_equal(config$valueOutputs[[session$ns("Visits")]], session$ns("visits_table"))
    expect_equal(config$valueIds, as.list(session$ns("Visits")))
    for (sent in log$messages) {
      if (sent$type == "unsaved:config") expect_length(sent$message$baseline, 0L)
      if (sent$type == "unsaved:restore") expect_length(sent$message$inputs, 0L)
    }
  })
})

test_that("late server values join independently and compare uses value ids", {
  shiny::testServer(function(input, output, session) {
    ready <- shiny::reactiveVal(FALSE)
    visits <- shiny::reactiveVal(make_visits())
    late <- shiny::reactive({
      shiny::req(ready())
      visits()
    })
    tracker <- unsaved_track(
      "name", values = list(Visits = visits, Late = late),
      compare = list(Visits = function(a, b) identical(nrow(a), nrow(b)))
    )
  }, {
    session$setInputs(name = "Ada")
    expect_named(tracker$baseline(), c("name", "Visits"))
    visits(data.frame(visit = 1:2, score = c(NA_real_, 2)))
    session$flushReact()
    expect_equal(tracker$count(), 0L)
    ready(TRUE)
    session$flushReact()
    expect_equal(tracker$baseline()$Late, visits())
    visits(make_visits())
    session$setInputs(name = "Grace")
    expect_equal(tracker$changed(), c("name", "Late"))
    tracker$mark_saved()
    visits(NULL)
    session$flushReact()
    expect_null(tracker$diff()$current[[1]])
  })
})

test_that("server values validate ids reactives and output mappings", {
  session <- shiny::MockShinySession$new()
  on.exit(session$close())
  rv <- shiny::reactiveVal(NULL)
  for (bad in list(1, list(rv), list(A = rv, A = rv), list(A = function() 1),
                   setNames(list(rv), NA_character_), setNames(list(rv), ""))) {
    expect_error(unsaved_track(values = bad, session = session), "uniquely named list")
  }
  expect_error(unsaved_track("A", values = list(A = rv), session = session), "clash")
  for (bad in list("table", c(B = "table"), c(A = NA_character_), c(A = ""),
                   list(A = "table"), c(A = "one", A = "two"))) {
    expect_error(unsaved_track(values = list(A = rv), value_outputs = bad,
                               session = session), "named character vector")
  }
})

test_that("server values capture NULL and remain dirty without app restoration", {
  shiny::testServer(function(input, output, session) {
    value <- shiny::reactiveVal(NULL)
    tracker <- unsaved_track(values = list(Value = value))
  }, {
    session$flushReact()
    expect_equal(tracker$baseline(), list(Value = NULL))
    value(make_visits(0L))
    session$flushReact()
    expect_equal(tracker$count(), 1L)
    tracker$discard()
    session$flushReact()
    expect_equal(tracker$is_dirty(), TRUE)
    expect_equal(value(), make_visits(0L))
  })
})
