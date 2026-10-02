#' Track Unsaved Input Changes
#' @param inputs Required non-empty character vector of input identifiers.
#' @param guard_nav Guard clicks, keyboard and programmatic tab navigation,
#'   including updateTabsetPanel(). To navigate while dirty, call mark_saved(),
#'   discard() (and wait for restored inputs), or pause() first.
#' @param guard_unload Warn on browser close or refresh. Browsers use generic
#'   wording and may suppress the prompt without prior user interaction.
#' @param on_save NULL or a function with no arguments. Returning without error,
#'   except exactly FALSE, marks the inputs saved and permits navigation.
#' @param session The current Shiny session.
#' @return An UnsavedTracker R6 object. is_dirty(), count() and changed() are
#'   reactive. baseline() returns the saved snapshot without a dependency.
#'   mark_saved() replaces it after the app saves. discard() restores inputs
#'   through client bindings. pause() disables tracking and guards; resume()
#'   compares current inputs with the retained baseline.
#' @details The initial values are captured on the first reactive flush.
#'   Listed inputs appearing later join the baseline with their first value.
#'   Removed inputs are ignored; returning inputs use their retained baseline.
#'   Tab metadata filters navigation inputs, including reports arriving after
#'   the first flush. File upload values are never sent in client snapshots.
#'   Save and leave waits for a server round trip. Errors are caught without
#'   sending their messages to the browser. Discard sends JSON, so exotic R
#'   objects may not round-trip. Module ids are namespaced; module use is untested.
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
                          on_save = NULL,
                          session = shiny::getDefaultReactiveDomain()) {
  valid_inputs <- !missing(inputs) && is.character(inputs) &&
    length(inputs) > 0L && !anyNA(inputs) && all(nzchar(inputs))
  if (!valid_inputs) {
    stop("`inputs` must be a character vector of input ids to track.", call. = FALSE)
  }
  session <- require_session(session)
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
  UnsavedTracker$new(inputs, guard_nav, guard_unload, on_save, session)
}

UnsavedTracker <- R6Class("UnsavedTracker", cloneable = FALSE,
  public = list(
    initialize = function(inputs, guard_nav, guard_unload, on_save, session) {
      private$.session <- session
      private$.inputs <- inputs
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
            private$publish(changed_inputs(private$.baseline, current))
          }
        }
      }, domain = session)
      private$.save_observer <- shiny::observeEvent(
        session$input$unsaved_save_requested,
        private$handle_save(session$input$unsaved_save_requested),
        ignoreInit = TRUE,
        domain = session
      )
      session$onSessionEnded(function() {
        private$.observer$destroy()
        private$.save_observer$destroy()
      })
    },
    is_dirty = function() length(private$.changed()) > 0L,
    count = function() as.integer(length(private$.changed())),
    changed = function() private$.changed(),
    baseline = function() {
      shiny::isolate({
        snapshot_inputs(private$.baseline, private$.inputs, private$tab_ids())
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
        if (private$.ready) private$publish(changed_inputs(private$.baseline, current))
      })
      invisible(self)
    }
  ),
  private = list(
    .session = NULL, .inputs = NULL, .instance = NULL, .on_save = NULL,
    .guard_nav = TRUE, .guard_unload = TRUE, .paused = FALSE, .ready = FALSE,
    .baseline = NULL, .changed = NULL, .observer = NULL, .save_observer = NULL,
    tab_ids = function() {
      tabs <- private$.session$input$unsaved_tab_ids %||% character()
      ids <- private$.inputs
      ids[vapply(ids, private$.session$ns, character(1)) %in% tabs]
    },
    current = function() {
      snapshot_inputs(
        shiny::reactiveValuesToList(private$.session$input),
        private$.inputs,
        private$tab_ids()
      )
    },
    sync = function(current, join = TRUE) {
      baseline <- snapshot_inputs(private$.baseline, private$.inputs, private$tab_ids())
      if (join) baseline <- join_baseline(baseline, current)
      if (!identical(baseline, private$.baseline)) {
        private$.baseline <- baseline
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
    client_values = function() {
      shiny::isolate(restorable_values(self$baseline()))
    },
    config = function() {
      values <- private$client_values()
      names(values) <- vapply(names(values), private$.session$ns, character(1))
      ns <- private$.session$ns
      private$.session$sendCustomMessage("unsaved:config", list(
        instance = private$.instance,
        baseline = na_to_null(values),
        tabInput = ns("unsaved_tab_ids"),
        saveInput = ns("unsaved_save_requested"),
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
