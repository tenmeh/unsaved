make_values_reason_app <- function(custom_text = FALSE) {
  skip_on_cran()
  path <- local_app_file(c(
    "library(shiny)",
    "library(unsaved)",
    "ui <- fluidPage(unsaved_badge(), textOutput('reason_received'),",
    "textOutput('own_received'), actionButton('own_save', 'Save'),",
    "tabsetPanel(id = 'tabs', tabPanel('Form', value = 'form',",
    "tableOutput('visits_table'), actionButton('edit', 'Edit table'),",
    "actionButton('refresh', 'Render again'), actionButton('destroy', 'Destroy tracker')),",
    "tabPanel('Other', value = 'other', 'Other panel')))",
    "server <- function(input, output, session) {",
    "visits <- reactiveVal(data.frame(visit = 1L))",
    "reason_received <- reactiveVal('none')",
    "own_received <- reactiveVal('none')",
    "tracker <- unsaved_track(values = list(Visits = visits),",
    "value_outputs = c(Visits = 'visits_table'), require_reason = TRUE,",
    if (custom_text) paste0(
      "text = unsaved_text(reason_cancel = 'Back', ",
      "reason_save = 'Record reason'),"
    ),
    "on_save = function(reason) { reason_received(reason); TRUE },",
    "on_discard = function() visits(tracker$baseline()$Visits))",
    "output$visits_table <- renderTable({ input$refresh; visits() })",
    "output$reason_received <- renderText(reason_received())",
    "output$own_received <- renderText(own_received())",
    "observeEvent(input$edit, visits(data.frame(visit = 1:2)))",
    "observeEvent(input$destroy, tracker$destroy())",
    "observeEvent(input$own_save, tracker$ask_reason(function(reason) {",
    "own_received(reason); tracker$mark_saved() }))",
    "}",
    "shinyApp(ui, server)"
  ), "unsaved-round4-", .local_envir = parent.frame())
  local_app_driver(path, .local_envir = parent.frame())
}

fill_reason <- function(app, value) {
  app$run_js(paste0(
    "var area = document.querySelector('.unsaved-dialog textarea'); area.value = ",
    jsonlite::toJSON(value, auto_unbox = TRUE),
    "; area.dispatchEvent(new Event('input', {bubbles: true}));"
  ))
}

test_that("reason-only dialog uses custom button labels", {
  app <- make_values_reason_app(custom_text = TRUE)
  app$click("own_save")
  app$wait_for_js("document.querySelector('.unsaved-dialog') !== null")
  expect_equal(app$get_js(
    "document.querySelector('.unsaved-dialog .unsaved-keep').textContent"
  ), "Back")
  expect_equal(app$get_js(
    "document.querySelector('.unsaved-dialog .btn-primary').textContent"
  ), "Record reason")
  expect_no_shiny_errors(app)
})

test_that("server table edits show a badge and mapped output marker", {
  app <- make_values_reason_app()
  expect_equal(badge_text(app), "")
  app$run_js(paste0(
    "var hint = document.createElement('span'); hint.id = 'existing-description';",
    "hint.textContent = 'Existing description'; document.body.appendChild(hint);",
    "document.getElementById('visits_table').setAttribute('aria-describedby', hint.id);"
  ))
  app$click("edit")
  app$wait_for_idle()
  app$wait_for_js("document.getElementById('visits_table').hasAttribute('data-unsaved')")
  expect_equal(badge_text(app), "1 unsaved change")
  expect_equal(app$get_js("getComputedStyle(document.getElementById('visits_table')).outlineStyle"), "dashed")
  app$run_js("document.getElementById('visits_table').style.setProperty('--unsaved-outline', '4px dashed red')")
  expect_equal(app$get_js("getComputedStyle(document.getElementById('visits_table')).outlineWidth"), "4px")
  sibling_marker <- paste0(
    "document.getElementById('visits_table').previousElementSibling",
    ".classList.contains('unsaved-output-marker')"
  )
  expect_true(app$get_js(sibling_marker))
  expect_false(app$get_js("document.getElementById('visits_table').classList.contains('unsaved-marker')"))
  expect_equal(app$get_js("document.querySelector('#visits_table .unsaved-sr')"), NULL)
  description <- app$get_js(paste0(
    "document.getElementById('visits_table').previousElementSibling.querySelector('.unsaved-sr').id"
  ))
  expect_equal(app$get_js(paste0("document.getElementById('", description, "').textContent")), "Unsaved change")
  expect_equal(app$get_js("document.getElementById('visits_table').getAttribute('aria-describedby')"),
               paste("existing-description", description))
  app$click("refresh")
  app$wait_for_idle()
  expect_true(app$get_js(sibling_marker))
  expect_equal(app$get_js(paste0(
    "document.getElementById('visits_table').previousElementSibling.querySelector('.unsaved-sr').id"
  )), description)
  app$run_js("document.querySelector('a[data-value=other]').click()")
  app$run_js("document.querySelector('.unsaved-dialog .btn-outline-danger').click()")
  app$wait_for_idle()
  expect_equal(badge_text(app), "")
  expect_equal(marker_count(app), 0)
  expect_equal(app$get_js(paste0("document.getElementById('", description, "')")), NULL)
  expect_equal(app$get_js("document.getElementById('visits_table').getAttribute('aria-describedby')"),
               "existing-description")
  expect_equal(app$get_js("document.querySelectorAll('#visits_table tbody tr').length"), 1)
  app$set_inputs(tabs = "form")
  app$click("edit")
  app$wait_for_idle()
  expect_true(app$get_js(sibling_marker))
  app$click("destroy")
  app$wait_for_idle()
  expect_equal(marker_count(app), 0)
  expect_equal(app$get_js("document.querySelectorAll('.unsaved-marker, .unsaved-sr').length"), 0)
  expect_equal(app$get_js("document.getElementById('visits_table').getAttribute('aria-describedby')"),
               "existing-description")
  expect_no_shiny_errors(app)
})

