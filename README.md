# unsaved <img src="man/figures/logo.png" align="right" height="139" alt="unsaved logo" />

<!-- badges: start -->
[![R-CMD-check](https://github.com/tenmeh/unsaved/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/tenmeh/unsaved/actions/workflows/R-CMD-check.yaml)
<!-- badges: end -->

`unsaved` tracks unsaved changes in Shiny forms and data-review apps. It
marks edited fields and tables, counts changes, and asks before navigation
or closing the browser tab loses them. Saves can require a reason for
change. Your app saves the records and keeps the audit trail.

## Try it

- [Lab result review](https://tenmeh.github.io/unsaved/articles/live-demo.html#lab-result-review): edit a table and save with a reason.
- [Team profile editor](https://tenmeh.github.io/unsaved/articles/live-demo.html#team-profile-editor): edit, save, discard and load records.

## Install

The package is not yet on CRAN. This line is ready for the first release:

```r
install.packages("unsaved")
```

For the development version, use remotes:

```r
remotes::install_github("tenmeh/unsaved")
```

## A small form

The example stores the name in memory for this session. Replace the save
callback with your app's storage code.

```r
library(shiny)
library(unsaved)

ui <- fluidPage(
  unsaved_badge(),
  textInput("name", "Name", "Ada"),
  actionButton("save", "Save")
)

server <- function(input, output, session) {
  saved_name <- reactiveVal("Ada")
  tracker <- unsaved_track("name", on_save = function() {
    saved_name(input$name)
    TRUE
  })
  observeEvent(input$save, tracker$save())
}

shinyApp(ui, server)
```

Returning `TRUE` tells the tracker that the save succeeded. The registered
callback also supplies Save and continue in the navigation dialog.
Browser close warnings use the browser's own text and may be suppressed.

## Learn more

- [Get started](https://tenmeh.github.io/unsaved/articles/get-started.html): build a form and load records.
- [Saving](https://tenmeh.github.io/unsaved/articles/saving.html): sync, async, reasons and audit trails.
- [Server values and tables](https://tenmeh.github.io/unsaved/articles/server-values.html): track edited data and choose comparisons.
- [Modules and navigation](https://tenmeh.github.io/unsaved/articles/modules-navigation.html): several trackers and guarded actions.
- [Limits and browser behaviour](https://tenmeh.github.io/unsaved/articles/limits.html): restoration, theming and accessibility.
- [Live demo](https://tenmeh.github.io/unsaved/articles/live-demo.html): both apps and things to try.

## What it does not do

- Store data, drafts or audit trails. Your app owns storage.
- Provide a compliance system.
- Undo and redo edits. Use [rewind](https://tenmeh.github.io/rewind/) for that.
