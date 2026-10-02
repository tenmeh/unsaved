# CRAN comments

## Submission

This is a new submission. The package has not been on CRAN before.

## Test environments

* PLACEHOLDER: local Windows, R version and tarball check results.
* PLACEHOLDER: GitHub Actions macOS (release), Windows (release),
  Ubuntu (devel, release, oldrel-1), after CI runs.

## R CMD check results

PLACEHOLDER: errors, warnings and notes from the submission tarball.
The standard "New submission" note is expected for a first submission.
Record any other note here and explain it before submitting.

## Notes for the reviewer

* The package marks changed Shiny inputs and guards tab navigation.
  Applications save their own data.
* Session examples run only in an interactive R session.
* Browser tests use shinytest2 and skip on CRAN.
* The showcase stores records in memory for the current session only.
