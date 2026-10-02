make_browser <- function() {
  skip_on_cran()
  local_app_driver(
    test_path("apps", "demo"),
    load_timeout = 30000,
    .local_envir = parent.frame()
  )
}

test_that("radio markers use the group label and preserve descriptions", {
  app <- make_browser()
  app$run_js("document.getElementById('choice').setAttribute('aria-describedby', 'existing')")
  app$set_inputs(choice = "B")
  app$wait_for_idle()
  expect_equal(app$get_js("document.querySelector('#choice > label').classList.contains('unsaved-marker')"), TRUE)
  expect_equal(app$get_js("document.querySelector('#choice .radio label').classList.contains('unsaved-marker')"), FALSE)
  description <- "document.getElementById('choice').getAttribute('aria-describedby')"
  expect_match(app$get_js(description), "existing unsaved-description")
  app$click("save")
  app$wait_for_idle()
  expect_equal(app$get_js(description), "existing")
  expect_no_shiny_errors(app)
})

test_that("navigation blocks, keeps editing, then discards and leaves", {
  app <- make_browser()
  app$set_inputs(name = "Grace")
  app$wait_for_idle()
  app$run_js("document.querySelector('a[data-value=other]').click()")
  expect_equal(app$get_value(input = "tabs"), "form")
  expect_equal(app$get_js("document.querySelector('.unsaved-dialog').getAttribute('role')"), "dialog")
  expect_equal(app$get_js("document.activeElement.textContent"), "Keep editing")
  expect_equal(app$get_js("document.activeElement.className"), "btn btn-secondary")
  keydown <- "document.activeElement.dispatchEvent(new KeyboardEvent('keydown', {key:'Tab', bubbles:true}))"
  app$run_js(keydown)
  expect_equal(app$get_js("document.activeElement.textContent"), "Discard changes")
  expect_equal(app$get_js("document.activeElement.className"), "btn btn-danger")
  app$run_js(keydown)
  expect_equal(app$get_js("document.activeElement.textContent"), "Keep editing")
  app$run_js("document.querySelector('.unsaved-dialog button').click()")
  expect_equal(app$get_value(input = "tabs"), "form")
  expect_equal(app$get_js("document.activeElement.getAttribute('data-value')"), "other")
  app$run_js("document.querySelector('a[data-value=other]').click()")
  app$run_js("document.querySelector('.unsaved-dialog .btn-danger').click()")
  app$wait_for_idle()
  expect_equal(app$get_value(input = "tabs"), "other")
  expect_equal(app$get_value(input = "name"), "Ada")
  expect_equal(marker_count(app), 0)
  expect_no_shiny_errors(app)
})

test_that("unload handlers are added while dirty and removed when clean", {
  app <- make_browser()
  app$run_js("
    window.unloadEvents = [];
    ['addEventListener', 'removeEventListener'].forEach(function(key) {
      var original = window[key];
      window[key] = function(type) {
        if (type === 'beforeunload') window.unloadEvents.push(key);
        return original.apply(this, arguments);
      };
    });
  ")
  app$set_inputs(name = "Grace")
  app$wait_for_idle()
  expect_equal(app$get_js("window.unloadEvents.join(',')"), "addEventListener")
  app$click("save")
  app$wait_for_idle()
  expect_equal(app$get_js("window.unloadEvents.join(',')"), "addEventListener,removeEventListener")
  expect_no_shiny_errors(app)
})

test_that("server attaches assets without a badge and trackers stay independent", {
  skip_on_cran()
  path <- local_app_file(c(
    "library(shiny)",
    "library(unsaved)",
    "ui <- fluidPage(textInput('x', 'X', 'a'), textInput('y', 'Y', 'b'), actionButton('save', 'Save X'))",
    "server <- function(input, output, session) {",
    "a <- unsaved_track('x')",
    "b <- unsaved_track('y')",
    "observeEvent(input$save, a$mark_saved())",
    "}", "shinyApp(ui, server)"
  ), "unsaved-app-")
  app <- local_app_driver(path)
  app$set_inputs(x = "changed", y = "changed")
  app$wait_for_idle()
  expect_equal(marker_count(app), 2)
  app$click("save")
  app$wait_for_idle()
  expect_equal(app$get_js(
    "document.getElementById('x').closest('.shiny-input-container').hasAttribute('data-unsaved')"
  ), FALSE)
  expect_equal(app$get_js(
    "document.getElementById('y').closest('.shiny-input-container').hasAttribute('data-unsaved')"
  ), TRUE)
  expect_no_shiny_errors(app)
})

test_that("badges, field markers, save and discard work", {
  app <- make_browser()
  app$set_inputs(name = "Grace")
  app$wait_for_idle()
  expect_equal(badge_text(app), "1 unsaved change")
  expect_equal(app$get_js(
    "document.getElementById('age').closest('.shiny-input-container').hasAttribute('data-unsaved')"
  ), FALSE)
  app$set_inputs(age = 31)
  app$wait_for_idle()
  expect_equal(badge_text(app), "2 unsaved changes")
  app$click("discard")
  app$wait_for_idle()
  expect_equal(app$get_value(input = "name"), "Ada")
  expect_equal(app$get_value(input = "age"), 30)
  app$set_inputs(name = "Grace")
  app$click("save")
  app$wait_for_idle()
  expect_equal(badge_text(app), "")
  expect_equal(marker_count(app), 0)
  expect_no_shiny_errors(app)
})

test_that("every restorable demo widget returns to its baseline", {
  app <- make_browser()
  ids <- c(
    "name", "age", "choice", "checked", "select", "group", "slider",
    "date", "range", "area", "password"
  )
  baseline <- lapply(ids, function(id) app$get_value(input = id))
  names(baseline) <- ids
  app$set_inputs(
    name = "Grace", age = 31, choice = "B", checked = TRUE,
    select = "B", group = c("A", "B"), slider = 6, date = "2026-02-01",
    range = c("2026-02-01", "2026-02-28"), area = "Changed", password = "test"
  )
  app$wait_for_idle()
  app$click("discard")
  app$wait_for_idle()
  for (id in ids) {
    expect_equal(app$get_value(input = id), baseline[[id]], info = id)
  }
  expect_equal(badge_text(app), "")
  app$set_inputs(tabs = "other")
  app$wait_for_idle()
  app$set_inputs(checked = TRUE)
  app$click("discard")
  app$wait_for_idle()
  expect_equal(app$get_value(input = "checked"), FALSE)
  app$set_inputs(tabs = "widgets")
  app$wait_for_idle()
  app$set_inputs(area = "Changed again")
  app$click("discard")
  app$wait_for_idle()
  expect_equal(app$get_value(input = "area"), "Hello")
  expect_no_shiny_errors(app)
})
