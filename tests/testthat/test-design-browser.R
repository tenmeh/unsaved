test_that("badge selects singular and plural templates", {
  skip_on_cran()
  path <- local_app_file(c(
    "library(shiny)",
    "library(unsaved)",
    "ui <- fluidPage(unsaved_badge(c(one = 'One edit', other = '{n} edits')),",
    "textInput('name', 'Name', 'Ada'), textInput('city', 'City', 'London'),",
    "actionButton('save', 'Save'))",
    "server <- function(input, output, session) {",
    "tracker <- unsaved_track(c('name', 'city'))",
    "observeEvent(input$save, tracker$mark_saved())",
    "}", "shinyApp(ui, server)"
  ), "unsaved-plural-")
  app <- local_app_driver(path)
  expect_equal(badge_text(app), "")
  app$run_js("$('#name').val('Grace').trigger('change')")
  app$wait_for_js("Shiny.shinyapp.$inputValues.name === 'Grace'")
  app$wait_for_idle()
  expect_equal(badge_text(app), "One edit")
  app$run_js("$('#city').val('York').trigger('change')")
  app$wait_for_js("Shiny.shinyapp.$inputValues.city === 'York'")
  app$wait_for_idle()
  expect_equal(badge_text(app), "2 edits")
  app$click("save")
  app$wait_for_idle()
  expect_equal(badge_text(app), "")
  expect_no_shiny_errors(app)
})
