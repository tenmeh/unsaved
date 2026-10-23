server <- function(input, output, session) {
  # Every visitor gets their own records. Nothing is written to disk.
  records <- reactiveVal(initial_records)
  active <- reactiveVal("ada")

  save_profile <- function() {
    values <- isolate(reactiveValuesToList(input))[names(field_labels)]
    current <- records()
    record <- current[[active()]]
    for (id in names(field_labels)) {
      if (!is.null(values[[id]])) record[[id]] <- values[[id]]
    }
    current[[active()]] <- record
    records(current)
    TRUE
  }
  text_ids <- c("name", "location", "bio")
  text_compare <- setNames(rep(list(unsaved_compare_text()), length(text_ids)), text_ids)
  tracker <- unsaved_track(
    setNames(names(field_labels), unname(field_labels)),
    on_save = save_profile,
    on_discard = function() showNotification("Changes discarded"),
    compare = text_compare
  )

  observeEvent(input$save, {
    save_profile()
    tracker$mark_saved()
  })
  observeEvent(input$discard, tracker$discard())

  observe({
    enabled <- tracker$is_dirty() && !tracker$is_saving()
    session$sendCustomMessage("profile-buttons", enabled)
  })
  output$load_control <- renderUI(actionButton("load", "Load another record"))

  # Confirm the action before replacing the current record.
  observeEvent(input$load, {
    req(input$record %in% names(records()))
    record_id <- input$record
    tracker$confirm(function() {
      active(record_id)
      record <- records()[[active()]]
      tracker$load_baseline(values = record)
      updateTextInput(session, "name", value = record$name)
      updateSelectInput(session, "role", selected = record$role)
      updateTextInput(session, "location", value = record$location)
      updateTextAreaInput(session, "bio", value = record$bio)
      updateCheckboxInput(session, "newsletter", value = record$newsletter)
    })
  })
  # Tag builders escape field values, including free text entered by visitors.
  display_value <- function(value) {
    if (is.null(value) || !length(value) || identical(value, "")) return("(empty)")
    if (is.logical(value)) return(if (value) "Yes" else "No")
    paste(value, collapse = ", ")
  }
  output$changes <- renderUI({
    if (tracker$is_paused()) return(tags$p("Loading profile..."))
    changes <- tracker$diff()
    if (!nrow(changes)) return(tags$p("No unsaved changes. Try editing a field."))
    tagList(lapply(seq_len(nrow(changes)), function(i) {
      tags$section(class = "border-bottom pb-3 mb-3",
        tags$strong(changes$label[i]),
        tags$div(class = "small text-muted", changes$change[i]),
        tags$div("Saved: ", display_value(changes$saved[[i]])),
        tags$div("Current: ", display_value(changes$current[[i]]))
      )
    }))
  })
  output$saved_profile <- renderUI({
    record <- records()[[active()]]
    tags$dl(lapply(names(field_labels), function(id) {
      tagList(tags$dt(field_labels[[id]]), tags$dd(display_value(record[[id]])))
    }))
  })
}
