make_feature_app <- function() {
  skip_on_cran()
  path <- local_app_file(c(
    "library(shiny)",
    "library(unsaved)",
    "module_ui <- function(id) {",
    "ns <- NS(id)",
    "tagList(textInput(ns('name'), 'Name', 'Ada'), textInput(ns('raw'), 'Raw', 'Ada'),",
    "textOutput(ns('blocked')), textOutput(ns('saved')), textOutput(ns('discarded')))",
    "}",
    "module_server <- function(id) moduleServer(id, function(input, output, session) {",
    "saved <- reactiveVal(0L)",
    "discarded <- reactiveVal(0L)",
    "blocked <- reactiveVal(0L)",
    "tracker <- unsaved_track(c('name', 'raw'), compare = list(name = unsaved_compare_text()),",
    "text = unsaved_text(title = paste('Leave', id), message = '{n} edit{s}.',",
    "keep = 'Stay', discard = 'Reset', save = 'Store', saving = 'Working',",
    "save_failed = 'Try again.', unsaved = '(changed)'),",
    "on_save = function() {",
    "saved(saved() + 1L)",
    "if (saved() == 1L) return(FALSE)",
    "TRUE",
    "}, on_discard = function() discarded(discarded() + 1L))",
    "observeEvent(input$unsaved_nav_blocked, blocked(blocked() + 1L))",
    "output$blocked <- renderText(blocked())",
    "output$saved <- renderText(saved())",
    "output$discarded <- renderText(discarded())",
    "})",
    "ui <- fluidPage(unsaved_badge(), tabsetPanel(id = 'tabs',",
    "tabPanel('Form', value = 'form', module_ui('first'), module_ui('second')),",
    "tabPanel('Other', value = 'other', 'Other')))",
    "server <- function(input, output, session) {",
    "module_server('first')",
    "module_server('second')",
    "}",
    "shinyApp(ui, server)"
  ), "unsaved-features-", .local_envir = parent.frame())
  local_app_driver(path, load_timeout = 30000, .local_envir = parent.frame())
}

feature_dialog <- function(app) {
  app$wait_for_idle()
  app$run_js("document.querySelector('a[data-value=other]').click()")
  app$wait_for_idle()
}

test_that("custom text reach dialog, screen readers and save states", {
  app <- make_feature_app()
  app$set_inputs(`first-name` = "Grace", `second-name` = "Jo")
  feature_dialog(app)
  expect_equal(app$get_js("document.querySelector('.unsaved-dialog h2').textContent"), "Leave first")
  expect_equal(app$get_js("document.querySelector('.unsaved-dialog p').textContent"), "2 edits.")
  expect_equal(app$get_js("document.querySelector('.unsaved-sr').textContent"), "(changed)")
  expect_equal(app$get_js("document.querySelector('.unsaved-keep').textContent"), "Stay")
  expect_equal(app$get_js("document.querySelector('.unsaved-dialog .btn-outline-danger').textContent"), "Reset")
  expect_equal(app$get_js("document.querySelector('.unsaved-dialog .btn-primary').textContent"), "Store")
  app$run_js("
    window.heldSaved = [];
    var socket = Shiny.shinyapp.$socket;
    var original = socket.onmessage;
    socket.onmessage = function(event) {
      var data = typeof event.data === 'string' ? JSON.parse(event.data) : {};
      if (data.custom && data.custom['unsaved:saved']) {
        window.heldSaved.push(function() { original.call(socket, event); });
        return;
      }
      original.call(socket, event);
    };
  ")
  app$run_js("document.querySelector('.unsaved-dialog .btn-primary').click()")
  expect_equal(app$get_js("document.querySelector('.unsaved-dialog .btn-primary').textContent"), "Working")
  app$wait_for_idle()
  app$run_js("window.heldSaved.splice(0).forEach(function(reply) { reply(); })")
  expect_equal(app$get_js("document.querySelector('.unsaved-dialog [role=alert]').textContent"), "Try again.")
  expect_equal(app$get_js("document.querySelector('.unsaved-dialog .btn-primary').textContent"), "Store")
  expect_no_shiny_errors(app)
})

test_that("per-input comparison is used in a module browser", {
  app <- make_feature_app()
  app$set_inputs(`first-name` = " Ada ")
  app$wait_for_idle()
  expect_equal(badge_text(app), "")
  expect_equal(marker_count(app), 0)
  app$set_inputs(`first-raw` = " Ada ")
  app$wait_for_idle()
  expect_equal(badge_text(app), "1 unsaved change")
  expect_equal(marker_count(app), 1)
  expect_no_shiny_errors(app)
})

test_that("module nav input is namespaced and save and discard stay independent", {
  app <- make_feature_app()
  app$set_inputs(`first-name` = "Grace")
  feature_dialog(app)
  expect_equal(app$get_value(output = "first-blocked"), "1")
  expect_equal(app$get_value(output = "second-blocked"), "0")
  expect_equal(badge_text(app), "1 unsaved change")
  marked <- function(id) {
    app$get_js(paste0("document.getElementById('", id, "').closest('.shiny-input-container')",
                      ".hasAttribute('data-unsaved')"))
  }
  expect_equal(marked("first-name"), TRUE)
  expect_equal(marked("second-name"), FALSE)
  app$run_js("document.querySelector('.unsaved-dialog .btn-primary').click()")
  app$wait_for_idle()
  expect_equal(app$get_value(input = "tabs"), "form")
  app$run_js("document.querySelector('.unsaved-dialog .btn-primary').click()")
  app$wait_for_idle()
  expect_equal(app$get_value(input = "tabs"), "other")
  expect_equal(app$get_value(output = "first-saved"), "2")
  expect_equal(app$get_value(output = "second-saved"), "0")
  expect_equal(badge_text(app), "")
  app$set_inputs(tabs = "form", `first-name` = "Edited again")
  feature_dialog(app)
  app$run_js("document.querySelector('.unsaved-dialog .btn-outline-danger').click()")
  app$wait_for_idle()
  expect_equal(app$get_value(input = "first-name"), "Grace")
  expect_equal(app$get_value(input = "second-name"), "Ada")
  expect_equal(badge_text(app), "")
  expect_no_shiny_errors(app)
})

test_that("dialog discard callback runs once for the involved module", {
  app <- make_feature_app()
  app$set_inputs(`second-name` = "Grace")
  feature_dialog(app)
  expect_equal(app$get_js("document.querySelector('.unsaved-dialog h2').textContent"), "Leave second")
  expect_equal(app$get_js("document.querySelector('.unsaved-dialog p').textContent"), "1 edit.")
  app$run_js("document.querySelector('.unsaved-dialog .btn-outline-danger').click()")
  app$wait_for_idle()
  expect_equal(app$get_value(output = "second-discarded"), "1")
  expect_equal(app$get_value(output = "first-discarded"), "0")
  expect_equal(app$get_value(input = "second-name"), "Ada")
  expect_equal(app$get_value(input = "first-name"), "Ada")
  expect_equal(app$get_value(input = "tabs"), "other")
  expect_equal(badge_text(app), "")
  expect_no_shiny_errors(app)
})
