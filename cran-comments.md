# CRAN comments

## Submission

This is a new submission. The package has not been on CRAN before.

## Test environments

* local Windows 11, R 4.6.1 (release): `R CMD check --as-cran` on the built
  tarball, with `_R_CHECK_CRAN_INCOMING_=TRUE`,
  `_R_CHECK_CRAN_INCOMING_REMOTE_=TRUE`, the PDF manual and pandoc. Run once
  without `NOT_CRAN` and once with it.
* local Windows 11, R 4.4.1, with Shiny 1.7.0: the full test suite, to
  confirm the minimum version of Shiny in DESCRIPTION.
* GitHub Actions, `R CMD check --as-cran`: macOS (release), Windows
  (release), Ubuntu (devel, release, oldrel-1)

The tarball was checked locally with the current release of R, not
R-devel, because this machine has only the release version. R-devel is
covered by the Ubuntu (devel) job above, which also runs
`R CMD check --as-cran`.

## R CMD check results

0 errors | 0 warnings | 1 note

* Maintainer: 'Tanmay Chanda <tanmaychanda96@gmail.com>'
  New submission

The only note is the standard note for a first submission.

## Notes for the reviewer

* The package tells a 'shiny' user which inputs they have changed and not
  saved, and asks before they leave with unsaved changes. Its R functions
  build HTML and keep state for one 'shiny' session. Its JavaScript runs in
  the browser of the user of a 'shiny' app.
* The package never saves data. The app saves, and tells the package when
  it has done so.
* The example of `unsaved_track()` runs only in an interactive session,
  because the function needs a running 'shiny' session. The examples of
  `unsaved_badge()`, `unsaved_dependency()`, `unsaved_guard()`,
  `unsaved_text()` and `unsaved_compare_text()` run.
* The tests that start an app in a headless browser use 'shinytest2'. They
  call `skip_on_cran()`, and they skip when Chrome or a suggested package is
  not available. On CRAN 33 tests skip for this reason; the other tests run.
* The package writes nothing outside `tempdir()`, opens no connections and
  starts no processes. Its JavaScript stores nothing in the browser.
