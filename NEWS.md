# unsaved 0.1.0

* First release.
* `unsaved_track()` marks changed fields and guards tab changes and browser close.
* Trackers support local input ids inside Shiny modules.
* Password fields are excluded from tracking and saved client snapshots.
* Named inputs supply field labels, with optional comparison and discard callbacks.
* `tracker$diff()` reports labels, change descriptions and saved and current values.
* Paused trackers hide markers and guards while keeping reactive queries truthful.
* `tracker$confirm(action, text = NULL)` asks before server actions when dirty,
  including while paused. Per-call text applies only to that dialog; action errors warn.
* `tracker$destroy()` removes trackers and handles module destruction automatically.
  All commands do nothing after destruction, and late browser messages are ignored.
* `unsaved_badge()` counts distinct changed fields across the page.
* `unsaved_compare_text()` provides whitespace and empty-text comparison rules.
* `unsaved_guard()` protects tagged clicks independently of tab guards.
* `unsaved_text()` sets dialog and screen-reader text.
* Dialogs offer Keep editing, Discard changes and optional Save and leave actions.
* Save callbacks may return promises resolving to TRUE; edits during a save
  stay unsaved. Failed promises, errors and invalid results warn.
* `tracker$mark_saved(values =)` acknowledges saved values and keeps later edits dirty.
  `tracker$load_baseline(values)` loads a record before input updates and publishes clean.
* `tracker$save()` shares the navigation save lifecycle; `is_saving()` reports pending saves.
  Save and leave stays open when edits made during saving remain unsaved, with
  `unsaved_text(save_incomplete =)` text. Escape and Keep editing wait for the reply.
* `unsaved_track()` lists inputs and values first, then saving, comparison, guards and text.
  Untracked input changes do not rerun tracking. Table summaries use vector comparisons
  and cached diffs, with "table changed" when a custom comparator finds other differences.
* Browser edits provisionally arm the close-tab warning while the server is busy.
* `unsaved_track(values =)` tracks server reactive values, with optional output
  markers through `value_outputs` and app-managed restoration on discard.
  Table change descriptions name up to three changed cells when rows and
  columns are unchanged, with a count of any remaining changed cells.
* `unsaved_track(require_reason = TRUE)` requires a reason for Save and leave
  and `tracker$save()`. `tracker$ask_reason()` remains available for app-managed saves, with button
  labels set through `unsaved_text(reason_cancel =, reason_save =)`.
