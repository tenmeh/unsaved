make_action_app <- function() {
  skip_on_cran()
  path <- local_app_file(c(
    "library(shiny)",
    "library(unsaved)",
    "capture <- tags$script(HTML(\"",
    "$(document).on('shiny:connected', function() {",
    "  window.unsavedPayloads = [];",
    "  var socket = Shiny.shinyapp.$socket;",
    "  var original = socket.onmessage;",
    "  socket.onmessage = function(event) {",
    "    var data = typeof event.data === 'string' ? JSON.parse(event.data) : {};",
    "    if (data.custom) Object.keys(data.custom).forEach(function(key) {",
    "      if (key.indexOf('unsaved:') === 0) window.unsavedPayloads.push(data.custom[key]);",
    "    });",
    "    original.call(socket, event);",
    "  };",
    "});\"))",
    "ui <- fluidPage(tags$head(capture), unsaved_badge(),",
    "textInput('name', 'Name', 'Ada'), passwordInput('secret', 'Password', 'private-first'),",
    "dateInput('date', 'Date', '2026-01-01'),",
    "dateRangeInput('range', 'Range', '2026-01-01', '2026-01-31'),",
    "checkboxInput('fail', 'Fail save', FALSE), actionButton('confirm', 'Load record'),",
    "unsaved_guard(actionButton('guarded', 'Delete draft')),",
    "actionButton('add_secret', 'Add password'), uiOutput('late'),",
    "textOutput('calls'), textOutput('value'), textOutput('discards'),",
    "textOutput('discard_value'), textOutput('saves'), textOutput('types'), tableOutput('diff'))",
    "server <- function(input, output, session) {",
    "calls <- reactiveVal(0L)",
    "value <- reactiveVal('none')",
    "discards <- reactiveVal(0L)",
    "discard_value <- reactiveVal('none')",
    "saves <- reactiveVal(0L)",
    "types <- reactiveVal('none')",
    "tracker <- unsaved_track(c('Full name' = 'name', Password = 'secret', Late = 'late_secret',",
    "Date = 'date', Range = 'range'),",
    "on_save = function() {",
    "saves(saves() + 1L)",
    "if (input$fail) stop('private save detail')",
    "TRUE",
    "}, on_discard = function() {",
    "discards(discards() + 1L)",
    "discard_value(input$name)",
    "})",
    "run_action <- function() {",
    "calls(calls() + 1L)",
    "value(input$name)",
    "types(paste(class(input$date), class(input$range), sep = '/'))",
    "}",
    "observeEvent(input$confirm, tracker$confirm(run_action))",
    "observeEvent(input$guarded, run_action())",
    "observeEvent(input$add_secret, {",
    "output$late <- renderUI(passwordInput('late_secret', 'Late password', 'private-late'))",
    "})",
    "output$calls <- renderText(calls())",
    "output$value <- renderText(value())",
    "output$discards <- renderText(discards())",
    "output$discard_value <- renderText(discard_value())",
    "output$saves <- renderText(saves())",
    "output$types <- renderText(types())",
    "output$diff <- renderTable(tracker$diff()[, c('label', 'change')])",
    "}",
    "shinyApp(ui, server)"
  ), "unsaved-actions-", .local_envir = parent.frame())
  local_app_driver(path, load_timeout = 30000, .local_envir = parent.frame())
}

action_dialog <- function(app, button = "confirm") {
  app$set_inputs(name = "Grace", wait_ = FALSE)
  app$wait_for_idle()
  app$run_js(paste0("document.getElementById('", button, "').click()"))
  app$wait_for_idle()
  app$wait_for_js("document.querySelector('.unsaved-dialog') !== null")
}

test_that("clean confirm runs immediately without a dialog", {
  app <- make_action_app()
  app$click("confirm")
  app$wait_for_idle()
  expect_equal(app$get_value(output = "calls"), "1")
  expect_equal(app$get_value(output = "value"), "Ada")
  expect_null(app$get_js("document.querySelector('.unsaved-dialog')"))
  expect_no_shiny_errors(app)
})

test_that("dirty confirm Keep editing cancels the server action", {
  app <- make_action_app()
  action_dialog(app)
  expect_equal(app$get_value(output = "calls"), "0")
  app$run_js("document.querySelector('.unsaved-dialog .btn-secondary').click()")
  app$wait_for_idle()
  expect_equal(app$get_value(output = "calls"), "0")
  expect_equal(app$get_value(input = "name"), "Grace")
  expect_equal(badge_text(app), "1 unsaved change")
  # A cancelled confirmation must not block the next request.
  app$click("confirm")
  app$wait_for_idle()
  expect_equal(app$get_js("document.querySelector('.unsaved-dialog') !== null"), TRUE)
  expect_no_shiny_errors(app)
})

