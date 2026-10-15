test_that("dynamic module destruction removes markers badge and guards", {
  skip_on_cran()
  skip_if_not_installed("shiny", "1.14.0")
  path <- local_app_file(c(
    "library(shiny)",
    "library(unsaved)",
    "ui <- fluidPage(unsaved_badge(), actionButton('add', 'Add'),",
    "actionButton('remove', 'Remove'), textOutput('calls'),",
    "unsaved_guard(actionButton('exit', 'Exit')),",
    "tabsetPanel(id = 'tabs', tabPanel('Form', value = 'form',",
    "tags$div(id = 'host')), tabPanel('Other', value = 'other', 'Other')))",
    "server <- function(input, output, session) {",
    "module_session <- NULL",
    "calls <- reactiveVal(0L)",
    "output$calls <- renderText(calls())",
    "observeEvent(input$exit, calls(calls() + 1L))",
    "observeEvent(input$add, {",
    "insertUI('#host', ui = tags$div(id = 'editor',",
    "textInput(NS('editor', 'name'), 'Name', 'Ada'),",
    "actionButton(NS('editor', 'confirm'), 'Confirm')))",
    "module_session <<- moduleServer('editor', function(input, output, session) {",
    "tracker <- unsaved_track('name')",
    "observeEvent(input$confirm, tracker$confirm(function() calls(calls() + 1L)))",
    "session",
    "})",
    "})",
    "observeEvent(input$remove, {",
    "removeUI('#editor')",
    "module_session$destroy()",
    "})",
    "}",
    "shinyApp(ui, server)"
  ), "unsaved-destroy-")
  app <- local_app_driver(path, load_timeout = 30000)
  app$click("add")
  app$wait_for_js("document.getElementById('editor-name') !== null")
  app$wait_for_idle()
  app$set_inputs(`editor-name` = "Grace")
  app$wait_for_idle()
  expect_equal(marker_count(app), 1)
  expect_equal(badge_text(app), "1 unsaved change")
  unload_blocked <- paste0(
    "(() => { const event = new Event('beforeunload', {cancelable: true});",
    "window.dispatchEvent(event); return event.defaultPrevented; })()"
  )
  expect_equal(app$get_js(unload_blocked), TRUE)
  app$run_js("document.querySelector('a[data-value=other]').click()")
  app$wait_for_js("document.querySelector('.unsaved-dialog') !== null")
  expect_equal(app$get_value(input = "tabs"), "form")
  app$run_js("document.querySelector('.unsaved-dialog .btn-secondary').click()")
  app$click("editor-confirm")
  app$wait_for_js("document.querySelector('.unsaved-dialog') !== null")
  app$run_js("
    window.removalReplies = 0;
    var originalInput = Shiny.setInputValue;
    Shiny.setInputValue = function(id) {
      if (id.indexOf('unsaved_confirm_requested') !== -1) window.removalReplies++;
      return originalInput.apply(this, arguments);
    };
  ")
  # Remove through the server while the dialog covers the button.
  # set_inputs() refuses action buttons, so send the event from the page.
  app$run_js("Shiny.setInputValue('remove', 1, {priority: 'event'})")
  app$wait_for_idle()
  expect_null(app$get_js("document.getElementById('editor-name')"))
  expect_null(app$get_js("document.querySelector('.unsaved-dialog')"))
  expect_equal(app$get_js("window.removalReplies"), 0)
  expect_equal(app$get_value(output = "calls"), "0")
  expect_equal(marker_count(app), 0)
  expect_equal(badge_text(app), "")
  expect_equal(app$get_js(unload_blocked), FALSE)
  app$run_js("document.getElementById('exit').click()")
  app$wait_for_idle()
  expect_equal(app$get_value(output = "calls"), "1")
  app$run_js("document.querySelector('a[data-value=other]').click()")
  app$wait_for_idle()
  expect_equal(app$get_value(input = "tabs"), "other")
  expect_null(app$get_js("document.querySelector('.unsaved-dialog')"))
  expect_no_shiny_errors(app)
})
