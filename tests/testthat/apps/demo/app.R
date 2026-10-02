library(shiny)
library(unsaved)

form_tab <- tabPanel(
  "Form",
  value = "form",
  textInput("name", "Name", "Ada"),
  numericInput("age", "Age", 30),
  radioButtons("choice", "Choice", c("A", "B")),
  actionButton("save", "Mark saved"),
  actionButton("discard", "Discard"),
  actionButton("pause", "Pause"),
  actionButton("resume", "Resume")
)
other_tab <- tabPanel(
  "Other",
  value = "other",
  checkboxInput("checked", "Checked", FALSE)
)
widgets_tab <- tabPanel(
  "Widgets",
  value = "widgets",
  selectInput("select", "Select", c("A", "B")),
  checkboxGroupInput("group", "Group", c("A", "B"), "A"),
  sliderInput("slider", "Slider", 0, 10, 5),
  dateInput("date", "Date", "2026-01-01"),
  dateRangeInput("range", "Range", "2026-01-01", "2026-01-31"),
  textAreaInput("area", "Text", "Hello"),
  passwordInput("password", "Password"),
  fileInput("file", "File")
)

ui <- fluidPage(
  titlePanel("Unsaved changes"),
  unsaved_badge(),
  tabsetPanel(id = "tabs", form_tab, other_tab, widgets_tab)
)

tracked <- c(
  "name", "age", "choice", "checked", "select", "group",
  "slider", "date", "range", "area", "file"
)

server <- function(input, output, session) {
  tracker <- unsaved_track(tracked)
  observeEvent(input$save, tracker$mark_saved())
  observeEvent(input$discard, tracker$discard())
  observeEvent(input$pause, tracker$pause())
  observeEvent(input$resume, tracker$resume())
}

shinyApp(ui, server)
