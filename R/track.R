#' Track Unsaved Input Changes
#' @description Help users of Shiny forms see edits they have not saved and
#'   ask before they lose them. The app validates and saves its own data.
#' @param inputs Character vector of unique input ids. May be empty when
#'   values are supplied. At least one input or value must be supplied.
#'   Optional names are field labels; an empty name uses the id.
#' @param values NULL or a uniquely named list of reactive expressions or
#'   reactiveVals. Names are both ids and labels and must not clash with inputs.
#'   Their first results become the baseline. Data frames compare column by
#'   column. These values never enter browser snapshots.
#' @param value_outputs NULL or a named character vector mapping value ids to
#'   output ids. The output is outlined while its value is changed. Use local ids in
#'   modules. Unmapped values count towards the badge but have no marker.
#' @param on_save NULL or a function with no arguments (or one argument named
#'   reason when require_reason is TRUE). It must finish saving
#'   before returning TRUE, or return a promise that resolves to exactly TRUE.
#'   FALSE, errors and other results fail the save. Failed promises raise one
#'   server warning. ExtendedTask results are unsupported; return the promise.
#'   Edits made while a promise is pending stay unsaved.
#' @param require_reason Require a reason before Save and continue or save(). If TRUE,
#'   on_save must have exactly one argument named reason. Otherwise it takes
#'   no arguments. Reasons are trimmed and cut to 1000 characters.
#' @param on_discard NULL or a function with no arguments, called after each
#'   discard request. Errors become warnings. Inputs may not yet be restored; use
#'   baseline() for the restored values.
#' @param compare NULL for tolerant comparison, one function for all inputs,
#'   or a named list of functions keyed by tracked input id. Functions take
#'   saved and current values and return a single non-NA logical for equality.
#'   Numeric values use all.equal() with relative tolerance 1e-8 (absolute near
#'   zero). For exact amounts or ids, use `compare = list(amount = identical)`.
#' @param guard_nav Guard tab clicks, keyboard and programmatic tab navigation,
#'   including updateTabsetPanel(). To navigate while dirty, call mark_saved(),
#'   discard() (and wait for restored inputs), or pause() first.
#' @param guard_unload Warn on browser close or refresh. Browsers use generic
#'   wording and may suppress the prompt without prior user interaction.
#' @param guard_clicks Guard clicks on elements marked with unsaved_guard().
#'   Tagged tabs follow guard_nav instead.
#' @param text Text returned by unsaved_text(). A shared dialog uses the
#'   text of its first involved tracker.
#' @param session The current Shiny session.
#' @return An UnsavedTracker R6 object with the methods below.
#' @section Methods:
#' Query methods read the real differences even while paused.
#' Every command returns invisible self and does nothing after destroy().
#'
#' - `is_dirty()`: Reactive scalar logical: TRUE if values differ.
#' - `count()`: Reactive scalar integer: number of changed fields.
#' - `changed()`: Reactive character vector of changed local input and value ids.
#' - `diff()`: Reactive data frame in input then value order, with name, label,
#'     change, saved and current columns. The last two are list columns.
#'     change is display text; saved and current hold the evidence. A custom
#'     comparison can report "table changed" without individual changed cells.
#'     A clean tracker returns the same five columns with zero rows.
#' - `is_paused()`: Reactive scalar logical: TRUE while paused.
#' - `is_saving()`: Reactive scalar logical: TRUE until a save settles.
#' - `baseline()`: Non-reactive named list of saved values.
#' - `mark_saved(values = NULL)`: Non-reactive command. Uses current inputs and values
#'     as the baseline, or overlays a named list of saved values keyed by
#'     tracked input or value id. Omitted ids use current values. Unknown ids are
#'     errors; passwords are ignored. File values stay on the server.
#'     Publishes the real state; later edits stay dirty. Returns invisible self.
#' - `load_baseline(values)`: Loads a named list before input updates. Uses the
#'     same validation and overlay as mark_saved(), but publishes clean at once.
#'     The next comparison decides the state. Returns invisible self.
#' - `save()`: Runs on_save with a starting snapshot. Requires on_save. Does
#'     nothing when clean; warns if a save is pending. With require_reason,
#'     asks for a reason and waits in the dialog until saving finishes.
#'     Failure without a dialog warns. Returns invisible self.
#' - `discard()`: Non-reactive command. Requests that the browser
#'     restore saved values, then calls on_discard without waiting for the
#'     inputs to return. Returns invisible self.
#' - `pause()`: Non-reactive command. Hides field markers and badge
#'     counts and disables all guards. Keeps the baseline and query state.
#'     Returns invisible self.
#' - `resume()`: Non-reactive command. Restores markers, badge
#'     counts and guards, comparing against the retained baseline.
#'     Returns invisible self.
#' - `confirm(action, text = NULL)`: Non-reactive command. Runs a function with
#'     no arguments at once when clean. Paused dirty trackers still ask.
#'     Otherwise asks first, then runs it after discard or successful save.
#'     text may be unsaved_text() for this dialog only. Action errors warn.
#'     Keep editing cancels before saving starts; it is disabled while saving.
#'     A second pending call warns and drops the new action.
#'     Returns invisible self, not the action result.
#' - `ask_reason(action)`: Non-reactive command. Always opens a reason-only
#'     dialog with Cancel and Save. Save calls action(reason) once; Cancel does
#'     nothing. The action must take one argument and must save and mark_saved()
#'     itself. Shares the pending confirmation slot with confirm(). Returns
#'     invisible self. Available whether or not require_reason is TRUE.
#' - `destroy()`: Stops tracking, cancels a pending confirmation and removes
#'     client markers, badge counts and guards. Repeated calls do nothing.
#'     Runs automatically on session end and on module destruction when
#'     supported by Shiny. Returns invisible self.
#'
#' @details Initial values are captured after the first reactive flush and
#'   the client's field report, so password values never enter the baseline.
#'   Listed inputs appearing later join the baseline with their first value.
#'   Removed inputs are ignored; returning inputs use their retained baseline.
#'   Tab metadata filters navigation inputs, including reports arriving after
#'   the first flush. File upload values are never sent in client snapshots.
#'   Password fields are never tracked. Cached values wait for the client's
#'   password report, and a late report removes an input from the snapshot.
#'   A reported password id stays excluded for the life of the tracker,
#'   including after the widget is removed or its id is reused.
#'   Save and continue waits for a server round trip. Errors are caught without
#'   sending their messages to the browser. Discard sends JSON, so exotic R
#'   objects may not round-trip. Use module-local ids inside moduleServer().
#'
#'   The navigation guard and badges cover the whole page, not one form.
#'   For a multi-step form, use `guard_nav = FALSE` and unsaved_guard() on
#'   real exit buttons and links. guard_clicks defaults to TRUE independently.
#'   Use `tracker$confirm()` for server actions.
#'
#'   With several trackers, a shared Save and continue saves each one on its own.
#'   One can succeed while another fails; nothing is rolled back. Use one
#'   tracker and one save for fields that must save together. Return a promise
#'   for background work. Only one save per tracker can be pending; further
#'   requests are ignored with a warning.
#'   A promise that never settles keeps is_saving() TRUE and the dialog waiting.
#'   The app must arrange its own timeout or rejection. destroy() clears the
#'   pending flag but does not cancel the app's work. After success, navigation
#'   proceeds only if no edits remain; otherwise save_incomplete is shown.
#'
#' @section Loading a record:
#' Set the saved baseline before sending input updates. Here `records()` holds
#' saved records with the tracked fields `name` and `location`:
#'
#' ```r
#' observeEvent(input$load, {
#'   record_id <- input$record
#'   tracker$confirm(function() {
#'     record <- records()[[record_id]]
#'     tracker$load_baseline(values = record)
#'     updateTextInput(session, "name", value = record$name)
#'     updateTextInput(session, "location", value = record$location)
#'   })
#' })
#' ```
#'
#' `values` is a named list keyed by tracked input id. Omitted ids use their
#' current input values. Unknown ids are errors; password ids are ignored.
#' File values can be saved on the server but are never sent to the browser.
#' With no argument, `mark_saved()` still captures current input values.
#'
#' The browser receives a clean state immediately. Until the updated values
#' return, server comparisons can briefly report the old inputs as dirty.
#' The next server comparison decides the state; matching echoes leave it clean.
#' Supply values with the types returned by each input binding. Use `confirm()`
#' before replacing edits, as above.
#'
#' The pause, update, wait for every echo, `mark_saved()`, resume pattern is still
#' useful when the final values are not known in advance, or updates span several
#' round trips. Disable editing and saving while that load is pending. Paused
#' queries still report real differences; `is_paused()` can show a loading state.
#'
#' @section Discard requests:
#' discard() sends a request to the browser; it does not synchronously restore
#' inputs or undo writes to storage. In on_discard, read the saved snapshot:
#' ```r
#' on_discard = function() {
#'   saved_values <- tracker$baseline()
#'   # Use this snapshot, not the not-yet-restored input values.
#' }
#' ```
#' Server values cannot be restored by the package. Restoring each reactiveVal
#' from tracker$baseline() in on_discard is the app's job. mark_saved() snapshots
#' server values too; mark_saved(values = list(Visits = saved_table)) overlays
#' their saved values by id. diff() lists input changes then server value changes.
#'
#' @section Reason for change and audit trails:
#' With require_reason = TRUE, Save and continue requires non-blank text labelled
#' by unsaved_text(reason = "Reason for change (required)"). ask_reason() uses reason_title
#' for its heading. Both trim the reason, limit it to 1000 characters and show
#' a counter. The reason goes only to the server; the package never logs it.
#' Record tracker$diff(), reason, the authenticated user and a timestamp in your
#' on_save callback before returning TRUE. The package does not store the audit
#' trail; the app does. Use a transaction for the record and audit writes.
#'
#' @section Save errors:
#' The app must log errors inside on_save(), then return FALSE. The browser
#' only sees the generic save failure message. For example:
#' ```r
#' on_save <- function() {
#'   tryCatch({
#'     save_record(input$name)
#'     TRUE
#'   }, error = function(error) {
#'     message("Save failed: ", conditionMessage(error))
#'     FALSE
#'   })
#' }
#' ```
#' Replace message() with your app's logger if needed. After correcting the
#' problem, select Save and continue again to retry.
#'
#' @section Limits:
#' For cached, restorable inputs, the close-tab warning is armed as soon as the
#' browser reports a changed value, even while the server is busy. Paused trackers
#' and `guard_unload = FALSE` are excluded. Markers, badges, tab and click guards
#' still follow the server. The browser uses JSON equality; the next server state
#' wins, including custom comparisons. Password and file inputs have no
#' provisional protection.
#' Browser close warnings may be suppressed.
#'
#' discard() restores saved values through supported Shiny bindings. It is
#' tested with text, text area and numeric inputs; radio buttons, checkboxes
#' and checkbox groups; select inputs with the default selectize binding;
#' date inputs and ranges; numeric sliders and ranges; date sliders and ranges;
#' and date-time sliders. It cannot restore file uploads, password fields or
#' inputs without a Shiny binding. Missing elements are skipped. It does not
#' undo app-side writes to storage.
#' @examples
#' if (interactive()) {
#'   shiny::shinyApp(
#'     shiny::fluidPage(unsaved_badge(), shiny::textInput("name", "Name")),
#'     function(input, output, session) {
#'       unsaved_track("name")
#'     }
#'   )
#' }
#' @export
#' @importFrom R6 R6Class
unsaved_track <- function(inputs = character(), values = NULL, value_outputs = NULL,
                          on_save = NULL, require_reason = FALSE, on_discard = NULL,
                          compare = NULL,
                          guard_nav = TRUE, guard_unload = TRUE, guard_clicks = TRUE,
                          text = unsaved_text(),
                          session = shiny::getDefaultReactiveDomain()) {
  valid_inputs <- is.character(inputs) && !anyNA(inputs) && all(nzchar(inputs))
  if (!valid_inputs) {
    stop("`inputs` must contain at least one non-empty input id.", call. = FALSE)
  }
  if (anyDuplicated(inputs)) stop("`inputs` must contain unique input ids.", call. = FALSE)
  if (anyNA(names(inputs))) stop("Field names must not be NA.", call. = FALSE)
  validate_tracked_values(values, inputs, value_outputs)
  if (!length(inputs) && !length(values)) {
    stop("`inputs` must contain at least one non-empty input id, or supply `values`.", call. = FALSE)
  }
  session <- require_session(session)
  check_flag(guard_nav, "guard_nav")
  check_flag(guard_unload, "guard_unload")
  check_flag(guard_clicks, "guard_clicks")
  check_flag(require_reason, "require_reason")
  if (require_reason) {
    check_reason_callback(on_save, "on_save", allow_null = TRUE)
  } else {
    check_callback(on_save, "on_save")
  }
  check_callback(on_discard, "on_discard")
  if (!inherits(text, "unsaved_text")) {
    stop("`text` must be returned by unsaved_text().", call. = FALSE)
  }
  validate_compare(compare, c(inputs, names(values)))
  UnsavedTracker$new(
    inputs = inputs, guard_nav = guard_nav, guard_unload = guard_unload,
    guard_clicks = guard_clicks, on_save = on_save, on_discard = on_discard, compare = compare,
    text = text, session = session, values = values,
    value_outputs = value_outputs, require_reason = require_reason
  )
}

