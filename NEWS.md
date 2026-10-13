# unsaved 0.1.0

* First release.
* `unsaved_track()` marks changed fields and guards tab changes and browser close.
* Trackers support local input ids inside Shiny modules.
* Password fields are excluded from tracking and saved client snapshots.
* Named inputs supply field labels, with optional comparison and discard callbacks.
* `tracker$diff()` reports labels, change descriptions and saved and current values.
* Paused trackers hide markers and guards while keeping reactive queries truthful.
* `tracker$confirm()` asks before server actions when dirty, including while paused.
* `tracker$destroy()` removes trackers and handles module destruction automatically.
* `unsaved_badge()` counts distinct changed fields across the page.
* `unsaved_compare_text()` provides whitespace and empty-text comparison rules.
* `unsaved_guard()` protects tagged clicks independently of tab guards.
* `unsaved_text()` sets dialog and screen-reader text.
* Dialogs offer Keep editing, Discard changes and optional Save and leave actions.
* Save callbacks must finish and return TRUE; errors and invalid results warn.
* `tracker$mark_saved(values =)` accepts a saved record before input updates.
* Browser edits provisionally arm the close-tab warning while the server is busy.
