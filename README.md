# unsaved <img src="man/figures/logo.png" align="right" height="139" alt="unsaved logo" />

<!-- badges: start -->
[![R-CMD-check](https://github.com/tenmeh/unsaved/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/tenmeh/unsaved/actions/workflows/R-CMD-check.yaml)
<!-- badges: end -->

[Try the live demo](https://tenmeh.github.io/unsaved/articles/live-demo.html).

Show a 'shiny' user which fields they have changed and not saved, and stop
them from losing those changes by accident.

- Changed fields get a marker next to their label.
- A badge shows the count, for example "2 unsaved changes".
- If the user tries to switch tabs with unsaved changes, a dialog asks them to
  keep editing, discard the changes, or (optionally) save and leave.
- If the user closes or refreshes the browser tab, the browser shows its own
  warning.

The package never saves data. Your app saves. You tell the tracker when a save
is done.

## Example

```r
library(shiny)
library(unsaved)

ui <- fluidPage(
  unsaved_badge(),
  textInput("name", "Name"),
  numericInput("age", "Age", 30),
  actionButton("save", "Save")
)

server <- function(input, output, session) {
  tracker <- unsaved_track(c("name", "age"))
  observeEvent(input$save, {
    # Save input$name and input$age to your own storage here, then:
    tracker$mark_saved()
  })
}

shinyApp(ui, server)
```

Run a larger demo with
`shiny::runApp(system.file("examples/demo", package = "unsaved"))`.

## The tracker

`unsaved_track(inputs)` returns a tracker. `inputs` is required: list the ids of
the inputs that make up your form. Action buttons, tab selections and the
package's own inputs are never tracked, even if you list them.

| Method | What it does |
|---|---|
| `is_dirty()` | Reactive. `TRUE` when at least one input differs from its saved value. |
| `count()` | Reactive. The number of changed inputs. |
| `changed()` | Reactive. The ids of the changed inputs. |
| `baseline()` | The saved values, as a named list. Not reactive. |
| `mark_saved()` | Call after your app saves. The current values become the saved values. |
| `discard()` | Put every input back to its saved value. |
| `pause()`, `resume()` | Stop and restart tracking, markers and guards. |

Use `is_dirty()` to protect your own destructive actions, for example to
disable a "Load another record" button while there are unsaved changes.

An input that appears after the app starts, for example from `renderUI()`,
takes its first value as its saved value. Only a later edit counts as a change.

## Save and leave

Give `unsaved_track()` an `on_save` function to add a **Save and leave** button
to the dialog:

```r
tracker <- unsaved_track(c("name", "age"), on_save = function() {
  save_record(input$name, input$age)  # your own save code
})
```

- If `on_save()` finishes without an error, the tracker marks the values saved
  and the user goes to the tab they clicked.
- If `on_save()` stops with an error or returns `FALSE`, the user stays on the
  tab, keeps their changes, and sees "Could not save. Your changes are still
  here." The error message stays on the server.
- Saving needs a round trip to the server, so the dialog waits while the server
  is busy. Discarding does not wait.
- With more than one tracker, the button shows only when every tracker with
  unsaved changes has an `on_save`.

## The navigation guard

While there are unsaved changes, the guard stops every tab change: a click, the
arrow keys, and `updateTabsetPanel()` from the server. To move tabs from the
server while dirty, call `mark_saved()`, `discard()` or `pause()` first. Use
`guard_nav = FALSE` to turn the guard off.

Each blocked change also sets the input `unsaved_nav_blocked`, so your app can
react to it.

## Limits

- Browsers show their own close or refresh warning, ignore any custom text, and
  may not show it at all if the user has not used the page. Treat it as a
  courtesy, not a guarantee.
- If your app calls `updateTextInput(label = )` or similar, the field marker
  disappears until the next change.
- `discard()` sends the saved values to the browser as JSON. Unusual R objects
  may not come back exactly. A file input cannot get its file back.
- An input inside a `renderUI()` that has not rendered yet is not tracked until
  it appears.
- The tracker is made for the top-level server function. Ids in modules go
  through `session$ns()`, but module use is not tested.

## For CSS

These names are stable, so you can style them:

| Selector | What it is |
|---|---|
| `[data-unsaved="true"]` | The container of a changed input |
| `.unsaved-sr` | The hidden "(unsaved)" text for screen readers |
| `.unsaved-badge` | The badge |
| `.unsaved-dialog` | The dialog panel |
| `.unsaved-backdrop` | The dialog backdrop |
