# Pre-CRAN polish: design

Date: 2026-10-22. Status: approved in discussion on 2026-10-22.

## Goal

Release `unsaved` 0.1.0 to CRAN with a save and load API that cannot report
edits as saved when they are not, a dialog that is correct for every action
and accessible, and documentation a new user can read in five minutes. New
features wait for 0.2.0.

Sources: five read-only reviews of 2026-10-22 (an API review with the
r-api-review skill, and reviews of missing features, design and UX,
engineering and CRAN readiness, and product lifecycle). The merged list is
in `verification/IDEAS-2026-10-22.md` (local only).

## Decisions

These were decided on 2026-10-22. "Yes to all recommendations."

1. **Two baseline commands.** `mark_saved(values = NULL)` acknowledges a
   save. `load_baseline(values)` loads a record. They have different
   contracts (see "Saving and loading").
2. **One managed save path.** New tracker methods `save()` and
   `is_saving()`. Save and leave, and the app's own Save button through
   `save()`, share one lifecycle. After a successful save, the browser
   leaves only if no tracked field is still dirty.
3. **Argument order.** `unsaved_track()` lists what to track, then saving,
   then guards, then text and session. Do not split saving into a separate
   `unsaved_save()` object.
4. **Neutral dialog wording.** The dialog says "continue", not "leave",
   because it also guards `confirm()` and `unsaved_guard()` actions.
   `confirm()` takes per-call text.
5. **Button order and weight.** Discard on the left as an outline button,
   then Keep editing, then Save on the right. Keep editing is the primary
   button when there is no Save.
6. **Native `<dialog>`.** Use `showModal()` for the focus trap, the inert
   page, top-layer stacking and the backdrop.
7. **Theming through CSS custom properties.** Rules sit under `:where()`. A
   changed output gets a dashed outline, not a solid one. The badge has a
   default Bootstrap class.
8. **Reason dialog.** Save stays enabled. An empty reason shows an inline
   error. The counter text is part of `unsaved_text()`. Cut text is
   announced.
9. **Scope.** 0.1.0 ships the fixes and decisions in this spec. Section
   "Deferred to 0.2.0" lists what waits.
10. **Docs.** The README becomes a short page. The long guide moves into
    pkgdown articles.

Rejected:

