make_provisional_app <- function(guard_unload = TRUE, compare = "NULL") {
  skip_on_cran()
  path <- local_app_file(c(
    "library(shiny)",
    "library(unsaved)",
    "ui <- fluidPage(unsaved_badge(), textInput('name', 'Name', 'Ada'),",
    "selectInput('role', 'Role', c('Designer', 'Developer')),",
    "actionButton('load', 'Load'), actionButton('block', 'Block'),",
    "actionButton('pause', 'Pause'), textOutput('dirty'), textOutput('done'),",
    "unsaved_guard(actionButton('exit', 'Exit')))",
    "server <- function(input, output, session) {",
    paste0("tracker <- unsaved_track(c('name', 'role'), guard_unload = ",
           guard_unload, ", compare = ", compare, ")"),
    "done <- reactiveVal(0L)",
    "observeEvent(input$block, {",
    "Sys.sleep(5)",
    "done(done() + 1L)",
    "})",
    "observeEvent(input$pause, tracker$pause())",
    "observeEvent(input$load, {",
    "tracker$mark_saved(values = list(name = 'Sam', role = 'Developer'))",
    "updateTextInput(session, 'name', value = 'Sam')",
    "updateSelectInput(session, 'role', selected = 'Developer')",
    "})",
    "output$dirty <- renderText(tracker$is_dirty())",
    "output$done <- renderText(done())",
    "}",
    "shinyApp(ui, server)"
  ), "unsaved-provisional-", .local_envir = parent.frame())
  local_app_driver(path, .local_envir = parent.frame())
}

unload_warning <- function(app) {
  app$get_js(paste0(
    "(() => { const event = new Event('beforeunload', {cancelable: true});",
    "window.dispatchEvent(event); return event.defaultPrevented; })()"
  ))
}

# get_value() waits for the blocked server, so read the page instead.
done_text <- function(app) {
  app$get_js("document.getElementById('done').textContent")
}

wait_unblocked <- function(app) {
  app$wait_for_js("document.getElementById('done').textContent === '1'", timeout = 20000)
  app$wait_for_idle()
}

block_server <- function(app) {
  app$run_js("Shiny.setInputValue('block', 1, {priority: 'event'})")
  app$wait_for_js("document.documentElement.classList.contains('shiny-busy')")
}

test_that("explicit baseline record loading ends clean without markers", {
  app <- make_provisional_app()
  app$set_inputs(name = "Edited")
  app$wait_for_idle()
  expect_equal(marker_count(app), 1)
  app$click("load")
  app$wait_for_idle()
  expect_equal(app$get_value(input = "name"), "Sam")
  expect_equal(app$get_value(input = "role"), "Developer")
  expect_equal(app$get_value(output = "dirty"), "FALSE")
  expect_equal(marker_count(app), 0)
  expect_equal(badge_text(app), "")
  expect_equal(unload_warning(app), FALSE)
  expect_no_shiny_errors(app)
})

test_that("busy server edits provisionally arm only the unload warning", {
  app <- make_provisional_app(compare = "function(saved, current) TRUE")
  block_server(app)
  app$run_js("$('#name').val('Changed').trigger('change')")
  app$wait_for_js("Shiny.shinyapp.$inputValues.name === 'Changed'")
  expect_equal(done_text(app), "0")
  expect_equal(unload_warning(app), TRUE)
  expect_equal(marker_count(app), 0)
  expect_equal(badge_text(app), "")
  app$run_js("document.getElementById('exit').click()")
  expect_null(app$get_js("document.querySelector('.unsaved-dialog')"))
  wait_unblocked(app)
  expect_equal(app$get_value(output = "done"), "1")
  expect_equal(app$get_value(output = "dirty"), "FALSE")
  expect_equal(unload_warning(app), FALSE)
  expect_no_shiny_errors(app)
})

test_that("an edit back to the saved value does not arm provisional unload", {
  app <- make_provisional_app(compare = "function(saved, current) TRUE")
  app$set_inputs(name = "Changed")
  app$wait_for_idle()
  expect_equal(unload_warning(app), FALSE)
  block_server(app)
  app$run_js("$('#name').val('Ada').trigger('change')")
  app$wait_for_js("Shiny.shinyapp.$inputValues.name === 'Ada'")
  expect_equal(done_text(app), "0")
  expect_equal(unload_warning(app), FALSE)
  wait_unblocked(app)
  expect_no_shiny_errors(app)
})

test_that("paused and unload-disabled trackers ignore provisional edits", {
  for (paused in c(FALSE, TRUE)) {
    app <- make_provisional_app(guard_unload = paused)
    if (paused) app$click("pause")
    app$wait_for_idle()
    block_server(app)
    app$run_js("$('#name').val('Changed').trigger('change')")
    app$wait_for_js("Shiny.shinyapp.$inputValues.name === 'Changed'")
    expect_equal(done_text(app), "0")
    expect_equal(unload_warning(app), FALSE)
    wait_unblocked(app)
    expect_no_shiny_errors(app)
  }
})
