# unsaved <img src="man/figures/logo.png" align="right" height="139" alt="unsaved logo" />

<!-- badges: start -->
[![R-CMD-check](https://github.com/tenmeh/unsaved/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/tenmeh/unsaved/actions/workflows/R-CMD-check.yaml)
<!-- badges: end -->

[Try the live demo](https://tenmeh.github.io/unsaved/articles/live-demo.html).

`unsaved` helps users of Shiny forms see what they have changed and not saved,
and asks before they lose it. It marks changed fields, counts the changes, and
asks before a tab change, a guarded button or a closed browser tab would discard
them. Use it for record editors, settings pages and data-entry forms: anywhere
with a Save button. Your app saves the data; `unsaved` tracks the values you
tell it are saved.

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

The navigation guard and badges cover the whole page, not one form. Every
badge counts distinct changed fields across all trackers, including modules.

## The tracker

`unsaved_track(inputs)` returns a tracker. `inputs` is required: list the ids of
the inputs that make up your form. Optional names are field labels, for example
`unsaved_track(c("Full name" = "name", Role = "role"))`. Ids must be unique.
Action buttons, tab selections and the package's own inputs are never tracked.
Password fields are never tracked because their values must stay out of saved
snapshots, browser caches and change summaries, even if you list their ids.
A reported password id stays excluded for the life of its tracker.

| Method | What it does |
|---|---|
| `is_dirty()` | Reactive. `TRUE` when at least one input differs from its saved value. |
| `count()` | Reactive. The number of changed inputs. |
| `changed()` | Reactive. The ids of the changed inputs. |
| `diff()` | Reactive. A change summary with field labels and saved/current list columns. |
| `is_paused()` | Reactive. `TRUE` while markers and guards are paused. |
| `baseline()` | The saved values, as a named list. Not reactive. |
| `mark_saved()` | Call after your app saves. The current values become the saved values. |
| `discard()` | Request that the browser restore saved values through input bindings. |
| `pause()`, `resume()` | Hide and restore markers, badge counts and guards; queries stay truthful. |
| `confirm(action)` | Run a function now if clean; otherwise ask, even while paused. |
| `destroy()` | Stop tracking and remove markers, badge counts and guards. Safe to repeat. |

Use `diff()` to build a review screen. It returns `name`, `label`, `change`,
`saved` and `current`, in the order of `inputs`, with one row per changed field.
The last two columns hold the original values as lists. Short values appear
as `"Ada -> Grace"`; longer values use short descriptions. A clean tracker
returns the same columns with no rows.

An input that appears after the app starts, for example from `renderUI()`,
takes its first value as its saved value. Only a later edit counts as a change.

## Save and leave

Give `unsaved_track()` an `on_save` function to add a **Save and leave** button
to the dialog:

```r
tracker <- unsaved_track(c("name", "age"), on_save = function() {
  save_record(input$name, input$age)  # your own save code
  TRUE
})
```

- `on_save()` must finish saving and return exactly `TRUE` before the tracker
  marks the values saved and permits navigation.
- If `on_save()` stops with an error or returns `FALSE`, the user stays on the
  tab, keeps their changes, and sees "Could not save. Your changes are still
  here." The error message goes to a server warning, not to the browser.
- Saving needs a round trip to the server, so the dialog waits while the server
  is busy. Discarding does not wait.
- With more than one tracker, the button shows only when every tracker with
  unsaved changes has an `on_save`.
- Any result other than `TRUE` or `FALSE`, including NULL, NA, a number, a
  promise or an `ExtendedTask`, fails the save and raises one server warning.
- **Keep editing** cancels navigation, not a save already requested.

With several trackers, a shared Save and leave saves each tracker on its own.
One can succeed while another fails. Nothing is rolled back. Use one tracker
and one save for fields that must save together.

### Save errors

Log errors inside your app's `on_save`, then return `FALSE`. The browser only
sees the generic message "Could not save. Your changes are still here."

```r
tracker <- unsaved_track(c("name", "age"), on_save = function() {
  tryCatch({
    save_record(input$name, input$age)
    TRUE
  }, error = function(error) {
    message("Save failed: ", conditionMessage(error))  # server log
    FALSE
  })
})
```

Use your app's logger in place of `message()` if needed. After correcting the
problem, the user can select Save and leave again to retry.

## The navigation guard

While there are unsaved changes, the guard stops every tab change: a click, the
arrow keys, and `updateTabsetPanel()` from the server. To move tabs from the
server while dirty, call `mark_saved()`, `discard()` or `pause()` first. Use
`guard_nav = FALSE` to turn the guard off.

For a multi-step form, allow movement between steps and confirm at the real
exit points:

```r
tracker <- unsaved_track(c("name", "age"), guard_nav = FALSE)
# In the UI: unsaved_guard(actionButton("exit", "Exit form"))
observeEvent(input$exit, updateTabsetPanel(session, "pages", "home"))
```

`unsaved_guard()` guards exit buttons and links with `guard_clicks = TRUE`,
which is the default even when `guard_nav = FALSE`. Use `tracker$confirm()`
for server actions. Tagged tabs always follow `guard_nav`.

Each blocked change also sets the input `unsaved_nav_blocked`, so your app can
react to it. Inside a module this input uses the module's namespace.

## Guard other actions

On the server, wrap a destructive action in `confirm()`:

```r
observeEvent(input$load, {
  tracker$confirm(function() load_record(input$record))
})
```

Clean trackers run the function at once. A dirty tracker asks even while paused.
Keep editing cancels. Discard restores inputs, calls `on_discard`, then runs
the action. Save and leave runs it only after a successful save. The action
runs once on the server. While one confirmation is pending, further calls
to that tracker warn and drop the new action. The new action is not run or
queued, and the first confirmation stays open. Capture a record id before
calling `confirm()` if the action must use the selection made at that time.

For a click in the browser, `unsaved_guard()` adds `data-unsaved-guard`:

```r
unsaved_guard(actionButton("delete", "Delete draft"))
unsaved_guard(tags$a(href = "/another-page", "Another page"))
```

You can also add the attribute yourself, including on a modal close button.
Dirty trackers with `guard_clicks = TRUE` block the click. Discard or a successful
save replays it once. Keep editing cancels it. Server confirmation works
independently of `guard_nav`.

## Text, comparison and discard callbacks

Set `text = unsaved_text(title = "Profile changes", keep = "Stay")` to change
dialog text. The message template accepts `{n}` and `{s}`. The helper also
sets `discard`, `save`, `saving`, `save_failed` and screen-reader `unsaved`
text. A shared dialog uses the first involved tracker's text.

Set `compare = unsaved_compare_text()` to ignore outer whitespace and treat
empty text as NULL. Set `trim = FALSE` or `empty_is_null = FALSE` to turn
either rule off. A custom function takes saved and current values and returns
one non-missing logical: TRUE means equal. Use a named list to apply functions
by input id, for example `compare = list(name = unsaved_compare_text())`.
Other fields use the default comparison, including its numeric tolerance.

Numeric values use `all.equal()` with tolerance `1e-8`. This is a relative
tolerance except near zero, where `all.equal()` uses an absolute difference.
For exact amounts or ids, use `compare = list(amount = identical)`.

`on_discard = function() ...` runs after server or dialog discard. Errors
become warnings. For a direct `discard()` call the restored inputs may not
have reached the server yet; use `tracker$baseline()` for their saved values.

A direct `discard()` is a request: the browser restores the inputs later.
Read the baseline in the callback:

```r
on_discard = function() {
  saved_values <- tracker$baseline()
  # Use this snapshot, not the not-yet-restored input values.
}
```

Restoration is tested with these Shiny inputs:

- Text and text area inputs, and numeric inputs.
- Radio buttons, checkboxes and checkbox groups.
- Select inputs (the default selectize binding).
- Date inputs and date ranges.
- Numeric sliders and ranges, date sliders and ranges, and date-time sliders.

`discard()` cannot restore file uploads, password fields or inputs without a
Shiny binding. Password fields are not tracked. Missing input elements are
skipped. Discard does not undo changes your app has already made to storage.

## Loading a record

While paused, `is_dirty()`, `count()`, `changed()` and `diff()` still report
real differences. Use reactive `is_paused()` to show a loading state.

Pause guards and markers, update the inputs, wait for the new values to arrive from the
browser, mark them saved, then resume. This server recipe loads two text fields
from your app's `records()` list:

```r
pending_record <- reactiveVal(NULL)
observeEvent(input$load, {
  req(is.null(pending_record()))
  record_id <- input$record
  tracker$confirm(function() {
    record <- records()[[record_id]]
    tracker$pause()
    pending_record(record)
    updateTextInput(session, "name", value = record$name)
    updateTextInput(session, "location", value = record$location)
  })
})
observe({
  record <- pending_record()
  req(!is.null(record))
  ready <- identical(input$name, record$name) &&
    identical(input$location, record$location)
  if (ready) {
    tracker$mark_saved()
    tracker$resume()
    pending_record(NULL)
  }
})
```

Here the tracker must list `name` and `location`. Disable editing and saving
while a load is pending, as guards are paused. Wait for every field that you
update, using the type its input binding returns. Calling `mark_saved()` right
after `update*Input()` is wrong: the updates have not reached the browser yet,
so it captures the old server values. A field that appears later takes its
first value as saved.

## Modules and rewind

For a module-local count, use a custom output. The built-in badge shows the
page total. Each module can use this pattern:

```r
editor_ui <- function(id) {
  ns <- NS(id)
  tagList(textInput(ns("name"), "Name"), textOutput(ns("count")))
}
editor_server <- function(id) {
  moduleServer(id, function(input, output, session) {
    tracker <- unsaved_track("name")
    output$count <- renderText(paste(tracker$count(), "changed fields"))
    tracker
  })
}
```

Inside `moduleServer()`, give `unsaved_track()` local input ids, without
`session$ns()`. Markers, saves, discards and event inputs use that module's
namespace. Multiple modules can share the count badge.

`rewind` is optional. Call `rewind::rewind_enable(inputs = ...)` alongside
`unsaved_track()` to add undo and redo. Undoing to the saved values clears
dirty state; redo restores it. Discard is an edit and can itself be undone.
For text, slow typing can make several history steps; use `updateOn = "blur"`
if you want one step per edit. Undo with rewind's controls or API: Ctrl+Z
inside a text box uses the browser's own undo.

## Limits

- Dirty state needs a round trip to the server. An edit made while the server
  is busy is protected only once the server has seen it and sent the new state
  back to the browser.
- Browsers show their own close or refresh warning, ignore any custom text, and
  may not show it at all if the user has not used the page. Treat it as a
  courtesy, not a guarantee.
- If your app calls `updateTextInput(label = )` or similar, the field marker
  disappears until the next change.
- `discard()` sends the saved values to the browser as JSON. Unusual R objects
  may not come back exactly. A file input cannot get its file back.
- An input inside a `renderUI()` that has not rendered yet is not tracked until
  it appears.

## What unsaved does not do

- Track grid edits in DT or rhandsontable as a whole table. An edit event is
  not the whole table; these editors need an app-specific adapter.
- Put back an uploaded file.
- Recover a lost session or its unsaved edits.
- Resolve conflicts between two users editing the same record.

## For CSS

These names are stable, so you can style them:

| Selector | What it is |
|---|---|
| `[data-unsaved="true"]` | The container of a changed input |
| `.unsaved-sr` | The hidden "(unsaved)" text for screen readers |
| `.unsaved-badge` | The badge |
| `.unsaved-dialog` | The dialog panel |
| `.unsaved-backdrop` | The dialog backdrop |