- `unsaved_save(action, require_reason)` as a separate save object
  (Astra's alternative B). It adds a concept and removes one argument.
- `value_labels`. Useful, but it can be added later without a break.
- A keyed cell-level change log in 0.1.0. Insert, delete and reorder rules
  need their own design first.

## API after this change

```r
unsaved_track(
  inputs = character(), values = NULL, value_outputs = NULL,
  on_save = NULL, require_reason = FALSE, on_discard = NULL,
  compare = NULL,
  guard_nav = TRUE, guard_unload = TRUE, guard_clicks = TRUE,
  text = unsaved_text(),
  session = shiny::getDefaultReactiveDomain()
)
```

Tracker methods, new or changed in **bold**:

- Queries: `is_dirty()`, `count()`, `changed()`, `diff()`, `is_paused()`,
  **`is_saving()`** (reactive logical), `baseline()`.
- Commands, all returning invisible self: **`mark_saved(values = NULL)`**,
  **`load_baseline(values)`**, **`save()`**, `discard()`, `pause()`,
  `resume()`, **`confirm(action, text = NULL)`**, `ask_reason(action)`,
  `destroy()`.

`unsaved_badge(label = ..., class = "badge text-bg-warning", live = TRUE)`:
`label` is one template, or `c(one = ..., other = ...)` for languages with
other plural rules. `live = FALSE` removes the live region.

`unsaved_text()` defaults:

| Field | Default |
|---|---|
| title | "Save your changes?" |
| message | "You have {n} unsaved change{s}. They will be lost if you continue without saving." |
| keep | "Keep editing" |
| discard | "Discard and continue" |
| save | "Save and continue" |
| saving | "Saving..." |
| save_failed | "Could not save. Your changes are still here. Try again or keep editing." |
| save_incomplete (new) | "Saved. Some changes were made while saving and are not saved yet." |
| unsaved | "Unsaved change" |
| reason | "Reason for change (required)" |
| reason_title | "Why are you making this change?" |
| reason_cancel | "Keep editing" |
| reason_save | "Save" |
| reason_missing (new) | "Enter a reason to save." |
| reason_count (new) | "{n} of {max} characters" |
| reason_cut (new) | "The reason was shortened to {max} characters." |

## Saving and loading

**`mark_saved(values = NULL)`** acknowledges that the app saved.

- With no `values`, the current values become the baseline, as today.
- With `values` (a named list, as today: tracked input and value ids,
  passwords ignored, unknown ids an error), those values overlay the
  current ones in the baseline.
- It then publishes the **real** state: current values compared with the
  new baseline. It never forces a clean state. Edits made after the
  snapshot stay dirty.

**`load_baseline(values)`** loads a record before its input updates.

- `values` is required, with the same validation as `mark_saved()`.
- This is today's `mark_saved(values =)` behaviour: it publishes a clean
  state at once, and the next server comparison decides. Input echoes that
  match the record leave the form clean.
- The README, articles and both showcase apps use it for loading.

**`save()`** runs the app's registered save.

- It is an error to call it on a tracker with no `on_save`.
- When the tracker is clean, it does nothing.
- When a save is pending, it warns and does nothing, as Save and leave
  does today.
- With `require_reason = TRUE`, it opens the reason dialog (title
  `reason_title`, buttons `reason_cancel` and `reason_save`). The dialog
  stays open with "Saving..." until the reply, and shows `save_failed` on
  failure, like Save and leave. Keep editing cancels before saving starts.
- Without a reason, it saves at once with no dialog.
- It takes a snapshot at the start, calls `on_save()` or
  `on_save(reason)`, and handles TRUE, FALSE, errors and promises exactly
  as Save and leave does. On success it calls `mark_saved(values =
  snapshot)`.
- Failure without a dialog raises the usual server warning. The app can
  observe `is_saving()` and `is_dirty()`.

**`is_saving()`** is TRUE from the start of a save until it settles, for
both `save()` and Save and leave.

**Save and leave after success.** The server publishes the state after
`mark_saved(values = snapshot)` and before the `unsaved:saved` reply (this
is already the order). The browser navigates only if that tracker has no
dirty ids. Otherwise the dialog stays open, the count updates, the buttons
return to normal, and the alert shows `save_incomplete`.

**`ask_reason(action)`** stays as the lower-level tool: it asks, then calls
`action(reason)`, and the app manages the save itself.

**`confirm(action, text = NULL)`**: `text` is NULL or a value from
`unsaved_text()`, used for this dialog only. An error in `action` (from
Discard or from Save) becomes a warning, as in `ask_reason()`; it never
ends the session.

## Fixes

1. **Destroyed trackers.** Every public command first checks for
   destruction: commands return invisible self and do nothing, `save()`
   included. The browser keeps a set of removed instances and ignores
   their messages, so nothing can rebuild them. Remove the tracker's
   insertUI span in `destroy()`.
2. **Escape and Keep editing while saving** are disabled while the dialog
   waits for a reply.
3. **Table summaries and custom comparison.** When the field's comparator
   says a table changed but the cell scan finds no difference, `change`
   reads "table changed". Document `change` as display text and
   `saved`/`current` as the evidence.
4. **Script version.** `unsaved_dependency()` uses
   `utils::packageVersion("unsaved")`. Add `utils` to Imports (base R, no
   new install).
5. **Input dependency.** A tracker reads only its tracked inputs and the
   package's own report inputs, not `reactiveValuesToList(session$input)`.
   Password ids grow in an observer, not inside a reactive.
6. **Faster table compare.** Compare changed columns as vectors, with NA
   handling, and stop the scan once three cells and the count are known.
   Cache the diff in a private reactive.
7. **A save that never settles.** Document it. `destroy()` clears the
   pending flag.
8. **CRAN-safe tests.** The review showcase's server test must not depend
   on wall-clock time on CRAN: use `skip_on_cran()` or settle promises
   deterministically.

## Dialog and design

1. **`<dialog>` element** with `showModal()`, `aria-labelledby` (title) and
   `aria-describedby` (message). The page behind is inert. Focus returns to
   the element that opened it. Escape follows "Keep editing", except while
   saving.
2. **Buttons.** The actions row is right-aligned. Order: Discard
   (`btn btn-outline-danger`, pushed left with `margin-right: auto`), Keep
   editing, Save (`btn btn-primary`). With no Save, Keep editing is
   `btn btn-primary`. Bootstrap 3: add `btn-default` next to
   `btn-secondary`. Below about 400px the buttons stack, full width, the
   primary one on top.
3. **Panel.** `max-height: calc(100dvh - 2rem)`, `overflow-y: auto`, a
   border `var(--bs-border-color-translucent)` and a shadow
   `var(--bs-box-shadow-lg)`, with fallbacks.
4. **CSS custom properties**, documented in the README "For CSS" table:
   `--unsaved-color` (default `var(--bs-primary, currentColor)`),
   `--unsaved-dot-size` (`.5em`), `--unsaved-outline` (`2px dashed
   var(--unsaved-color)`). All package rules sit under `:where()`. Note
   the 3:1 contrast rule for custom colours.
5. **Changed outputs** get the dashed outline, not a focus-like solid one.
6. **Reason field.** Save stays enabled. On an empty reason, set
   `aria-invalid="true"`, show `reason_missing` inline (linked by
   `aria-describedby`) and focus the text area. The counter uses
   `reason_count` with `form-text small` styling. A cut reason announces
   `reason_cut` once in the alert region. Only reassign the value when it
   is over the limit, so the caret and IME input are safe.
7. **Groups.** For radio and checkbox groups, describe the group with
   `role="group"` and `aria-labelledby`, or describe the first input.

## Showcase apps

- **Profile demo** (`inst/examples/demo`): remove the late contact field
  and the status text; use the default marker look; a three-step hint
  ("Edit Name. Click Preferences. Choose Save and continue."); Save and
  Discard disabled while clean; load records with `load_baseline()`.
- **Review app** (`inst/examples/review`): the hint in a callout card; the
  badge next to Save review; Save review disabled while clean and calling
  `tracker$save()`; an "Edited" caption on the table while it is changed;
  after a save, a notification "Saved. View the audit trail" with a link to
  the tab. The app's audit rows stay hand-built in the app.

## Docs

- **README**, about 80 lines: what it does, install, one example, the live
  demo links, links to articles.
- **Articles**: "Get started" (the tutorial), "Saving: sync, async,
  reasons and audit trails", "Server values and tables", "Modules and
  navigation", "Limits and browser behaviour", and the live demo. Add an
  `articles:` block to `_pkgdown.yml`; move `unsaved_dependency` under
  "Advanced" in the reference index.
- **NEWS**: a short summary for 0.1.0.
- **Release setup**: a `release.yaml` workflow like rewind's, a bug-report
  issue template (sessionInfo, shiny and bslib versions, browser, reprex)
  and CONTRIBUTING.md.

## Deferred to 0.2.0

- A keyed cell-level change log and changed-cell data for highlighting.
- `on_save` returning FALSE with a message, or a `can_save` reactive.
- Save and Discard buttons that enable with dirty state in the browser.
- Markers on the tab or section that holds changes.
- A disconnect notice and `allowReconnect()` docs.
- Guards for back and forward and URL routes.
- `discard(ids =)`.
- Reason rules: only for existing data, and a fixed list of reasons.
- `value_labels`.
- CI: a NOT_CRAN-unset job, a Shiny 1.7.0 floor job, bslib-dev,
  dependabot; an adapter section for Shiny internals in the JS.

## Not in this package

Storage of records, drafts or audit trails; e-signatures and compliance
claims; record locking or merging; a validation engine; grid editing; undo
(rewind); browser-stored drafts.

## Build plan

Three Astra rounds, each verified, committed and pushed on
`feat/pre-cran-polish`:

1. Saving and loading, the API order, and the fixes.
2. Dialog, design and the showcase apps.
3. Docs and release setup.

Then: make the repo public, deploy pkgdown, run the full CRAN check again,
and update cran-comments.md (cran-submission skill).
