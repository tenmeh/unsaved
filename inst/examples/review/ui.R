ui <- page_navbar(
  title = "Lab result review", id = "tabs", fillable = FALSE,
  theme = bs_theme(version = 5, primary = "#237A80",
                   bg = "#F7F5EF", fg = "#17202A"),
  header = tags$div(
    tags$script(src = "buttons.js"),
    class = "container py-3",
    card(class = "border-primary", card_body(tags$p(
      "Try this: double-click a result value, write a note, then leave Review. ",
      "Save with a reason and inspect the audit trail. Fictional study DEMO only."
    ))),
    textOutput("save_state")
  ),
  nav_panel("Review", value = "review",
    layout_columns(
      col_widths = c(8, 4),
      card(
        card_header(textOutput("batch_heading")),
        tags$p("Double-click a Value or Flag cell, edit it, then click outside the cell."),
        textOutput("edited", container = tags$small),
        DT::DTOutput("results_table")
      ),
      card(
        card_header("Review this batch"),
        selectInput("batch", "Batch to load", names(initial_batches)),
        actionButton("load", "Load batch"),
        tags$p(class = "small text-muted", "Loading asks before replacing unsaved edits."),
        selectInput("status", "Review status", c("Not started", "In review", "Reviewed")),
        textAreaInput("note", "Review note", rows = 3),
        tags$div(class = "d-flex gap-2 align-items-center",
          actionButton("save", "Save review", class = "btn-primary", disabled = "disabled"),
          unsaved_badge()
        ),
        actionButton("discard", "Discard changes")
      )
    )
  ),
  nav_panel("Changes", value = "changes",
    card(
      card_header("Live changes"),
      tags$p("The table is one tracked field, alongside status and note. ",
             "Leaving Review asks you to save, discard or keep editing."),
      uiOutput("changes")
    )
  ),
  nav_panel("Audit trail", value = "audit",
    card(
      card_header("Saved changes, newest first"),
      tags$p("The app, not unsaved, stores this audit trail. ",
             "All batches and audit rows last only for this session."),
      DT::DTOutput("audit_table")
    )
  )
)
