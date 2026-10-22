make_save_app <- function(save = "none", multi = FALSE, second_save = TRUE) {
  skip_on_cran()
  handler <- if (save == "none") "NULL" else "save_callback"
  second_handler <- if (second_save && save != "none") "save_callback" else "NULL"
  path <- local_app_file(c(
    "library(shiny)",
    "library(unsaved)",
    "ui <- fluidPage(unsaved_badge(), textOutput('saved_count'),",
    "tabsetPanel(id = 'tabs', tabPanel('Form', value = 'form',",
    "textInput('name', 'Name', 'Ada'), textInput('second', 'Second', 'First'),",
    "actionButton('appear', 'Show field'), actionButton('remove', 'Remove field'),",
    "actionButton('jump', 'Server navigation'), uiOutput('late_ui')),",
    "tabPanel('Other', value = 'other', 'Other panel')))",
    "server <- function(input, output, session) {",
    "saved <- reactiveVal(0L)",
    "save_callback <- function() {",
    "saved(saved() + 1L)",
    if (save == "error") "stop('Secret server detail')" else
      if (save == "false") "return(FALSE)" else
        if (save == "promise") paste0(
          "promises::promise(function(resolve, reject) {",
          "later::later(function() resolve(TRUE), delay = 1)})"
        ) else "TRUE",
    "}",
    paste0("tracker <- unsaved_track(c('tabs', 'name', 'late'), on_save = ", handler, ")"),
    if (multi) paste0("second <- unsaved_track('second', on_save = ", second_handler, ")") else "",
    "visible <- reactiveVal(FALSE)",
    "observeEvent(input$appear, visible(TRUE))",
    "observeEvent(input$remove, visible(FALSE))",
    "output$late_ui <- renderUI({",
    "if (visible()) textInput('late', 'Late field', 'First value')",
    "})",
    "output$saved_count <- renderText(saved())",
    "observeEvent(input$jump, updateTabsetPanel(session, 'tabs', selected = 'other'))",
    "}",
    "shinyApp(ui, server)"
  ), "unsaved-save-", .local_envir = parent.frame())
  local_app_driver(path, load_timeout = 30000, .local_envir = parent.frame())
}

open_dialog <- function(app) {
  app$set_inputs(name = "Grace")
  app$wait_for_idle()
  app$run_js("document.querySelector('a[data-value=other]').click()")
}

test_that("promise save waits then navigates after resolution", {
  app <- make_save_app(save = "promise")
  open_dialog(app)
  app$run_js("document.querySelector('.unsaved-dialog .btn-primary').click()")
  expect_equal(app$get_js("document.querySelector('.unsaved-dialog .btn-primary').textContent"),
               "Saving...")
  expect_equal(app$get_js("document.querySelector('a[data-value=form]').parentElement.classList.contains('active')"),
               TRUE)
  app$wait_for_js("document.querySelector('.unsaved-dialog') === null")
  app$wait_for_idle()
  expect_equal(app$get_value(input = "tabs"), "other")
  expect_equal(app$get_value(output = "saved_count"), "1")
  expect_equal(badge_text(app), "")
  expect_no_shiny_errors(app)
})

test_that("late renderUI field joins saved baseline and dialog discard restores it", {
  app <- make_save_app()
  app$click("appear")
  app$wait_for_idle()
  expect_equal(app$get_value(input = "late"), "First value")
  expect_equal(badge_text(app), "")
  app$set_inputs(late = "Edited value")
  app$wait_for_idle()
  expect_equal(badge_text(app), "1 unsaved change")
  app$run_js("document.querySelector('a[data-value=other]').click()")
  app$run_js("document.querySelector('.unsaved-dialog .btn-danger').click()")
  app$wait_for_idle()
  expect_equal(app$get_value(input = "late"), "First value")
  expect_equal(badge_text(app), "")
  expect_equal(app$get_value(input = "tabs"), "other")
  expect_no_shiny_errors(app)
})

test_that("dialog copy has full stops and omits save without a callback", {
  app <- make_save_app()
  open_dialog(app)
  expect_equal(app$get_js("document.querySelector('.unsaved-dialog h2').textContent"), "Unsaved changes")
  expect_equal(app$get_js("document.querySelector('.unsaved-dialog p').textContent"), "You have 1 unsaved change.")
  expect_equal(app$get_js("document.querySelectorAll('.unsaved-dialog button').length"), 2)
  app$run_js("document.querySelector('.unsaved-dialog .btn-secondary').click()")
  app$click("appear")
  app$wait_for_idle()
  app$set_inputs(late = "Edited")
  app$run_js("document.querySelector('a[data-value=other]').click()")
  expect_equal(app$get_js("document.querySelector('.unsaved-dialog p').textContent"), "You have 2 unsaved changes.")
  expect_no_shiny_errors(app)
})

