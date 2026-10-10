# unsaved 0.1.0

- `unsaved_track()` keeps its tracker object and six exports; help now lists every method.
- Paused trackers keep truthful queries and add reactive `is_paused()`; markers and guards stay hidden.
- `unsaved_track()` adds `guard_clicks` for tagged clicks, separate from tab-only `guard_nav`.
- `on_save()` must return exactly `TRUE` after saving; other results fail, with warnings except for `FALSE`.

* Disconnecting with a server confirmation open closes the dialog and clears the guards.
* `on_save()` rejects asynchronous results and keeps the changes unsaved.
* `confirm()` restores focus to the previous element when the dialog closes.
* First release.
* Trackers support local input ids inside Shiny modules.
* Password fields are never tracked or sent in saved client snapshots.
* `tracker$confirm()` protects server actions with the existing dialog.
  A call while a confirmation is pending warns and drops the new action.
* `tracker$diff()` gives field labels, short change descriptions and saved
  and current values in list columns, in the order of the tracked inputs.
* `unsaved_badge()` shows the number of unsaved changes.
* `unsaved_compare_text()` offers whitespace and empty-text comparison rules.
* `unsaved_guard()` protects button, modal close and link clicks.
* `unsaved_text()` sets dialog and screen-reader text. Shared dialogs use
  the first involved tracker's text.
* `unsaved_track()` tracks the inputs you list, marks changed fields, and
  guards tab changes and browser close while there are unsaved changes.
* `unsaved_track()` accepts named inputs for field labels, custom comparison
  functions and an `on_discard` callback. Duplicate input ids are rejected.
* `unsaved_track()` puts `session` last, after the text and comparison options.
* The dialog offers "Keep editing" and "Discard changes", and "Save and leave"
  when you give `unsaved_track()` an `on_save` function.
