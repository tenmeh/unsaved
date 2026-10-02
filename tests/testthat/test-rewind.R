test_that("rewind undo clears dirty, redo restores it and discard is undoable", {
  skip_on_cran()
  skip_if_not_installed("rewind")
  path <- local_app_file(c(
    "library(shiny)",
    "library(unsaved)",
    "library(rewind)",
    "ui <- fluidPage(unsaved_badge(), textInput('name', 'Name', 'Ada'),",
    "actionButton('undo', 'Undo'), actionButton('redo', 'Redo'),",
    "actionButton('discard', 'Discard'), textOutput('dirty'))",
    "server <- function(input, output, session) {",
    "rewind_enable(inputs = 'name', coalesce_ms = 0)",
    "tracker <- unsaved_track('name')",
    "observeEvent(input$undo, rewind_undo())",
    "observeEvent(input$redo, rewind_redo())",
    "observeEvent(input$discard, tracker$discard())",
    "output$dirty <- renderText(tracker$is_dirty())",
    "}",
    "shinyApp(ui, server)"
  ), "unsaved-rewind-")
  app <- local_app_driver(path, load_timeout = 30000)
  app$set_inputs(name = "Grace")
  app$wait_for_idle()
  expect_equal(app$get_value(output = "dirty"), "TRUE")
  expect_equal(marker_count(app), 1)
  app$click("undo")
  app$wait_for_idle()
  expect_equal(app$get_value(input = "name"), "Ada")
  expect_equal(app$get_value(output = "dirty"), "FALSE")
  expect_equal(badge_text(app), "")
  expect_equal(marker_count(app), 0)
  app$click("redo")
  app$wait_for_idle()
  expect_equal(app$get_value(input = "name"), "Grace")
  expect_equal(app$get_value(output = "dirty"), "TRUE")
  expect_equal(marker_count(app), 1)
  app$click("discard")
  app$wait_for_idle()
  expect_equal(app$get_value(input = "name"), "Ada")
  expect_equal(app$get_value(output = "dirty"), "FALSE")
  expect_equal(marker_count(app), 0)
  app$click("undo")
  app$wait_for_idle()
  expect_equal(app$get_value(input = "name"), "Grace")
  expect_equal(app$get_value(output = "dirty"), "TRUE")
  expect_equal(marker_count(app), 1)
  expect_no_shiny_errors(app)
})
