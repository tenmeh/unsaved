make_managed_save_app <- function(reason = FALSE) {
  skip_on_cran()
  path <- local_app_file(c(
    "library(shiny)",
    "library(unsaved)",
    "ui <- fluidPage(unsaved_badge(), textOutput('saving'),",
    "tabsetPanel(id = 'tabs', tabPanel('Form', value = 'form',",
    "textInput('name', 'Name', 'Ada'), actionButton('save', 'Save')),",
    "tabPanel('Other', value = 'other', 'Other')))",
    "server <- function(input, output, session) {",
    "resolve_save <- NULL",
    paste0("on_save <- function(", if (reason) "reason" else "", ") {"),
    "promises::promise(function(resolve, reject) resolve_save <<- resolve)",
    "}",
    paste0("tracker <- unsaved_track('name', on_save = on_save, require_reason = ", reason, ")"),
    "observeEvent(input$save, tracker$save())",
    "observeEvent(input$settle, resolve_save(TRUE))",
    "output$saving <- renderText(tracker$is_saving())",
    "}",
    "shinyApp(ui, server)"
  ), "unsaved-save-lifecycle-", .local_envir = parent.frame())
  local_app_driver(path, .local_envir = parent.frame())
}

test_that("save and continue stays when edits made during saving remain dirty", {
  app <- make_managed_save_app()
  app$set_inputs(name = "Saved snapshot")
  app$run_js("document.querySelector('a[data-value=other]').click()")
  app$wait_for_js("document.querySelector('.unsaved-dialog') !== null")
  app$run_js("document.querySelector('.unsaved-dialog .btn-primary').click()")
  app$wait_for_js("document.getElementById('saving').textContent === 'TRUE'")
  # A real change event: an event-priority setInputValue() is not an input edit.
  app$run_js("$('#name').val('Later edit').trigger('change');")
  app$wait_for_js("Shiny.shinyapp.$inputValues.name === 'Later edit'")
  app$wait_for_idle()
  app$run_js("Shiny.setInputValue('settle', 1, {priority: 'event'});")
  app$wait_for_js("document.getElementById('saving').textContent === 'FALSE'")
  app$wait_for_js(paste0(
    "document.querySelector('.unsaved-dialog [role=alert]') !== null && ",
    "document.querySelector('.unsaved-dialog [role=alert]').textContent === ",
    "'Saved. Some changes were made while saving and are not saved yet.'"
  ))
  expect_equal(app$get_value(input = "tabs"), "form")
  expect_equal(badge_text(app), "1 unsaved change")
  expect_equal(app$get_js("document.querySelector('.unsaved-dialog p').textContent"),
               paste("You have 1 unsaved change.",
                     "They will be lost if you continue without saving."))
  expect_equal(app$get_js("document.querySelector('.unsaved-dialog .unsaved-keep').disabled"), FALSE)
  expect_no_shiny_errors(app)
})

test_that("managed reason save waits through Escape then closes on success", {
  app <- make_managed_save_app(reason = TRUE)
  app$set_inputs(name = "Grace")
  app$click("save")
  app$wait_for_js("document.querySelector('.unsaved-dialog textarea') !== null")
  app$run_js(paste0(
    "var reason = document.querySelector('.unsaved-dialog textarea');",
    "reason.value = 'Correction'; reason.dispatchEvent(new Event('input'));",
    "document.querySelector('.unsaved-dialog .btn-primary').click();"
  ))
  app$wait_for_js("document.getElementById('saving').textContent === 'TRUE'")
  expect_equal(app$get_js("document.querySelector('.unsaved-dialog .btn-primary').textContent"), "Saving...")
  browser_key(app, "Escape", 27L)
  expect_equal(app$get_js("document.querySelector('.unsaved-dialog') !== null"), TRUE)
  expect_equal(app$get_js("document.querySelector('.unsaved-dialog .unsaved-keep').disabled"), TRUE)
  app$run_js("Shiny.setInputValue('settle', 1, {priority: 'event'});")
  app$wait_for_js("document.querySelector('.unsaved-dialog') === null")
  app$wait_for_idle()
  expect_equal(badge_text(app), "")
  expect_equal(app$get_value(input = "tabs"), "form")
  expect_no_shiny_errors(app)
})
