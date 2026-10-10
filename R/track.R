#' Track Unsaved Input Changes
#' @description Help users of Shiny forms see edits they have not saved and
#'   ask before they lose them. The app validates and saves its own data.
#' @param inputs Required non-empty character vector of unique input ids.
#'   Optional names are field labels; an empty name uses the id.
#' @param guard_nav Guard tab clicks, keyboard and programmatic tab navigation,
#'   including updateTabsetPanel(). To navigate while dirty, call mark_saved(),
#'   discard() (and wait for restored inputs), or pause() first.
#' @param guard_unload Warn on browser close or refresh. Browsers use generic
#'   wording and may suppress the prompt without prior user interaction.
#' @param guard_clicks Guard clicks on elements marked with unsaved_guard().
#'   Tagged tabs follow guard_nav instead.
#' @param on_save NULL or a function with no arguments. It must finish saving
#'   before it returns and return TRUE for success or FALSE for expected failure.
#'   Errors also fail the save. Any other result keeps changes unsaved and
#'   raises a server warning, including NULL, NA, promises and ExtendedTask.
#' @param on_discard NULL or a function with no arguments, called after each
#'   discard request. Errors become warnings. Inputs may not yet be restored; use
#'   baseline() for the restored values.
#' @param compare NULL for tolerant comparison, one function for all inputs,
#'   or a named list of functions keyed by tracked input id. Functions take
#'   saved and current values and return a single non-NA logical for equality.
#'   Numeric values use all.equal() with relative tolerance 1e-8 (absolute near
#'   zero). For exact amounts or ids, use `compare = list(amount = identical)`.
#' @param text Text returned by unsaved_text(). A shared dialog uses the
#'   text of its first involved tracker.
#' @param session The current Shiny session.
#' @return An UnsavedTracker R6 object with the methods below.
#' @section Methods:
#' Query methods read the real differences even while paused.
#'
#' - `is_dirty()`: Reactive scalar logical: TRUE if values differ.
#' - `count()`: Reactive scalar integer: number of changed fields.
#' - `changed()`: Reactive character vector of changed local input ids.
#' - `diff()`: Reactive data frame in input order, with name, label,
#'     change, saved and current columns. The last two are list columns.
#'     A clean tracker returns the same five columns with zero rows.
#' - `is_paused()`: Reactive scalar logical: TRUE while paused.
#' - `baseline()`: Non-reactive named list of saved values.
#' - `mark_saved()`: Non-reactive command. Replaces the baseline
#'     with current values after the app saves. Returns invisible self.
#' - `discard()`: Non-reactive command. Requests that the browser
#'     restore saved values, then calls on_discard without waiting for the
#'     inputs to return. Returns invisible self.
#' - `pause()`: Non-reactive command. Hides field markers and badge
#'     counts and disables all guards. Keeps the baseline and query state.
#'     Returns invisible self.
#' - `resume()`: Non-reactive command. Restores markers, badge
#'     counts and guards, comparing against the retained baseline.
#'     Returns invisible self.
#' - `confirm(action)`: Non-reactive command. Runs a function with
#'     no arguments at once when clean or paused, even with unsaved values.
#'     Otherwise asks first, then runs it after discard or successful save.
#'     Keep editing cancels the action, but not a save already requested.
#'     A second pending call warns and drops the new action.
#'     Returns invisible self, not the action result.
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
#'   Save and leave waits for a server round trip. Errors are caught without
#'   sending their messages to the browser. Discard sends JSON, so exotic R
#'   objects may not round-trip. Use module-local ids inside moduleServer().
#'
#'   The navigation guard and badges cover the whole page, not one form.
#'   For a multi-step form, use `guard_nav = FALSE` and unsaved_guard() on
#'   real exit buttons and links. guard_clicks defaults to TRUE independently.
#'   Use `tracker$confirm()` for server actions.
#'
#'   With several trackers, a shared Save and leave saves each one on its own.
#'   One can succeed while another fails; nothing is rolled back. Use one
#'   tracker and one save for fields that must save together. Starting work
#'   in the background and returning before it finishes is not supported.
#'
#' @section Loading a record:
#' Pause guards and markers, update inputs, wait for their values from the
#' browser, call mark_saved(), then resume(). Calling mark_saved() immediately
#' after updateTextInput() captures old server values. For a tracker listing
#' `name`, with `record` holding the new saved name, the server pattern is:
#' ```r
#' pending_record <- shiny::reactiveVal(NULL)
#' load_record <- function(record) {
#'   tracker$pause()
#'   pending_record(record)
#'   shiny::updateTextInput(session, "name", value = record$name)
#' }
#' shiny::observe({
#'   record <- pending_record()
#'   shiny::req(!is.null(record))
#'   if (identical(input$name, record$name)) {
#'     tracker$mark_saved()
#'     tracker$resume()
#'     pending_record(NULL)
#'   }
#' })
#' ```
#' Use confirm() before loading over edits. Disable editing, saving and further
#' loads while waiting. Check every updated field, using its binding's type.
#' A field appearing later takes its first value as saved.
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
#' problem, select Save and leave again to retry.
#'
#' @section Limits:
#' Dirty state needs a round trip to the server. An edit made while the server
#' is busy is protected only once the server has seen it and sent the new state
#' back to the browser. Browser close warnings may be suppressed.
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
unsaved_track <- function(inputs, guard_nav = TRUE, guard_unload = TRUE,
                          guard_clicks = TRUE, on_save = NULL, on_discard = NULL, compare = NULL,
                          text = unsaved_text(),
                          session = shiny::getDefaultReactiveDomain()) {
  valid_inputs <- !missing(inputs) && is.character(inputs) &&
    length(inputs) > 0L && !anyNA(inputs) && all(nzchar(inputs))
  if (!valid_inputs) {
    stop("`inputs` must contain at least one non-empty input id.", call. = FALSE)
  }
  session <- require_session(session)
  if (anyDuplicated(inputs)) stop("`inputs` must contain unique input ids.", call. = FALSE)
  if (anyNA(names(inputs))) stop("Field names must not be NA.", call. = FALSE)
  check_flag(guard_nav, "guard_nav")
  check_flag(guard_unload, "guard_unload")
  check_flag(guard_clicks, "guard_clicks")
  save_is_function <- is.function(on_save) && !is.primitive(on_save) &&
    length(formals(on_save)) == 0L
  if (!is.null(on_save) && !save_is_function) {
    stop("`on_save` must be NULL or a function with no arguments.", call. = FALSE)
  }
  discard_is_function <- is.function(on_discard) && !is.primitive(on_discard) &&
    length(formals(on_discard)) == 0L
  if (!is.null(on_discard) && !discard_is_function) {
    stop("`on_discard` must be NULL or a function with no arguments.", call. = FALSE)
  }
  if (!inherits(text, "unsaved_text")) {
    stop("`text` must be returned by unsaved_text().", call. = FALSE)
  }
  validate_compare(compare, inputs)
  UnsavedTracker$new(
    inputs = inputs, guard_nav = guard_nav, guard_unload = guard_unload,
    guard_clicks = guard_clicks, on_save = on_save, on_discard = on_discard, compare = compare,
    text = text, session = session
  )
}