test_that("removing a mapped output removes its sibling marker", {
  app <- make_values_reason_app()
  app$click("edit")
  app$wait_for_idle()
  expect_true(app$get_js(paste0(
    "document.getElementById('visits_table').previousElementSibling.classList.contains('unsaved-output-marker')"
  )))
  # Direct DOM removal also needs cleanup, without another Shiny output event.
  app$run_js("document.getElementById('visits_table').remove()")
  app$wait_for_js("document.querySelectorAll('.unsaved-marker, .unsaved-sr').length === 0")
  expect_equal(marker_count(app), 0)
  expect_equal(badge_text(app), "1 unsaved change")
  expect_no_shiny_errors(app)
})

test_that("required reason shows an inline error and reaches on_save", {
  app <- make_values_reason_app()
  app$click("edit")
  app$run_js("document.querySelector('a[data-value=other]').click()")
  disabled <- "document.querySelector('.unsaved-dialog .btn-primary').disabled"
  expect_equal(app$get_js(disabled), FALSE)
  expect_equal(app$get_js("document.querySelector('.unsaved-dialog label').textContent"),
               "Reason for change (required)")
  fill_reason(app, " \n\t ")
  expect_equal(app$get_js(disabled), FALSE)
  app$run_js("document.querySelector('.unsaved-dialog .btn-primary').click()")
  expect_equal(app$get_js("document.querySelector('.unsaved-reason-error').textContent"),
               "Enter a reason to save.")
  expect_equal(app$get_js("document.querySelector('.unsaved-dialog textarea').getAttribute('aria-invalid')"), "true")
  expect_equal(app$get_js("document.activeElement.tagName"), "TEXTAREA")
  expect_equal(app$get_js(paste0(
    "document.querySelector('.unsaved-dialog textarea').getAttribute('aria-describedby').split(' ')",
    ".includes(document.querySelector('.unsaved-reason-error').id)"
  )), TRUE)
  fill_reason(app, "  corrected record  ")
  expect_equal(app$get_js("document.querySelector('.unsaved-reason-count').textContent"), "20 of 1000 characters")
  expect_null(app$get_js("document.querySelector('.unsaved-dialog textarea').getAttribute('aria-invalid')"))
  expect_equal(app$get_js(disabled), FALSE)
  app$run_js("document.querySelector('.unsaved-dialog .btn-primary').click()")
  app$wait_for_js("document.querySelector('.unsaved-dialog') === null")
  app$wait_for_idle()
  expect_equal(app$get_value(output = "reason_received"), "corrected record")
  expect_equal(app$get_value(input = "tabs"), "other")
  expect_equal(badge_text(app), "")
  expect_no_shiny_errors(app)
})

test_that("ask_reason browser Cancel does nothing and Save sends a bounded reason", {
  app <- make_values_reason_app()
  app$click("own_save")
  app$wait_for_js("document.querySelector('.unsaved-dialog') !== null")
  expect_equal(app$get_js("document.querySelector('.unsaved-dialog h2').textContent"),
               "Why are you making this change?")
  expect_equal(app$get_js(paste0(
    "Array.from(document.querySelectorAll('.unsaved-dialog button'))",
    ".map(x => x.textContent).join(', ')"
  )), "Keep editing, Save")
  fill_reason(app, "cancel this")
  app$run_js("document.querySelector('.unsaved-dialog .unsaved-keep').click()")
  app$wait_for_idle()
  expect_equal(app$get_value(output = "own_received"), "none")
  app$click("own_save")
  app$wait_for_js("document.querySelector('.unsaved-dialog') !== null")
  expect_equal(app$get_js("document.querySelector('.unsaved-dialog .btn-primary').disabled"), FALSE)
  app$run_js(paste0(
    "var area = document.querySelector('.unsaved-dialog textarea');",
    "area.value = 'x'.repeat(1005);",
    "area.dispatchEvent(new InputEvent('input', {bubbles: true, inputType: 'insertFromPaste'}));"
  ))
  expect_equal(app$get_js("document.querySelector('.unsaved-dialog textarea').value.length"), 1000)
  expect_equal(app$get_js("document.querySelector('.unsaved-dialog [role=alert]').textContent"),
               "The reason was shortened to 1000 characters.")
  expect_equal(app$get_js("document.querySelector('.unsaved-reason-count').textContent"), "1000 of 1000 characters")
  app$run_js("document.querySelector('.unsaved-dialog .btn-primary').click()")
  app$wait_for_idle()
  expect_equal(app$get_value(output = "own_received"), strrep("x", 1000))
  expect_no_shiny_errors(app)
})
