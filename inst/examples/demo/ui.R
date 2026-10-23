ui <- page_sidebar(
  title = "unsaved: the team profile editor",
  theme = bs_theme(version = 5, primary = "#237A80",
                   bg = "#F7F5EF", fg = "#17202A"),
  fillable = FALSE,
  tags$script(src = "buttons.js"),
  sidebar = sidebar(
    title = "Your editing session", width = 320, open = "always",
    unsaved_badge(),
    actionButton("save", "Save profile", class = "btn-primary", disabled = "disabled"),
    actionButton("discard", "Discard changes", disabled = "disabled"),
    tags$hr(),
    selectInput("record", "Another team member",
                c("Ada Morgan" = "ada", "Sam Patel" = "sam")),
    uiOutput("load_control"),
    tags$p(class = "small text-muted",
           "Loading another record asks you to save or discard your edits. ",
           "Saved profiles last until you close this session.")
  ),
  card(
    class = "border-primary",
    card_body(
      # card_body() stacks its children, so the hint is one paragraph.
      tags$p(
        class = "mb-0",
        tags$strong("Try this:"),
        "Edit Name. Click Preferences. Choose Save and continue."
      )
    )
  ),
  layout_columns(
    col_widths = breakpoints(sm = c(12, 12), lg = c(7, 5)),
    navset_card_tab(
      id = "tabs",
      nav_panel("Profile", value = "profile",
        textInput("name", "Name", initial_records$ada$name),
        selectInput("role", "Role", c("Designer", "Developer", "Team lead")),
        textInput("location", "Location", initial_records$ada$location),
        textAreaInput("bio", "About", initial_records$ada$bio, rows = 3)
      ),
      nav_panel("Preferences", value = "preferences",
        tags$h3("Stay in touch"),
        checkboxInput("newsletter", "Team updates", TRUE),
        tags$p("This preference belongs to the same profile. ",
               "Unsaved changes protect navigation between all three tabs.")
      ),
      nav_panel("Saved profile", value = "saved",
        tags$p("This is the record in memory, after your last save."),
        uiOutput("saved_profile"),
        tags$p(class = "small text-muted",
               "The app saves the data. unsaved only tracks the saved state.")
      )
    ),
    card(
      card_header("What changed?"),
      tags$p(class = "small text-muted",
             "Saved and current values, from tracker$diff()."),
      uiOutput("changes")
    )
  )
)