UnsavedTracker <- R6Class("UnsavedTracker", cloneable = FALSE,
  public = list(
    initialize = function(inputs, guard_nav, guard_unload, guard_clicks,
                          on_save, on_discard, compare, text, session) {
      private$.text <- text
      private$.compare <- compare
      private$.on_discard <- on_discard
      private$.session <- session
      private$.inputs <- unname(inputs)
      field_names <- names(inputs) %||% rep("", length(inputs))
      field_names[!nzchar(field_names)] <- inputs[!nzchar(field_names)]
      private$.field_names <- structure(field_names, names = unname(inputs))
      private$.guard_clicks <- guard_clicks
      private$.pause_state <- shiny::reactiveVal(FALSE)
      private$.guard_nav <- guard_nav
      private$.guard_unload <- guard_unload
      private$.on_save <- on_save
      private$.instance <- session$ns(paste0("unsaved_", basename(tempfile())))
      private$.changed <- shiny::reactiveVal(character())
      private$.baseline <- list()
      asset <- htmltools::attachDependencies(
        htmltools::tags$span(),
        unsaved_dependency()
      )
      shiny::insertUI(
        selector = "body", where = "beforeEnd", ui = asset,
        session = session, immediate = TRUE
      )
      session$onFlushed(function() {
        private$.baseline <- shiny::isolate(private$current())
        private$.ready <- TRUE
        private$config()
        private$publish(character())
      }, once = TRUE)
      private$.observer <- shiny::observe({
        current <- private$current()
        if (private$.ready) {
          private$sync(current, join = !private$.paused)
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
      session$onSessionEnded(function() {
        private$.observer$destroy()
        private$.save_observer$destroy()
        private$.discard_observer$destroy()
        private$.confirm_observer$destroy()
      })
    },
    is_paused = function() private$.pause_state(),
    is_dirty = function() length(private$.changed()) > 0L,
    count = function() as.integer(length(private$.changed())),
    changed = function() private$.changed(),
    diff = function() {
      ids <- private$.changed()
      current <- private$current()
      input_diff(
        self$baseline(), current, private$.inputs,
        private$.field_names, private$.compare, ids
      )
    },
    confirm = function(action) {
      if (!is.function(action) || is.primitive(action) || length(formals(action)) != 0L) {
        stop("`action` must be a function with no arguments.", call. = FALSE)
      }
      shiny::isolate({
        if (!is.null(private$.pending)) {
          warning("A confirmation is already open, so this action was not run.", call. = FALSE)
        } else if (private$.paused || !self$is_dirty()) {
          action()
        } else {
          token <- basename(tempfile("confirm-"))
          private$.pending <- list(token = token, action = action)
          private$.session$sendCustomMessage("unsaved:confirm", list(
            instance = private$.instance, token = token
          ))
        }
      })
      invisible(self)
    },
    baseline = function() {
      shiny::isolate({
        snapshot_inputs(private$.baseline, private$.inputs, private$excluded_ids())
      })
    },
    mark_saved = function() {
      private$.baseline <- shiny::isolate(private$current())
      private$config()
      private$publish(character())
      invisible(self)
    },
    discard = function() {
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
      private$.paused <- TRUE
      private$.pause_state(TRUE)
      private$config()
      private$publish(shiny::isolate(private$.changed()))
      invisible(self)
    },
    resume = function() {
      private$.paused <- FALSE
      private$.pause_state(FALSE)
      shiny::isolate({
        current <- private$current()
        private$sync(current)
        private$config()
        if (private$.ready) private$publish(changed_inputs(private$.baseline, current, private$.compare))
      })
      invisible(self)
    }
  ),
  private = list(
    .session = NULL, .inputs = NULL, .instance = NULL, .on_save = NULL,
    .guard_nav = TRUE, .guard_unload = TRUE, .paused = FALSE, .ready = FALSE,
    .baseline = NULL, .changed = NULL, .observer = NULL, .save_observer = NULL,
    .text = NULL, .compare = NULL, .on_discard = NULL, .discard_observer = NULL,
    .field_names = NULL, .pending = NULL, .confirm_observer = NULL,
    .guard_clicks = TRUE, .pause_state = NULL,
    .password_ready = FALSE,
    .password_ids = NULL,
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
      passwords <- session$input$unsaved_password_ids %||% character()
      if (is.list(passwords) && "ids" %in% names(passwords)) passwords <- passwords$ids
      client_ids <- if (identical(session, session$rootScope())) {
        ids
      } else {
        vapply(ids, session$ns, character(1))
      }
      # Shiny can retain values after a widget is unbound; exclusions only grow.
      private$.password_ids <- union(private$.password_ids, ids[client_ids %in% passwords])
      union(ids[vapply(ids, session$ns, character(1)) %in% tabs], private$.password_ids)
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
      if (!private$fields_known()) return(list())
      snapshot_inputs(
        shiny::reactiveValuesToList(private$.session$input),
        private$.inputs,
        private$excluded_ids()
      )
    },
    sync = function(current, join = TRUE) {
      baseline <- snapshot_inputs(private$.baseline, private$.inputs, private$excluded_ids())
      if (join) baseline <- join_baseline(baseline, current)
      ready <- private$fields_known()
      if (!identical(baseline, private$.baseline) || ready != private$.password_ready) {
        private$.baseline <- baseline
        private$.password_ready <- ready
        private$config()
      }
    },
    # The client sends one request per tracker; each tracker answers only its own.
    handle_save = function(request) {
      if (!is.list(request) || !identical(request$instance, private$.instance)) {
        return(invisible(NULL))
      }
      ok <- FALSE
      if (!is.null(private$.on_save)) {
        # Errors stay on the server; the browser only learns that saving failed.
        result <- tryCatch(
          private$.on_save(),
          error = function(error) FALSE
        )
        ok <- identical(result, TRUE)
        if (!ok && !identical(result, FALSE)) {
          warning(
            "on_save() returned ", describe_value(result), ". ",
            "on_save() must return TRUE after it has finished saving. ",
            "The changes are kept as unsaved.",
            call. = FALSE
          )
        }
      }
      if (ok) self$mark_saved()
      private$.session$sendCustomMessage(
        "unsaved:saved",
        list(instance = private$.instance, ok = ok)
      )
    },
    handle_confirm = function(request) {
      pending <- private$.pending
      if (!is.list(request) || is.null(pending) ||
            !identical(request$instance, private$.instance) ||
            !identical(request$token, pending$token)) return(invisible(NULL))
      if (identical(request$choice, "keep")) {
        private$.pending <- NULL
      } else if (identical(request$choice, "discard")) {
        private$.pending <- NULL
        # The client has restored inputs and sent their echo before this event.
        private$notify_discard()
        pending$action()
      } else if (identical(request$choice, "save") && !self$is_dirty()) {
        private$.pending <- NULL
        pending$action()
      }
      invisible(NULL)
    },
    client_values = function() {
      shiny::isolate({
        if (!private$fields_known()) return(list())
        restorable_values(self$baseline())
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
        guardClicks = private$.guard_clicks && !private$.paused,
        guardNav = private$.guard_nav && !private$.paused,
        guardUnload = private$.guard_unload && !private$.paused
      ))
    },
    publish = function(ids) {
      private$.changed(ids)
      if (private$.paused) ids <- character()
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
