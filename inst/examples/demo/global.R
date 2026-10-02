# unsaved showcase -----------------------------------------------------------
# Run shiny::runApp(system.file("examples/demo", package = "unsaved")).
# All records are fictional and stay in memory for this session only.
library(shiny)
library(bslib)
library(unsaved)

# Keep labels separate from ids for the live change list.
field_labels <- c(
  name = "Name", role = "Role", location = "Location",
  bio = "About", newsletter = "Team updates", contact = "Contact note"
)
initial_records <- list(
  ada = list(name = "Ada Morgan", role = "Designer", location = "London",
             bio = "Making useful things for our team.", newsletter = TRUE,
             contact = "Available on Tuesdays"),
  sam = list(name = "Sam Patel", role = "Developer", location = "Bristol",
             bio = "Building the next release.", newsletter = FALSE,
             contact = "Available in the mornings")
)
