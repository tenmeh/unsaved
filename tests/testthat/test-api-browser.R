make_api_app <- function(guard_nav = TRUE, guard_clicks = TRUE) {
  skip_on_cran()
  path <- local_app_file(c(
    "library(shiny)",
    "library(unsaved)",
    "ui <- fluidPage(unsaved_badge(), textOutput('dirty'), textOutput('paused'),",
    "textOutput('calls'), actionButton('pause', 'Pause'), actionButton('resume', 'Resume'),",
    "unsaved_guard(actionButton('exit', 'Exit')),",
    "tabsetPanel(id = 'tabs', tabPanel('Form', value = 'form',",
    "textInput('name', 'Name', 'Ada')), tabPanel('Other', value = 'other', 'Other')))",
    "server <- function(input, output, session) {",
    paste0("tracker <- unsaved_track('name', guard_nav = ", guard_nav,
           ", guard_clicks = ", guard_clicks, ")"),
    "calls <- reactiveVal(0L)",
    "observeEvent(input$exit, calls(calls() + 1L))",
    "observeEvent(input$pause, tracker$pause())",
    "observeEvent(input$resume, tracker$resume())",
    "output$dirty <- renderText(tracker$is_dirty())",
    "output$paused <- renderText(tracker$is_paused())",
    "output$calls <- renderText(calls())",
    "}",
    "shinyApp(ui, server)"
  ), "unsaved-api-", .local_envir = parent.frame())
  local_app_driver(path, load_timeout = 30000, .local_envir = parent.frame())
}

test_that("paused markers and badge hide while the dirty query stays TRUE", {
  app <- make_api_app()
  app$set_inputs(name = "Grace")
  app$wait_for_idle()
  expect_equal(marker_count(app), 1)
  expect_equal(badge_text(app), "1 unsaved change")
  app$click("pause")
  app$wait_for_idle()
  expect_equal(app$get_value(output = "paused"), "TRUE")
  expect_equal(app$get_value(output = "dirty"), "TRUE")
  expect_equal(marker_count(app), 0)
  expect_equal(badge_text(app), "")
  app$set_inputs(name = "Next")
  app$wait_for_idle()
  expect_equal(app$get_value(output = "dirty"), "TRUE")
  expect_equal(marker_count(app), 0)
  expect_equal(badge_text(app), "")
  app$run_js("document.getElementById('exit').click()")
  app$wait_for_idle()
  expect_equal(app$get_value(output = "calls"), "1")
  expect_null(app$get_js("document.querySelector('.unsaved-dialog')"))
  app$run_js("document.querySelector('a[data-value=other]').click()")
  app$wait_for_idle()
  expect_equal(app$get_value(input = "tabs"), "other")
  app$click("resume")
  app$wait_for_idle()
  expect_equal(app$get_value(output = "paused"), "FALSE")
  expect_equal(marker_count(app), 1)
  expect_equal(badge_text(app), "1 unsaved change")
  expect_no_shiny_errors(app)
})

test_that("guarded buttons ask with tab guards disabled", {
  app <- make_api_app(guard_nav = FALSE)
  app$set_inputs(name = "Grace")
  app$wait_for_idle()
  app$run_js("document.getElementById('exit').click()")
  app$wait_for_js("document.querySelector('.unsaved-dialog') !== null")
  expect_equal(app$get_value(output = "calls"), "0")
  app$run_js("document.querySelector('.unsaved-dialog .btn-danger').click()")
  app$wait_for_idle()
  expect_equal(app$get_value(output = "calls"), "1")
  expect_equal(app$get_value(input = "name"), "Ada")
  expect_no_shiny_errors(app)
})

test_that("guarded buttons do not ask with click guards disabled", {
  app <- make_api_app(guard_clicks = FALSE)
  app$set_inputs(name = "Grace")
  app$wait_for_idle()
  app$run_js("document.getElementById('exit').click()")
  app$wait_for_idle()
  expect_null(app$get_js("document.querySelector('.unsaved-dialog')"))
  expect_equal(app$get_value(output = "calls"), "1")
  expect_equal(app$get_value(output = "dirty"), "TRUE")
  app$run_js("document.querySelector('a[data-value=other]').click()")
  app$wait_for_js("document.querySelector('.unsaved-dialog') !== null")
  expect_equal(app$get_value(input = "tabs"), "form")
  expect_no_shiny_errors(app)
})

test_that("tab changes are free with tab guards disabled even on tagged tabs", {
  app <- make_api_app(guard_nav = FALSE)
  app$set_inputs(name = "Grace")
  app$wait_for_idle()
  app$run_js("document.querySelector('a[data-value=other]').click()")
  app$wait_for_idle()
  expect_equal(app$get_value(input = "tabs"), "other")
  expect_null(app$get_js("document.querySelector('.unsaved-dialog')"))
  app$run_js("
    var tab = document.querySelector('a[data-value=form]');
    tab.setAttribute('data-unsaved-guard', '');
    tab.click();
  ")
  app$wait_for_idle()
  expect_equal(app$get_value(input = "tabs"), "form")
  expect_null(app$get_js("document.querySelector('.unsaved-dialog')"))
  expect_equal(app$get_value(output = "dirty"), "TRUE")
  expect_no_shiny_errors(app)
})
