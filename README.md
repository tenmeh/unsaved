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

`unsaved_track(inputs)` returns a tracker. List the ids of the inputs that
make up your form, or supply server `values`. Optional names are labels, for example
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
| `ask_reason(action)` | Ask for a reason, then call `action(reason)` on Save. |
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

- `on_save()` must return exactly `TRUE`, or a promise that resolves to exactly
  `TRUE`, before the tracker marks values saved and permits navigation.
- If `on_save()` stops with an error or returns `FALSE`, the user stays on the
  tab, keeps their changes, and sees "Could not save. Your changes are still
  here." The error message goes to a server warning, not to the browser.
- Saving needs a round trip to the server, so the dialog waits while the server
  is busy. Discarding does not wait.
- With more than one tracker, the button shows only when every tracker with
  unsaved changes has an `on_save`.
- Other results, including NULL, NA, a number or an `ExtendedTask`, fail the
  save and raise one server warning.
- **Keep editing** cancels navigation, not a save already requested.

With several trackers, a shared Save and leave saves each tracker on its own.
One can succeed while another fails. Nothing is rolled back. Use one tracker
and one save for fields that must save together.

For asynchronous saving, read inputs before starting the worker and return
the promise. Configure a future worker plan when the app starts.

```r
tracker <- unsaved_track("name", on_save = function() {
  name <- input$name
  promises::future_promise({
    save_record(name)
    TRUE
  })
})
```

The promise must resolve to exactly `TRUE`. The tracker saves the snapshot
taken when the save starts, so edits made during the save stay unsaved.
A promise that resolves to `FALSE` or any other value, or rejects, keeps the
baseline and raises one server warning. Rejection messages stay on the server.
Only one save per tracker can be pending; another request is ignored with a
warning. The dialog shows "Saving..." until the reply. Keep editing cancels
navigation only. Return the promise, not an `ExtendedTask`; for example use
`promises::future_promise()` or `mirai::mirai()` wrapped in a promise.

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

## Track an edited table on the server

DT and rhandsontable send edit events, not a complete saved table. Keep the
edited table in a reactiveVal and give that reactive to `values`. This DT
example belongs inside the app's server function; the UI needs
`DT::DTOutput("visits_table")` and Save and Discard action buttons.

```r
table_rv <- reactiveVal(data.frame(visit = 1:3, score = c(2, 4, 6)))
tracker <- unsaved_track(
  inputs = character(),
  values = list(Visits = table_rv),
  value_outputs = c(Visits = "visits_table"),
  on_discard = function() table_rv(tracker$baseline()$Visits)
)
output$visits_table <- DT::renderDT({
  DT::datatable(table_rv(), editable = TRUE, rownames = FALSE,
                selection = "none")
}, server = TRUE)
observeEvent(input$visits_table_cell_edit, {
  table_rv(DT::editData(table_rv(), input$visits_table_cell_edit,
                       rownames = FALSE))
})
observeEvent(input$save, {
  save_visits(table_rv())  # your app's storage function
  tracker$mark_saved()
})
observeEvent(input$discard, tracker$discard())
```

The list names are the value ids and labels. They must be unique and must
not clash with input ids. Supply at least one input or value. A reactive
expression also works: its first available result becomes the baseline.
Data frames compare column by column, using the usual comparison rules;
`compare = list(Visits = identical)` selects an exact comparison.

Changed values appear in `is_dirty()`, `count()`, `changed()` and `diff()`,
and count towards the badge. For example, a change summary can read
"a table of 12 rows -> a table of 13 rows". Input changes appear first in
`diff()`, followed by server values in list order. `value_outputs` is optional:
without it, the value has no field marker. Use module-local output ids.

`mark_saved()` snapshots server values too. To supply saved data explicitly,
use `tracker$mark_saved(values = list(Visits = saved_table))`. The package
never sends these values to the browser, even on discard. The table widget
still renders the data that your app gives it. Restoring the reactiveVal is
the app's job: `discard()` calls `on_discard`, which reads `tracker$baseline()`
in the example. Without that callback, the edited server value stays dirty.

