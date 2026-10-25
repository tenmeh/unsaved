server <- function(input, output, session) {
  batches <- reactiveVal(initial_batches)
  active_batch <- reactiveVal("B1")
  results_rv <- reactiveVal(initial_batches$B1$Results)
  saving <- reactiveVal(FALSE)
  audit <- reactiveVal(data.frame(
    batch = character(), field = character(), change = character(),
    sample_id = character(), column = character(), old_value = character(), new_value = character(),
    reason = character(), user = character(), timestamp = as.POSIXct(character())
  ))

  snapshot <- function() {
    list(Results = results_rv(), status = input$status, note = input$note)
  }
  save_review <- function(reason) {
    if (saving()) return(promises::promise_resolve(FALSE))
    # Capture everything now: later edits must not enter this save or its audit.
    saved <- snapshot()
    batch <- active_batch()
    changes <- tracker$diff()
    ordinary <- changes[changes$name != "Results", ]
    rows <- data.frame(field = ordinary$label, change = ordinary$change,
                       sample_id = rep("", nrow(ordinary)), column = rep("", nrow(ordinary)),
                       old_value = rep("", nrow(ordinary)), new_value = rep("", nrow(ordinary)))
    # The package describes a table briefly; the app records every changed cell
    # with a stable sample id and full values, including edits beyond that summary.
    if ("Results" %in% changes$name) {
      before <- tracker$baseline()$Results
      after <- saved$Results
      cell_text <- function(value) {
        if (is.na(value)) return("NA")
        if (identical(value, "")) return('""')
        as.character(value)
      }
      for (row in seq_len(nrow(before))) {
        for (column in names(before)) {
          old <- before[[column]][[row]]
          new <- after[[column]][[row]]
          if (isTRUE(all.equal(old, new, tolerance = 1e-8, check.attributes = FALSE))) next
          rows <- rbind(rows, data.frame(
            field = "Results", change = paste(cell_text(old), "->", cell_text(new)),
            sample_id = before$sample_id[row], column = column,
            old_value = cell_text(old), new_value = cell_text(new)
          ))
        }
      }
    }
    rows$batch <- rep(batch, nrow(rows))
    rows$reason <- rep(reason, nrow(rows))
    rows$user <- rep("demo reviewer", nrow(rows))
    rows$timestamp <- rep(Sys.time(), nrow(rows))
    saving(TRUE)
    promises::promise(function(resolve, reject) {
      later::later(function() {
        isolate({
          tryCatch({
            current <- batches()
            current[[batch]] <- saved
            next_audit <- rbind(audit(), rows)
            batches(current)
            audit(next_audit)
            saving(FALSE)
            # later() runs outside the session, so name it.
            showNotification(tagList("Saved. ", actionLink("view_audit", "View the audit trail")),
                             session = session)
            resolve(TRUE)
          }, error = function(error) {
            message("Review save failed; edits remain unsaved: ", conditionMessage(error))
            saving(FALSE)
            reject(error)
          })
        })
      }, delay = 0.6)
    })
  }
  tracker <- unsaved_track(
    c("Review status" = "status", "Review note" = "note"),
    values = list(Results = results_rv),
    value_outputs = c(Results = "results_table"),
    on_save = function(reason) save_review(reason), require_reason = TRUE,
    on_discard = function() results_rv(tracker$baseline()$Results),
    compare = list(note = unsaved_compare_text())
  )

  # Keep the table widget and its page in place as edits or restored values arrive.
  proxy <- DT::dataTableProxy("results_table", session = session)
  output$results_table <- DT::renderDT({
    DT::datatable(
      isolate(results_rv()), rownames = FALSE, selection = "none",
      editable = list(target = "cell", disable = list(columns = c(0, 1, 3))),
      options = list(pageLength = 6, dom = "t", ordering = FALSE)
    )
  })
  observeEvent(results_rv(), {
    DT::replaceData(proxy, results_rv(), rownames = FALSE, resetPaging = FALSE)
  }, ignoreInit = TRUE)
  observeEvent(input$results_table_cell_edit, {
    edit <- input$results_table_cell_edit
    req(all(edit$col %in% c(2, 4)))
    results_rv(DT::editData(results_rv(), edit, rownames = FALSE))
  })

  observeEvent(input$save, {
    req(!saving())
    tracker$save()
  })
  observeEvent(input$discard, {
    req(!saving())
    tracker$discard()
  })
  observeEvent(input$load, {
    req(!saving(), input$batch %in% names(batches()))
    batch <- input$batch
    tracker$confirm(function() {
      record <- batches()[[batch]]
      active_batch(batch)
      # Set the baseline before input echoes arrive from the browser.
      tracker$load_baseline(values = list(
        Results = record$Results, status = record$status, note = record$note
      ))
      results_rv(record$Results)
      updateSelectInput(session, "status", selected = record$status)
      updateTextAreaInput(session, "note", value = record$note)
    })
  })
  observeEvent(input$view_audit, nav_select("tabs", "audit", session = session))
  observe({
    session$sendCustomMessage("review-save", tracker$is_dirty() && !tracker$is_saving())
  })
  output$edited <- renderText(if ("Results" %in% tracker$changed()) "Edited" else "")
  output$batch_heading <- renderText(paste("Results for", active_batch()))
  output$save_state <- renderText({
    if (saving()) return("Saving...")
    if (tracker$is_dirty()) return("Unsaved edits. Save with a reason or discard.")
    "All changes saved."
  })
  output$changes <- renderUI({
    if (!nrow(tracker$diff())) return(tags$p("No unsaved changes."))
    tableOutput("change_table")
  })
  output$change_table <- renderTable(tracker$diff()[, c("label", "change")])
  output$audit_table <- DT::renderDT({
    rows <- audit()
    DT::datatable(rows[rev(seq_len(nrow(rows))), ], rownames = FALSE,
                  options = list(pageLength = 6, order = list(), scrollX = TRUE))
  })
}