test_that("dirty confirm Discard restores then runs the callback and action once", {
  app <- make_action_app()
  action_dialog(app)
  app$run_js("document.querySelector('.unsaved-dialog .btn-danger').click()")
  app$wait_for_idle()
  expect_equal(app$get_value(output = "calls"), "1")
  expect_equal(app$get_value(output = "value"), "Ada")
  expect_equal(app$get_value(output = "discards"), "1")
  expect_equal(app$get_value(output = "discard_value"), "Ada")
  expect_equal(app$get_value(output = "types"), "Date/Date")
  expect_equal(app$get_value(input = "name"), "Ada")
  expect_equal(badge_text(app), "")
  expect_null(app$get_js("document.querySelector('.unsaved-dialog')"))
  expect_no_shiny_errors(app)
})

test_that("dirty confirm Save runs the action once after successful saving", {
  app <- make_action_app()
  action_dialog(app)
  app$run_js("document.querySelector('.unsaved-dialog .btn-primary').click()")
  app$wait_for_idle()
  expect_equal(app$get_value(output = "calls"), "1")
  expect_equal(app$get_value(output = "saves"), "1")
  expect_equal(app$get_value(output = "value"), "Grace")
  expect_equal(badge_text(app), "")
  expect_null(app$get_js("document.querySelector('.unsaved-dialog')"))
  expect_no_shiny_errors(app)
})

test_that("dirty confirm failed saving leaves the action pending and permits retry", {
  app <- make_action_app()
  app$set_inputs(fail = TRUE)
  action_dialog(app)
  app$run_js("document.querySelector('.unsaved-dialog .btn-primary').click()")
  app$wait_for_idle()
  expect_equal(app$get_value(output = "calls"), "0")
  expect_equal(app$get_value(output = "saves"), "1")
  expect_equal(badge_text(app), "1 unsaved change")
  expect_equal(app$get_js("document.querySelector('.unsaved-dialog [role=alert]').textContent"),
               "Could not save. Your changes are still here.")
  app$set_inputs(fail = FALSE)
  app$run_js("document.querySelector('.unsaved-dialog .btn-primary').click()")
  app$wait_for_idle()
  expect_equal(app$get_value(output = "calls"), "1")
  expect_equal(badge_text(app), "")
  expect_no_shiny_errors(app)
})

test_that("guard attribute blocks a button and replays its click once after Discard", {
  app <- make_action_app()
  app$run_js("document.getElementById('guarded').classList.add('active')")
  action_dialog(app, "guarded")
  expect_equal(app$get_value(output = "calls"), "0")
  app$run_js("document.querySelector('.unsaved-dialog .btn-danger').click()")
  app$wait_for_idle()
  expect_equal(app$get_value(output = "calls"), "1")
  expect_equal(app$get_value(output = "value"), "Ada")
  expect_equal(app$get_value(output = "discards"), "1")
  expect_equal(app$get_value(output = "types"), "Date/Date")
  expect_equal(badge_text(app), "")
  expect_no_shiny_errors(app)
})

test_that("field labels and diff appear in the browser change summary", {
  app <- make_action_app()
  app$set_inputs(name = "Grace")
  app$wait_for_idle()
  expect_match(app$get_html("#diff"), "Full name")
  expect_match(app$get_html("#diff"), "Ada -&gt; Grace|Ada -> Grace")
  expect_no_shiny_errors(app)
})

test_that("password edits stay clean and never reach any unsaved message", {
  app <- make_action_app()
  app$set_inputs(secret = "private-edited")
  app$wait_for_idle()
  expect_equal(badge_text(app), "")
  expect_equal(marker_count(app), 0)
  app$run_js("document.getElementById('secret').closest('.shiny-input-container').remove()")
  app$click("add_secret")
  app$wait_for_idle()
  app$set_inputs(late_secret = "private-late-edited")
  app$wait_for_idle()
  expect_equal(badge_text(app), "")
  app$set_inputs(name = "Grace")
  action_dialog(app)
  app$run_js("document.querySelector('.unsaved-dialog .btn-danger').click()")
  app$wait_for_idle()
  expect_equal(app$get_value(input = "secret"), "private-edited")
  expect_equal(app$get_value(input = "late_secret"), "private-late-edited")
  expect_equal(badge_text(app), "")
  expect_equal(app$get_js("JSON.stringify(window.unsavedPayloads).includes('private-')"), FALSE)
  expect_equal(app$get_js("window.unsavedPayloads.length > 0"), TRUE)
  expect_no_shiny_errors(app)
})
