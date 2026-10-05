#' Track Unsaved Input Changes
#' @param inputs Required non-empty character vector of unique input ids.
#'   Optional names are field labels; an empty name uses the id.
#' @param guard_nav Guard clicks, keyboard and programmatic tab navigation,
#'   including updateTabsetPanel(). To navigate while dirty, call mark_saved(),
#'   discard() (and wait for restored inputs), or pause() first.
#' @param guard_unload Warn on browser close or refresh. Browsers use generic
#'   wording and may suppress the prompt without prior user interaction.
#' @param on_save NULL or a function with no arguments. Returning without error,
#'   except exactly FALSE, marks the inputs saved and permits navigation.
#' @param on_discard NULL or a function with no arguments, called after each
#'   discard. Errors become warnings. Inputs may not yet be restored; use
#'   baseline() for the restored values.
#' @param compare NULL for tolerant comparison, one function for all inputs,
#'   or a named list of functions keyed by tracked input id. Functions take
#'   saved and current values and return a single non-NA logical for equality.
#' @param text Text returned by unsaved_text(). A shared dialog uses the
#'   text of its first involved tracker.
#' @param session The current Shiny session.
#' @return An UnsavedTracker R6 object. is_dirty(), count() and changed() are
#'   reactive. diff() is reactive and returns name, label, change, saved and
#'   current columns, with the values in list columns, in input order.
#'   baseline() returns the saved snapshot without a dependency.
#'   mark_saved() replaces it after the app saves. discard() restores inputs
#'   through client bindings. pause() disables tracking and guards; resume()
#'   compares current inputs with the retained baseline.
#'   confirm(action) runs a function with no arguments at once when clean or
#'   paused. Otherwise it asks for confirmation and runs the action after
#'   discard or a successful save. Keep editing cancels the pending action.
#'   Calling confirm() while a confirmation is pending warns and drops the
#'   new action; it is not run or queued.
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
                          on_save = NULL, on_discard = NULL, compare = NULL,
                          text = unsaved_text(),
                          session = shiny::getDefaultReactiveDomain()) {
  valid_inputs <- !missing(inputs) && is.character(inputs) &&
    length(inputs) > 0L && !anyNA(inputs) && all(nzchar(inputs))
  if (!valid_inputs) {
    stop("`inputs` must be a character vector of input ids to track.", call. = FALSE)
  }
  session <- require_session(session)
  if (anyDuplicated(inputs)) stop("`inputs` must contain unique input ids.", call. = FALSE)
  if (anyNA(names(inputs))) stop("Field names must not be NA.", call. = FALSE)
  for (flag in list(guard_nav, guard_unload)) {
    if (!is.logical(flag) || length(flag) != 1L || is.na(flag)) {
      stop("Guard options must be single logical values.", call. = FALSE)
    }
  }
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
    on_save = on_save, on_discard = on_discard, compare = compare,
    text = text, session = session
  )
}

UnsavedTracker <- R6Class("UnsavedTracker", cloneable = FALSE,
  public = list(
    initialize = function(inputs, guard_nav, guard_unload, on_save, on_discard, compare, text, session) {
      private$.text <- text
      private$.compare <- compare
      private$.on_discard <- on_discard
      private$.session <- session
      private$.inputs <- unname(inputs)
      field_names <- names(inputs) %||% rep("", length(inputs))
      field_names[!nzchar(field_names)] <- inputs[!nzchar(field_names)]
      private$.field_names <- structure(field_names, names = unname(inputs))
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
          if (!private$.paused) {
            private$publish(changed_inputs(private$.baseline, current, private$.compare))
          }
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
      private$config()
      private$publish(character())
      invisible(self)
    },
    resume = function() {
      private$.paused <- FALSE
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
        ok <- tryCatch(
          !identical(private$.on_save(), FALSE),
          error = function(error) FALSE
        )
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
        guardNav = private$.guard_nav && !private$.paused,
        guardUnload = private$.guard_unload && !private$.paused
      ))
    },
    publish = function(ids) {
      private$.changed(ids)
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
