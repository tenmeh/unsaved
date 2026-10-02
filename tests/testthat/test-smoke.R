test_that("smoke helper checks stderr, browser logs and error outputs", {
  clean <- list(
    get_logs = function() data.frame(location = "shiny", message = "Ready", level = "info"),
    get_html = function(selector) NULL
  )
  expect_equal(collect_shiny_problems(clean), character())
  broken <- list(
    get_logs = function() {
      data.frame(
        location = c("shiny", "chromote"),
        message = c("Error: render failed", "TypeError"),
        level = c("warning", "error")
      )
    },
    get_html = function(selector) "<div class='shiny-output-error'>Failure</div>"
  )
  expect_length(collect_shiny_problems(broken), 3L)
})
