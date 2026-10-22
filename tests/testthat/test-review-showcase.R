test_that("the review showcase saves audit rows and loads a batch baseline", {
  skip_on_cran()
  for (package in c("DT", "bslib", "promises", "later")) skip_if_not_installed(package)
  withr::local_envvar(R_USER_CACHE_DIR = tempdir())
  env <- new.env(parent = globalenv())
  path <- system.file("examples/review", package = "unsaved")
  suppressWarnings(sys.source(file.path(path, "global.R"), envir = env))
  sys.source(file.path(path, "ui.R"), envir = env)
  sys.source(file.path(path, "server.R"), envir = env)
  expect_s3_class(env$ui, "shiny.tag.list")
  shiny::testServer(env$server, {
    log <- capture_messages(session)
    session$setInputs(status = "Not started", note = "", batch = "B1")
    session$flushReact()
    expect_match(output$changes$html, "No unsaved changes.", fixed = TRUE)
    session$setInputs(results_table_cell_edit = data.frame(row = 1L, col = 2L, value = "19"))
    session$setInputs(results_table_cell_edit = data.frame(row = 1L, col = 4L, value = "Checked"))
    session$setInputs(status = "In review", note = "Checked fictional source")
    expect_equal(results_rv()$value[1], 19)
    expect_setequal(tracker$changed(), c("Results", "status", "note"))
    config <- tail(Filter(function(x) x$type == "unsaved:config", log$messages), 1)[[1]]$message
    expect_equal(config$valueOutputs, setNames(list(session$ns("results_table")), session$ns("Results")))
    changes <- tracker$diff()
    expect_equal(changes$change[changes$name == "Results"],
                 'row 1, value: 12 -> 19; row 1, flag: "" -> Checked')
    expect_match(output$change_table, "row 1, value: 12", fixed = TRUE)
    session$setInputs(save = 1)
    request <- tail(Filter(function(x) x$type == "unsaved:confirm", log$messages), 1)[[1]]$message
    expect_true(request$reasonOnly)
    expect_true(request$saveMode)
    session$setInputs(unsaved_save_requested = c(
      request, list(choice = "save", reason = "  Corrected transcription  ")
    ))
    expect_true(saving())
    expect_equal(nrow(audit()), 0L)
    # Pump the later loop, including the chained promise callbacks.
    deadline <- Sys.time() + 5
    while ((saving() || tracker$is_dirty()) && Sys.time() < deadline) {
      later::run_now(0.1)
      session$flushReact()
    }
    session$flushReact()
    expect_equal(batches()$B1$Results$value[1], 19)
    expect_equal(batches()$B1$status, "In review")
    expect_equal(batches()$B1$note, "Checked fictional source")
    expect_equal(nrow(audit()), 4L)
    expect_equal(audit()$field, c("Review status", "Review note", "Results", "Results"))
    expect_equal(audit()$change[1:2], changes$change[changes$name != "Results"])
    cells <- audit()[audit()$field == "Results", ]
    expect_equal(cells$sample_id, rep("B1-001", 2))
    expect_equal(cells$column, c("value", "flag"))
    expect_equal(cells$old_value, c("12", '""'))
    expect_equal(cells$new_value, c("19", "Checked"))
    expect_equal(cells$change, c("12 -> 19", '"" -> Checked'))
    expect_equal(audit()$reason, rep("Corrected transcription", 4))
    expect_equal(audit()$batch, rep("B1", 4))
    expect_equal(audit()$user, rep("demo reviewer", 4))
    expect_false(anyNA(audit()$timestamp))
    expect_false(tracker$is_dirty())
    session$setInputs(unsaved_confirm_requested = c(request, list(choice = "save")))
    expect_match(output$changes$html, "No unsaved changes.", fixed = TRUE)
    session$setInputs(batch = "B2", load = 1)
    expect_equal(active_batch(), "B2")
    expect_equal(tracker$baseline()[names(batches()$B2)], batches()$B2)
    session$setInputs(status = "Not started", note = "")
    expect_false(tracker$is_dirty())
    expect_equal(results_rv(), batches()$B2$Results)
    session$setInputs(results_table_cell_edit = data.frame(row = 2L, col = 2L, value = "99"))
    session$setInputs(discard = 1)
    expect_equal(results_rv(), batches()$B2$Results)
    expect_false(tracker$is_dirty())

    # Navigation saves must also persist the starting values, not later edits.
    session$setInputs(note = "First edit")
    session$setInputs(unsaved_save_requested = list(instance = config$instance, reason = "Source check"))
    session$setInputs(note = "Later edit")
    deadline <- Sys.time() + 5
    while ((saving() || identical(tracker$baseline()$note, "")) && Sys.time() < deadline) {
      later::run_now(0.1)
      session$flushReact()
    }
    expect_equal(batches()$B2$note, "First edit")
    expect_equal(tracker$baseline()$note, "First edit")
    expect_true(tracker$is_dirty())
    expect_equal(tail(audit()$reason, 1), "Source check")
  })
})

