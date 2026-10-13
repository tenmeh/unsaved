test_that("input diff preserves order, labels, values and empty column types", {
  saved <- list(name = "Ada", role = "Designer", gone = "old", empty = NULL)
  current <- list(name = "Grace", role = "Developer", empty = "set", late = "first")
  fields <- c("role", "name", "empty", "gone", "late")
  out <- input_diff(saved, current, fields, c(role = "Role", name = "Full name", empty = ""))
  expect_equal(out$name, c("role", "name", "empty"))
  expect_equal(out$label, c("Role", "Full name", "empty"))
  expect_equal(out$change, c("Designer -> Developer", "Ada -> Grace", "set to set"))
  expect_equal(out$saved, list("Designer", "Ada", NULL))
  expect_equal(out$current, list("Developer", "Grace", "set"))
  expect_equal(input_diff(list(name = "Ada"), list(name = " Ada "), "name",
                          compare = unsaved_compare_text())$name, character())
  empty <- input_diff(list(), list(), character())
  expect_equal(names(empty), c("name", "label", "change", "saved", "current"))
  expect_equal(vapply(empty, typeof, character(1)),
               c(name = "character", label = "character", change = "character", saved = "list", current = "list"))
})

test_that("change descriptions follow rewind's short value rules", {
  expect_equal(format_change(NULL, NULL), "no change")
  expect_equal(format_change("Ada", NULL), "cleared")
  expect_equal(format_value(""), '""')
  expect_equal(format_value(NULL), "(none)")
  expect_equal(format_value(character()), "(empty)")
  expect_equal(format_value(c(NA, "")), 'NA, ""')
  expect_equal(format_value(1:4), "4 values")
  expect_equal(format_value(c("a", "b", "c")), "a, b, c")
  expect_equal(format_value(rep(strrep("a", 30), 2)), "2 values")
  expect_equal(format_value(strrep("a", 50)), paste0(strrep("a", 37), "..."))
  expect_equal(format_value(list(1, 2)), "a list of 2")
  expect_equal(format_value(data.frame(x = 1)), "a table of 1 row")
  expect_equal(format_value(data.frame(x = 1:2)), "a table of 2 rows")
  expect_equal(format_value(as.Date("2026-01-01")), "2026-01-01")
})

test_that("named tracker inputs validate and diff is reactive across save and pause", {
  session <- shiny::MockShinySession$new()
  on.exit(session$close())
  expect_error(unsaved_track(c(A = "name", B = "name"), session = session), "unique input ids")
  expect_error(unsaved_track(stats::setNames("name", NA_character_), session = session), "must not be NA")
  shiny::testServer(function(input, output, session) {
    tracker <- unsaved_track(c(Role = "role", "Full name" = "name", "raw"))
    changes <- shiny::reactive(tracker$diff())
  }, {
    session$setInputs(name = "Ada", role = "Designer", raw = "old",
                      unsaved_password_ids = list(ids = character()))
    expect_equal(nrow(changes()), 0L)
    session$setInputs(name = "Grace", role = "Developer", raw = "new")
    expect_equal(changes()$name, c("role", "name", "raw"))
    expect_equal(changes()$label, c("Role", "Full name", "raw"))
    tracker$pause()
    expect_equal(nrow(changes()), 3L)
    tracker$resume()
    expect_equal(nrow(changes()), 3L)
    tracker$mark_saved()
    expect_equal(nrow(changes()), 0L)
    session$setInputs(name = "Next")
    expect_equal(changes()$saved, list("Grace"))
  })
})

test_that("diff and tracking share a cached input snapshot", {
  shiny::testServer(function(input, output, session) {
    tracker <- unsaved_track("name")
    private <- tracker$.__enclos_env__$private
    original <- private$current
    calls <- new.env()
    calls$n <- 0L
    unlockBinding("current", private)
    private$current <- function() {
      calls$n <- calls$n + 1L
      original()
    }
    changes <- shiny::reactive(tracker$diff())
  }, {
    session$setInputs(name = "Ada")
    session$setInputs(name = "Grace")
    before <- calls$n
    expect_equal(changes()$current, list("Grace"))
    expect_equal(tracker$diff()$current, list("Grace"))
    expect_equal(calls$n, before)
    session$setInputs(name = "Next")
    expect_equal(changes()$current, list("Next"))
    expect_equal(calls$n, before + 1L)
    tracker$mark_saved()
    expect_equal(tracker$baseline(), list(name = "Next"))
    expect_equal(nrow(changes()), 0L)
  })
})