test_that("save success calls the callback, navigates and clears dirty", {
  app <- make_save_app(save = "success")
  open_dialog(app)
  expect_equal(app$get_js("document.querySelector('.unsaved-dialog .btn-primary').textContent"), "Save and leave")
  expect_equal(app$get_js("document.activeElement.textContent"), "Keep editing")
  key <- "document.activeElement.dispatchEvent(new KeyboardEvent('keydown', {key:'Tab', bubbles:true}))"
  app$run_js(key)
  expect_equal(app$get_js("document.activeElement.textContent"), "Discard changes")
  app$run_js(key)
  expect_equal(app$get_js("document.activeElement.textContent"), "Save and leave")
  app$run_js(key)
  expect_equal(app$get_js("document.activeElement.textContent"), "Keep editing")
  app$run_js("document.querySelector('.unsaved-dialog .btn-primary').click()")
  app$wait_for_idle()
  expect_equal(app$get_value(output = "saved_count"), "1")
  expect_equal(app$get_value(input = "tabs"), "other")
  expect_equal(app$get_value(input = "name"), "Grace")
  expect_equal(badge_text(app), "")
  expect_equal(app$get_js("document.querySelector('.unsaved-dialog') === null"), TRUE)
  expect_no_shiny_errors(app)
})

test_that("save failure stays dirty, shows a safe alert and allows retry", {
  for (failure in c("error", "false")) {
    app <- make_save_app(save = failure)
    open_dialog(app)
    app$run_js("document.querySelector('.unsaved-dialog .btn-primary').click()")
    app$wait_for_idle()
    expect_equal(app$get_value(input = "tabs"), "form")
    expect_equal(badge_text(app), "1 unsaved change")
    alert <- app$get_js("document.querySelector('.unsaved-dialog [role=alert]').textContent")
    expect_equal(alert, "Could not save. Your changes are still here.")
    expect_equal(app$get_js("document.querySelector('.unsaved-dialog .btn-primary').disabled"), FALSE)
    expect_equal(app$get_js("document.querySelector('.unsaved-dialog .btn-danger').disabled"), FALSE)
    dialog_text <- app$get_js("document.querySelector('.unsaved-dialog').textContent")
    expect_equal(grepl("Secret server detail", dialog_text, fixed = TRUE), FALSE)
    expect_no_shiny_errors(app)
    app$stop()
  }
})

test_that("waiting save disables Keep editing and Escape until the reply", {
  app <- make_save_app(save = "success")
  open_dialog(app)
  # Hold the actual socket acknowledgement, then deliver it to the real handler.
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
  expect_equal(app$get_js("document.querySelector('.unsaved-dialog .btn-primary').textContent"), "Saving...")
  expect_equal(app$get_js("document.querySelector('.unsaved-dialog .btn-primary').disabled"), TRUE)
  expect_equal(app$get_js("document.querySelector('.unsaved-dialog .btn-danger').disabled"), TRUE)
  expect_equal(app$get_js("document.querySelector('.unsaved-dialog .btn-secondary').disabled"), TRUE)
  app$run_js("document.querySelector('.unsaved-dialog .btn-secondary').click()")
  app$run_js(paste0(
    "document.querySelector('.unsaved-dialog').dispatchEvent(",
    "new KeyboardEvent('keydown', {key: 'Escape', bubbles: true}));"
  ))
  expect_equal(app$get_js("document.querySelector('.unsaved-dialog') !== null"), TRUE)
  app$wait_for_idle()
  expect_equal(app$get_value(output = "saved_count"), "1")
  expect_equal(badge_text(app), "")
  expect_equal(app$get_value(input = "tabs"), "form")
  expect_equal(app$get_js("window.heldSaved.length"), 1)
  app$run_js("window.heldSaved.shift()()")
  app$wait_for_idle()
  expect_equal(app$get_value(input = "tabs"), "other")
  expect_equal(app$get_js("document.querySelector('.unsaved-dialog') === null"), TRUE)
  expect_no_shiny_errors(app)
})

test_that("save is offered only when every guarded dirty tracker can save", {
  app <- make_save_app(save = "success", multi = TRUE, second_save = FALSE)
  app$set_inputs(second = "Changed")
  open_dialog(app)
  expect_equal(app$get_js("document.querySelector('.unsaved-dialog .btn-primary') === null"), TRUE)
  expect_no_shiny_errors(app)
})

test_that("all guarded dirty trackers must save before navigation", {
  app <- make_save_app(save = "success", multi = TRUE)
  app$set_inputs(second = "Changed")
  open_dialog(app)
  app$run_js("document.querySelector('.unsaved-dialog .btn-primary').click()")
  app$wait_for_idle()
  expect_equal(app$get_value(output = "saved_count"), "2")
  expect_equal(app$get_value(input = "tabs"), "other")
  expect_equal(badge_text(app), "")
  expect_no_shiny_errors(app)
})

test_that("server updateTabsetPanel is guarded while dirty", {
  app <- make_save_app()
  app$set_inputs(name = "Grace")
  app$wait_for_idle()
  app$click("jump")
  app$wait_for_idle()
  expect_equal(app$get_value(input = "tabs"), "form")
  expect_equal(app$get_js("document.querySelector('.unsaved-dialog') !== null"), TRUE)
  app$run_js("document.querySelector('.unsaved-dialog .btn-danger').click()")
  app$wait_for_idle()
  expect_equal(app$get_value(input = "tabs"), "other")
  expect_equal(badge_text(app), "")
  expect_no_shiny_errors(app)
})