UnsavedTracker <- R6Class("UnsavedTracker", cloneable = FALSE,
  public = list(
    initialize = function(inputs, guard_nav, guard_unload, guard_clicks,
                          on_save, on_discard, compare, text, session,
                          values, value_outputs, require_reason) {
      private$.text <- text
      private$.compare <- compare
      private$.on_discard <- on_discard
      private$.session <- session
      private$.inputs <- unname(inputs)
      private$.values <- values
      private$.ids <- c(unname(inputs), names(values))
      private$.value_outputs <- value_outputs
      private$.require_reason <- require_reason
      field_names <- names(inputs) %||% rep("", length(inputs))
      field_names[!nzchar(field_names)] <- inputs[!nzchar(field_names)]
      private$.field_names <- structure(field_names, names = unname(inputs))
      private$.field_names <- c(private$.field_names, stats::setNames(names(values), names(values)))
      private$.guard_clicks <- guard_clicks
      private$.pause_state <- shiny::reactiveVal(FALSE)
      # Module destruction runs callbacks after disabling module-owned reactives.
      private$.saving <- shiny::withReactiveDomain(session$rootScope(), shiny::reactiveVal(FALSE))
      private$.baseline_version <- shiny::reactiveVal(0L)
      private$.password_ids <- shiny::reactiveVal(character())
      private$.guard_nav <- guard_nav
      private$.guard_unload <- guard_unload
      private$.on_save <- on_save
      private$.instance <- session$ns(paste0("unsaved_", basename(tempfile())))
      private$.changed <- shiny::reactiveVal(character())
      private$.baseline <- list()
      private$.current <- shiny::reactive(private$current(), domain = session)
      private$.diff <- shiny::reactive({
        private$.baseline_version()
        input_diff(self$baseline(), private$.current(), private$.ids,
                   private$.field_names, private$.compare, private$.changed())
      }, domain = session)
      private$.password_observer <- shiny::observe({
        private$remember_passwords()
      }, priority = 100, domain = session)
      asset <- htmltools::attachDependencies(
        htmltools::tags$span(id = private$.instance),
        unsaved_dependency()
      )
      shiny::insertUI(
        selector = "body", where = "beforeEnd", ui = asset,
        session = session, immediate = TRUE
      )
      session$onFlushed(function() {
        if (private$.destroyed) return(invisible(NULL))
        private$.baseline <- shiny::isolate(private$.current())
        private$.ready <- TRUE
        private$config()
        private$publish(character())
      }, once = TRUE)
      private$.observer <- shiny::observe({
        current <- private$.current()
        if (private$.ready) {
          private$sync(current, join = !private$.pause_state())
          private$publish(changed_inputs(private$.baseline, current, private$.compare))
        }
      }, domain = session)
      private$.save_observer <- shiny::observeEvent(
        session$input$unsaved_save_requested,
        private$handle_save(session$input$unsaved_save_requested),
        ignoreInit = TRUE,
        domain = session
      )
      private$.discard_observer <- shiny::observeEvent(
        session$input$unsaved_discard_requested,
        {
          request <- session$input$unsaved_discard_requested
          if (is.list(request) && identical(request$instance, private$.instance)) {
            private$notify_discard()
          }
        },
        ignoreInit = TRUE,
        domain = session
      )
      private$.confirm_observer <- shiny::observeEvent(
        session$input$unsaved_confirm_requested,
        private$handle_confirm(session$input$unsaved_confirm_requested),
        ignoreInit = TRUE, domain = session
      )
      if (is.function(session$onDestroy)) session$onDestroy(self$destroy)
      session$onSessionEnded(self$destroy)
    },
    destroy = function() {
      if (private$.destroyed) return(invisible(self))
      private$.destroyed <- TRUE
      private$.observer$destroy()
      private$.save_observer$destroy()
      private$.discard_observer$destroy()
      private$.confirm_observer$destroy()
      private$.password_observer$destroy()
      private$.pending <- NULL
      private$.saving(FALSE)
      shiny::removeUI(selector = paste0("#", private$.instance),
                      session = private$.session, immediate = TRUE)
      private$.session$sendCustomMessage(
        "unsaved:remove", list(instance = private$.instance)
      )
      invisible(self)
    },
    is_paused = function() private$.pause_state(),
    is_saving = function() private$.saving(),
    is_dirty = function() length(private$.changed()) > 0L,
    count = function() as.integer(length(private$.changed())),
    changed = function() private$.changed(),
    diff = function() private$.diff(),
    confirm = function(action, text = NULL) {
      if (private$.destroyed) return(invisible(self))
      check_callback(action, "action", allow_null = FALSE)
      if (!is.null(text) && !inherits(text, "unsaved_text")) {
        stop("`text` must be NULL or returned by unsaved_text().", call. = FALSE)
      }
      shiny::isolate({
        if (!is.null(private$.pending)) {
          warning("A confirmation is already open, so this action was not run.", call. = FALSE)
        } else if (!self$is_dirty()) {
          private$run_action(action)
        } else {
          token <- basename(tempfile("confirm-"))
          private$.pending <- list(token = token, action = action)
          private$.session$sendCustomMessage("unsaved:confirm", list(
            instance = private$.instance, token = token, text = text
          ))
        }
      })
      invisible(self)
    },
    ask_reason = function(action) {
      if (private$.destroyed) return(invisible(self))
      check_reason_callback(action, "action")
      if (!is.null(private$.pending)) {
        warning("A confirmation is already open, so this action was not run.", call. = FALSE)
      } else {
        token <- basename(tempfile("reason-"))
        private$.pending <- list(token = token, action = action, reason_only = TRUE)
        private$.session$sendCustomMessage("unsaved:confirm", list(
          instance = private$.instance, token = token, reasonOnly = TRUE
        ))
      }
      invisible(self)
    },
    baseline = function() {
      shiny::isolate({
        private$select_values(private$.baseline)
      })
    },
    mark_saved = function(values = NULL) {
      if (private$.destroyed) return(invisible(self))
      private$set_baseline(values)
      shiny::isolate(private$publish(
        changed_inputs(private$.baseline, private$.current(), private$.compare)
      ))
      invisible(self)
    },
    load_baseline = function(values) {
      if (private$.destroyed) return(invisible(self))
      if (missing(values) || is.null(values)) {
        stop("`values` must be a uniquely named list of saved values.", call. = FALSE)
      }
      private$set_baseline(values)
      private$publish(character())
      invisible(self)
    },
    save = function() {
      if (private$.destroyed) return(invisible(self))
      if (is.null(private$.on_save)) stop("save() requires `on_save`.", call. = FALSE)
      shiny::isolate({
        if (private$.saving()) {
          warning("A save is already pending; the new save request was ignored.", call. = FALSE)
        } else if (self$is_dirty()) {
          if (private$.require_reason) {
            if (!is.null(private$.pending)) {
              warning("A confirmation is already open, so this action was not run.", call. = FALSE)
            } else {
              token <- basename(tempfile("save-"))
              private$.pending <- list(token = token, save_mode = TRUE)
              private$.session$sendCustomMessage("unsaved:confirm", list(
                instance = private$.instance, token = token, reasonOnly = TRUE, saveMode = TRUE
              ))
            }
          } else {
            private$handle_save(list(instance = private$.instance), dialog = FALSE)
          }
        }
      })
      invisible(self)
    },
    discard = function() {
      if (private$.destroyed) return(invisible(self))
      values <- private$client_values()
      names(values) <- vapply(names(values), private$.session$ns, character(1))
      private$.session$sendCustomMessage(
        "unsaved:restore",
        list(instance = private$.instance, inputs = na_to_null(values))
      )
      private$notify_discard()
      invisible(self)
    },
    pause = function() {
      if (private$.destroyed) return(invisible(self))
      private$.pause_state(TRUE)
      private$config()
      private$publish(shiny::isolate(private$.changed()))
      invisible(self)
    },
    resume = function() {
      if (private$.destroyed) return(invisible(self))
      private$.pause_state(FALSE)
      shiny::isolate({
        current <- private$.current()
        private$sync(current)
        private$config()
        if (private$.ready) private$publish(changed_inputs(private$.baseline, current, private$.compare))
      })
      invisible(self)
    }
  ),
  private = list(
    .session = NULL, .inputs = NULL, .instance = NULL, .on_save = NULL,
    .guard_nav = TRUE, .guard_unload = TRUE, .ready = FALSE,
    .baseline = NULL, .changed = NULL, .observer = NULL, .save_observer = NULL,
    .text = NULL, .compare = NULL, .on_discard = NULL, .discard_observer = NULL,
    .field_names = NULL, .pending = NULL, .confirm_observer = NULL,
    .guard_clicks = TRUE, .pause_state = NULL,
    .current = NULL, .destroyed = FALSE, .saving = NULL, .save_dialog = TRUE,
    .diff = NULL, .baseline_version = NULL, .password_observer = NULL,
    .password_ready = FALSE,
    .password_ids = NULL,
    .values = NULL, .ids = NULL, .value_outputs = NULL, .require_reason = FALSE,
    set_baseline = function(values) {
      if (!is.null(values)) {
        ids <- names(values)
        valid_names <- !length(values) || (!is.null(ids) && !anyNA(ids) &&
                                             all(nzchar(ids)) && !anyDuplicated(ids))
        if (!is.list(values) || is.data.frame(values) || !valid_names) {
          stop("`values` must be NULL or a uniquely named list of saved values.", call. = FALSE)
        }
        unknown <- setdiff(ids, private$.ids)
        if (length(unknown)) {
          stop("Unknown input id in `values`: ", paste(unknown, collapse = ", "),
               ". Tracked ids: ", paste(private$.ids, collapse = ", "), ".", call. = FALSE)
        }
      }
      shiny::isolate({
        baseline <- private$.current()
        values <- private$select_values(values)
        baseline[names(values)] <- values
        private$.baseline <- baseline
        private$.baseline_version(private$.baseline_version() + 1L)
      })
      private$config()
    },
    select_values = function(values) {
      c(snapshot_inputs(values, private$.inputs, private$excluded_ids()),
        values[intersect(names(values), names(private$.values))])
    },
    notify_discard = function() {
      if (!is.null(private$.on_discard)) {
        tryCatch(private$.on_discard(), error = function(error) {
          warning("on_discard() failed: ", conditionMessage(error), call. = FALSE)
        })
      }
      invisible(NULL)
    },
    excluded_ids = function() {
      tabs <- private$.session$input$unsaved_tab_ids %||% character()
      ids <- private$.inputs
      session <- private$.session
      union(ids[vapply(ids, session$ns, character(1)) %in% tabs], private$.password_ids())
    },
    remember_passwords = function() {
      ids <- private$.inputs
      session <- private$.session
      passwords <- session$input$unsaved_password_ids %||% character()
      if (is.list(passwords) && "ids" %in% names(passwords)) passwords <- passwords$ids
      client_ids <- if (identical(session, session$rootScope())) {
        ids
      } else {
        vapply(ids, session$ns, character(1))
      }
      # Shiny can retain values after a widget is unbound; exclusions only grow.
      private$.password_ids(union(shiny::isolate(private$.password_ids()), ids[client_ids %in% passwords]))
    },
    # Until the browser says which fields are passwords, nothing is snapshotted,
    # so a password never enters the saved values. testServer() has no browser
    # to report and no browser to leak to, so it starts at once. The package's
    # own tests set the option to act out a real browser that reports late.
    fields_known = function() {
      session <- private$.session
      if (!is.null(session$input$unsaved_password_ids)) return(TRUE)
      in_test_server <- inherits(session$rootScope(), "MockShinySession")
      in_test_server && !isTRUE(getOption("unsaved.wait_for_browser"))
    },
    current = function() {
      inputs <- if (!private$fields_known()) list() else snapshot_inputs(
        stats::setNames(lapply(private$.inputs, function(id) private$.session$input[[id]]), private$.inputs),
        intersect(private$.inputs, shiny::isolate(names(private$.session$input))),
        private$excluded_ids()
      )
      values <- list()
      for (id in names(private$.values)) {
        # A req() in one late value must not block the other tracked fields.
        result <- tryCatch(list(private$.values[[id]]()),
                           shiny.silent.error = function(error) NULL)
        if (!is.null(result)) values[id] <- result
      }
      c(inputs, values)
    },
    sync = function(current, join = TRUE) {
      baseline <- private$select_values(private$.baseline)
      if (join) baseline <- join_baseline(baseline, current)
      ready <- private$fields_known()
      if (!identical(baseline, private$.baseline) || ready != private$.password_ready) {
        private$.baseline <- baseline
        private$.password_ready <- ready
        private$config()
      }
    },
    # The client sends one request per tracker; each tracker answers only its own.
    handle_save = function(request, dialog = TRUE) {
      if (private$.destroyed) return(invisible(NULL))
      if (!is.list(request) || !identical(request$instance, private$.instance)) {
        return(invisible(NULL))
      }
      if (shiny::isolate(private$.saving())) {
        warning("A save is already pending; the new save request was ignored.", call. = FALSE)
        return(invisible(NULL))
      }
      snapshot <- shiny::isolate(private$.current())
      reason <- normalise_reason(request$reason)
      if (private$.require_reason && is.null(reason)) {
        private$.session$sendCustomMessage(
          "unsaved:saved", list(instance = private$.instance, ok = FALSE)
        )
        return(invisible(NULL))
      }
      ok <- FALSE
      result <- FALSE
      failed_with_error <- FALSE
      private$.save_dialog <- dialog
      private$.saving(TRUE)
      if (!is.null(private$.on_save)) {
        # Errors stay on the server; the browser only learns that saving failed.
        result <- tryCatch(
          if (private$.require_reason) private$.on_save(reason) else private$.on_save(),
          error = function(error) {
            failed_with_error <<- TRUE
            warning(
              "on_save() failed", if (!private$.require_reason) paste0(": ", conditionMessage(error)),
              ". The changes are kept as unsaved.", call. = FALSE
            )
            FALSE
          }
        )
        # promises is a Shiny dependency and is available whenever the app can
        # create a promise. Keep it in Suggests and guard namespace access.
        if (requireNamespace("promises", quietly = TRUE) && promises::is.promise(result)) {
          promises::then(result,
            onFulfilled = function(value) {
              private$finish_save(identical(value, TRUE), snapshot)
              if (!identical(value, TRUE)) {
                warning("on_save() promise resolved to ",
                        if (private$.require_reason) "an invalid result" else describe_value(value),
                        "; it must resolve to TRUE. The changes are kept as unsaved.",
                        call. = FALSE)
              }
              NULL
            },
            onRejected = function(error) {
              private$finish_save(FALSE, snapshot)
              # With a reason, the error may quote it, so leave the detail out.
              detail <- if (private$.require_reason) "" else paste0(": ", paste(
                if (inherits(error, "condition")) conditionMessage(error) else as.character(error),
                collapse = " "
              ))
              warning("on_save() promise rejected", detail,
                      ". The changes are kept as unsaved.", call. = FALSE)
              NULL
            }
          )
          return(invisible(NULL))
        }
        ok <- identical(result, TRUE)
        if (!ok && !identical(result, FALSE)) {
          warning(
            "on_save() returned ", if (private$.require_reason) "an invalid result" else describe_value(result), ". ",
            "on_save() must return TRUE after it has finished saving. ",
            if (inherits(result, "ExtendedTask")) paste0(
              "Return the promise instead, for example promises::future_promise() ",
              "or mirai::mirai() wrapped in a promise. "
            ),
            "The changes are kept as unsaved.",
            call. = FALSE
          )
        }
      }
      private$finish_save(ok, snapshot)
      if (!ok && identical(result, FALSE) && !dialog && !failed_with_error) {
        warning("on_save() failed. The changes are kept as unsaved.", call. = FALSE)
      }
    },
    finish_save = function(ok, snapshot) {
      if (private$.destroyed) return(invisible(NULL))
      private$.saving(FALSE)
      if (ok) {
        self$mark_saved(values = snapshot)
      }
      if (private$.save_dialog) {
        private$.session$sendCustomMessage(
          "unsaved:saved", list(instance = private$.instance, ok = ok)
        )
      }
      invisible(NULL)
    },
    handle_confirm = function(request) {
      if (private$.destroyed) return(invisible(NULL))
      pending <- private$.pending
      if (!is.list(request) || is.null(pending) ||
            !identical(request$instance, private$.instance) ||
            !identical(request$token, pending$token)) return(invisible(NULL))
      if (identical(request$choice, "keep")) {
        if (shiny::isolate(private$.saving())) return(invisible(NULL))
        private$.pending <- NULL
      } else if (isTRUE(pending$save_mode)) {
        if (identical(request$choice, "save")) private$.pending <- NULL
      } else if (isTRUE(pending$reason_only)) {
        reason <- normalise_reason(request$reason)
        if (identical(request$choice, "save") && !is.null(reason)) {
          private$.pending <- NULL
          tryCatch(pending$action(reason), error = function(error) {
            warning("The reason action failed.", call. = FALSE)
          })
        }
      } else if (identical(request$choice, "discard")) {
        private$.pending <- NULL
        # The client has restored inputs and sent their echo before this event.
        private$notify_discard()
        private$run_action(pending$action)
      } else if (identical(request$choice, "save") && !self$is_dirty()) {
        private$.pending <- NULL
        private$run_action(pending$action)
      }
      invisible(NULL)
    },
    run_action = function(action) {
      tryCatch(action(), error = function(error) {
        warning("The confirmation action failed: ", conditionMessage(error), call. = FALSE)
      })
    },
    client_values = function() {
      shiny::isolate({
        if (!private$fields_known()) return(list())
        restorable_values(snapshot_inputs(self$baseline(), private$.inputs))
      })
    },
    config = function() {
      values <- private$client_values()
      names(values) <- vapply(names(values), private$.session$ns, character(1))
      ns <- private$.session$ns
      private$.session$sendCustomMessage("unsaved:config", list(
        instance = private$.instance,
        baseline = na_to_null(values),
        tabInput = ns("unsaved_tab_ids"),
        passwordInput = ns("unsaved_password_ids"),
        saveInput = ns("unsaved_save_requested"),
        discardInput = ns("unsaved_discard_requested"),
        navInput = ns("unsaved_nav_blocked"),
        confirmInput = ns("unsaved_confirm_requested"),
        text = private$.text,
        canSave = !is.null(private$.on_save),
        requireReason = private$.require_reason,
        valueIds = as.list(unname(vapply(names(private$.values), ns, character(1)))),
        valueOutputs = stats::setNames(
          as.list(unname(vapply(private$.value_outputs, ns, character(1)))),
          vapply(names(private$.value_outputs), ns, character(1))
        ),
        guardClicks = private$.guard_clicks && !shiny::isolate(private$.pause_state()),
        guardNav = private$.guard_nav && !shiny::isolate(private$.pause_state()),
        guardUnload = private$.guard_unload && !shiny::isolate(private$.pause_state())
      ))
    },
    publish = function(ids) {
      private$.changed(ids)
      if (shiny::isolate(private$.pause_state())) ids <- character()
      client_ids <- unname(vapply(ids, private$.session$ns, character(1)))
      private$.session$sendCustomMessage("unsaved:state", list(
        instance = private$.instance,
        dirty = length(ids) > 0L,
        count = length(ids),
        ids = as.list(client_ids)
      ))
    }
  )
)