test_that("the review showcase tabs edits reasons and markers work", {
  skip_on_cran()
  for (package in c("DT", "bslib", "promises", "later")) skip_if_not_installed(package)
  app <- local_app_driver(system.file("examples/review", package = "unsaved"))
  expect_true(app$get_js("document.querySelector('.navbar .unsaved-badge') !== null"))
  for (tab in c("changes", "audit", "review")) {
    app$set_inputs(tabs = tab)
    app$wait_for_idle()
    expect_equal(app$get_value(input = "tabs"), tab)
    if (tab == "changes") expect_match(app$get_html("#changes"), "No unsaved changes.", fixed = TRUE)
  }
  app$run_js(paste0(
    "Shiny.setInputValue('results_table_cell_edit:DT.cellInfo', ",
    "[{row: 1, col: 2, value: '19'}, {row: 1, col: 4, value: 'Checked'}], {priority: 'event'});"
  ))
  app$wait_for_idle()
  expect_equal(badge_text(app), "1 unsaved change")
  expect_equal(app$get_js(
    "document.getElementById('results_table').getAttribute('data-unsaved')"
  ), "true")
  expect_true(app$get_js(paste0(
    "document.getElementById('results_table').previousElementSibling.classList.contains('unsaved-output-marker')"
  )))
  app$click("save")
  app$wait_for_js("document.querySelector('.unsaved-dialog textarea') !== null")
  app$run_js(paste0(
    "var reason = document.querySelector('.unsaved-dialog textarea');",
    "reason.value = 'Checked demo source'; reason.dispatchEvent(new Event('input'));",
    "document.querySelector('.unsaved-dialog .btn-primary').click();"
  ))
  app$wait_for_js("document.querySelector('.unsaved-badge').textContent === ''")
  app$wait_for_idle()
  expect_equal(badge_text(app), "")
  app$set_inputs(tabs = "audit")
  app$wait_for_idle()
  expect_match(app$get_html("#audit_table"), "Checked demo source")
  expect_equal(app$get_js("document.querySelectorAll('#audit_table tbody tr').length"), 2)
  expect_match(app$get_html("#audit_table"), "B1-001")
  expect_match(app$get_js("document.getElementById('audit_table').textContent"), "12 -> 19", fixed = TRUE)
  expect_match(app$get_js("document.getElementById('audit_table').textContent"), '"" -> Checked', fixed = TRUE)
  app$set_inputs(tabs = "review", note = "Reviewed source")
  app$wait_for_idle()
  app$run_js("document.querySelector('[data-value=changes]').click()")
  app$wait_for_js("document.querySelector('.unsaved-dialog textarea') !== null")
  app$run_js(paste0(
    "var reason = document.querySelector('.unsaved-dialog textarea');",
    "reason.value = 'Review complete'; reason.dispatchEvent(new Event('input'));",
    "document.querySelector('.unsaved-dialog .btn-primary').click();"
  ))
  app$wait_for_js("document.querySelector('.unsaved-dialog .btn-primary').textContent === 'Saving...'")
  app$wait_for_js("document.querySelector('.unsaved-dialog') === null")
  app$wait_for_idle()
  expect_equal(app$get_value(input = "tabs"), "changes")
  expect_equal(badge_text(app), "")
  expect_no_shiny_errors(app)
})
