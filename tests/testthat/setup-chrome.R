# All AppDrivers share one headless Chrome, and nothing closes it. When R
# exits, Chrome's main process is killed, but on Windows its child
# processes (crashpad, utility services) can outlive it. They keep handles
# that R inherited, so R CMD check waits for them until the CI job times
# out. Closing the browser at the end of the run lets Chrome stop its own
# children.
withr::defer(
  {
    has_chrome <- requireNamespace("chromote", quietly = TRUE) &&
      chromote::has_default_chromote_object()
    if (has_chrome) {
      try(chromote::default_chromote_object()$close(), silent = TRUE)
    }
  },
  envir = testthat::teardown_env()
)
