# Lab result review: fictional data, held in memory for each session only.
# Run shiny::runApp(system.file("examples/review", package = "unsaved")).
library(shiny)
library(bslib)
library(unsaved)

initial_batches <- lapply(c("B1", "B2", "B3"), function(batch) {
  list(
    Results = data.frame(
      sample_id = paste0(batch, "-", sprintf("%03d", 1:6)),
      test = rep(c("Marker A", "Marker B"), 3),
      value = c(12, 24, 15, 28, 11, 22),
      unit = rep("demo units", 6),
      flag = c("", "", "Check", "Check", "", "")
    ),
    status = "Not started", note = ""
  )
})
names(initial_batches) <- c("B1", "B2", "B3")
