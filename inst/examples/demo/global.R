# unsaved showcase -----------------------------------------------------------
# Run shiny::runApp(system.file("examples/demo", package = "unsaved")).
# All records are fictional and stay in memory for this session only.
# The showcase needs Shiny 1.7.4 or later because of bslib.
library(shiny)
library(bslib)
library(unsaved)

# Keep labels separate from ids for the live change list.
field_labels <- c(
  name = "Name", role = "Role", location = "Location",
  bio = "About", newsletter = "Team updates"
)
initial_records <- list(
  ada = list(name = "Ada Morgan", role = "Designer", location = "London",
             bio = "Making useful things for our team.", newsletter = TRUE),
  sam = list(name = "Sam Patel", role = "Developer", location = "Bristol",
             bio = "Building the next release.", newsletter = FALSE)
)