## Reason for change and audit trails

Set `require_reason = TRUE` to require a reason for Save and leave.
`on_save` must then take exactly one argument named `reason`. With the default
`require_reason = FALSE`, it must take no arguments.

The following server example appends changes to an in-memory audit table.
Replace this store with your app's persistent audit table, and write the
record and audit entry in one transaction. `authenticated_user()` must return
the user id from your app's authentication system.

```r
audit <- reactiveVal(data.frame())
save_with_reason <- function(reason) {
  changes <- tracker$diff()
  changes$reason <- rep(reason, nrow(changes))
  changes$user <- rep(authenticated_user(), nrow(changes))
  changes$timestamp <- rep(Sys.time(), nrow(changes))
  save_record(input$name)  # your app's storage function
  audit(rbind(audit(), changes))
  TRUE
}
tracker <- unsaved_track("name", require_reason = TRUE,
  on_save = function(reason) save_with_reason(reason))
observeEvent(input$save, {
  tracker$ask_reason(function(reason) {
    if (isTRUE(save_with_reason(reason))) tracker$mark_saved()
  })
})
```

The package does not store the audit trail; the app does. Capture `diff()`
before marking the values saved. This feature supplies a reason to your
app's audit code; it does not implement a regulatory compliance system.

The dialog has a required text area labelled "Reason for change". Save stays
disabled until the trimmed reason is non-empty. Reasons are trimmed and cut
to at most 1000 characters, with a visible counter. They go only to the
server and are never logged by the package. Callback errors use generic
package warnings when a reason is involved; handle diagnostics in your app
without exposing the reason.

`tracker$ask_reason(action)` always asks, even when clean or paused, and also
works with `require_reason = FALSE`. Its dialog has Cancel and Save buttons.
Cancel does nothing; Save calls `action(reason)` once. The action saves and
calls `mark_saved()` itself. Only one `confirm()` or `ask_reason()` can be
pending per tracker; a second request warns and is dropped.

Customise the label and the reason-only heading with
`unsaved_text(reason = "Reason for change",`
`reason_title = "Why are you making this change?")`. A shared Save and leave
dialog requires a reason if any involved tracker requires one; that reason
is passed to each callback that requires it.

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

Set the saved baseline before sending input updates. Here `records()` holds
saved records with the tracked fields `name` and `location`:

```r
observeEvent(input$load, {
  record_id <- input$record
  tracker$confirm(function() {
    record <- records()[[record_id]]
    tracker$mark_saved(values = record)
    updateTextInput(session, "name", value = record$name)
    updateTextInput(session, "location", value = record$location)
  })
})
```

`values` is a named list keyed by tracked input id. Omitted ids use their
current input values. Unknown ids are errors; password ids are ignored.
File values can be saved on the server but are never sent to the browser.
With no argument, `mark_saved()` still captures current input values.

The browser receives a clean state immediately. Until the updated values
return, server comparisons can briefly report the old inputs as dirty.
The next server comparison decides the state; matching echoes leave it clean.
Supply values with the types returned by each input binding. Use `confirm()`
before replacing edits, as above.

The pause, update, wait for every echo, `mark_saved()`, resume pattern is still
useful when the final values are not known in advance, or updates span several
round trips. Disable editing and saving while that load is pending. Paused
queries still report real differences; `is_paused()` can show a loading state.

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

- For cached, restorable inputs, the close-tab warning is armed as soon as the
  browser reports a changed value, even while the server is busy. Paused trackers
  and `guard_unload = FALSE` are excluded. Markers, badges, tab and click guards
  still follow the server. The browser uses JSON equality; the next server state
  wins, including custom comparisons. Password and file inputs have no
  provisional protection.
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

- Apply grid edit events to your data. Keep the edited table in a reactiveVal
  and track it with `values` as shown above.
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
