make_navigation_app <- function(bs5 = FALSE, navset = FALSE) {
  skip_on_cran()
  skip_if_not_installed("bslib")
  nav <- if (navset) {
    "bslib::navset_tab(id = 'tabs', bslib::nav_panel('Form', value = 'form', form),"
  } else {
    "tabsetPanel(id = 'tabs', tabPanel('Form', value = 'form', form),"
  }
  other <- if (navset) {
    "bslib::nav_panel('Other', value = 'other', 'Other panel')))"
  } else {
    "tabPanel('Other', value = 'other', 'Other panel')))"
  }
  theme <- if (bs5) "theme = bslib::bs_theme(version = 5)," else ""
  path <- local_app_file(c(
    "library(shiny)",
    "library(unsaved)",
    "form <- tagList(textInput('name', 'Name', 'Ada'),",
    "dateRangeInput('range', 'Range', '2026-01-01', '2026-01-31'),",
    "sliderInput('numeric_range', 'Numeric range', 0, 10, c(2, 8)),",
    "sliderInput('date_slider', 'Date slider', as.Date('2026-01-01'),",
    "as.Date('2026-12-31'), as.Date('2026-01-15')),",
    "sliderInput('date_slider_range', 'Date slider range', as.Date('2026-01-01'),",
    "as.Date('2026-12-31'), as.Date(c('2026-01-15', '2026-02-15'))),",
    "sliderInput('time_slider', 'Time slider', as.POSIXct('2026-01-01', tz = 'UTC'),",
    "as.POSIXct('2026-01-03', tz = 'UTC'), as.POSIXct('2026-01-02', tz = 'UTC')),",
    "actionButton('discard', 'Discard'))",
    paste("ui <- fluidPage(", theme, "unsaved_badge(),", nav),
    other,
    "server <- function(input, output, session) {",
    "tracker <- unsaved_track(c('tabs', 'name', 'range', 'numeric_range',",
    "  'date_slider', 'date_slider_range', 'time_slider'))",
    "observeEvent(input$discard, tracker$discard())",
    "}",
    "shinyApp(ui, server)"
  ), "unsaved-nav-", .local_envir = parent.frame())
  local_app_driver(path, .local_envir = parent.frame())
}

test_that("clean tab switches never become unsaved form changes", {
  app <- make_navigation_app()
  app$run_js("document.querySelector('a[data-value=other]').click()")
  app$wait_for_idle()
  expect_equal(app$get_js("document.querySelector('.unsaved-badge').textContent"), "")
  app$run_js("document.querySelector('a[data-value=form]').click()")
  app$wait_for_idle()
  expect_equal(app$get_value(input = "tabs"), "form")
  expect_equal(app$get_js("document.querySelector('.unsaved-dialog') === null"), TRUE)
  expect_no_shiny_errors(app)
})

test_that("bslib navsets expose tab ids and stay clean", {
  app <- make_navigation_app(bs5 = TRUE, navset = TRUE)
  expect_equal(app$get_js("document.getElementById('tabs').classList.contains('shiny-tab-input')"), TRUE)
  app$run_js("document.querySelector('a[data-value=other]').click()")
  app$wait_for_idle()
  expect_equal(app$get_js("document.querySelector('.unsaved-badge').textContent"), "")
  app$run_js("document.querySelector('a[data-value=form]').click()")
  app$wait_for_idle()
  expect_equal(app$get_value(input = "tabs"), "form")
  expect_no_shiny_errors(app)
})

test_that("Bootstrap 5 arrow keys and programmatic shows are guarded", {
  app <- make_navigation_app(bs5 = TRUE)
  app$set_inputs(name = "Grace")
  app$wait_for_idle()
  app$run_js("document.querySelector('a[data-value=form]').focus()")
  app$run_js("
    document.activeElement.dispatchEvent(new KeyboardEvent('keydown', {
      key: 'ArrowRight', bubbles: true, cancelable: true
    }));
  ")
  app$wait_for_idle()
  expect_equal(app$get_value(input = "tabs"), "form")
  expect_equal(app$get_js("document.querySelector('.unsaved-dialog') !== null"), TRUE)
  expect_equal(app$get_value(input = "unsaved_nav_blocked")$target, "other")
  app$run_js("document.querySelector('.unsaved-dialog button').click()")
  app$run_js("bootstrap.Tab.getOrCreateInstance(document.querySelector('a[data-value=other]')).show()")
  app$wait_for_idle()
  expect_equal(app$get_value(input = "tabs"), "form")
  expect_equal(app$get_js("document.querySelector('.unsaved-dialog') !== null"), TRUE)
  app$run_js("document.querySelector('.unsaved-dialog .btn-danger').click()")
  app$wait_for_idle()
  expect_equal(app$get_value(input = "tabs"), "other")
  expect_equal(app$get_value(input = "name"), "Ada")
  expect_no_shiny_errors(app)
})

test_that("clicking the already active tab keeps editing without a dialog", {
  for (bs5 in c(FALSE, TRUE)) {
    app <- make_navigation_app(bs5)
    app$set_inputs(name = "Grace")
    app$wait_for_idle()
    app$run_js("document.querySelector('a[data-value=form]').click()")
    app$wait_for_idle()
    expect_equal(app$get_value(input = "tabs"), "form")
    expect_equal(app$get_js("document.querySelector('.unsaved-dialog') === null"), TRUE)
    expect_no_shiny_errors(app)
    app$stop()
  }
})

test_that("date ranges and slider types discard through their bindings", {
  app <- make_navigation_app()
  ids <- c("range", "numeric_range", "date_slider", "date_slider_range", "time_slider")
  baseline <- lapply(ids, function(id) app$get_value(input = id))
  names(baseline) <- ids
  app$set_inputs(range = c("2026-02-01", "2026-02-28"), numeric_range = c(3, 7))
  app$run_js("
    ['date_slider', 'date_slider_range', 'time_slider'].forEach(function(id) {
      var el = document.getElementById(id);
      var value = id === 'date_slider_range' ? [Date.UTC(2026, 2, 1), Date.UTC(2026, 3, 1)] : Date.UTC(2026, 0, 1);
      window.jQuery(el).data('shiny-input-binding').setValue(el, value);
      window.jQuery(el).trigger('change');
    });
  ")
  app$wait_for_idle()
  app$click("discard")
  app$wait_for_idle()
  for (id in ids) {
    expect_equal(app$get_value(input = id), baseline[[id]], info = id)
  }
  expect_equal(app$get_js("document.querySelector('.unsaved-badge').textContent"), "")
  app$set_inputs(range = c("2026-02-01", "2026-02-28"))
  app$wait_for_idle()
  app$run_js("document.querySelector('a[data-value=other]').click()")
  app$run_js("document.querySelector('.unsaved-dialog .btn-danger').click()")
  app$wait_for_idle()
  expect_equal(app$get_value(input = "tabs"), "other")
  expect_equal(app$get_value(input = "range"), baseline$range)
  expect_equal(app$get_js("document.querySelector('.unsaved-badge').textContent"), "")
  expect_no_shiny_errors(app)
})
