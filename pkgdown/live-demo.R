# Build the live demo of the pkgdown site with shinylive.
#
# Run from the root of the package, after the site is built:
#
#   Rscript pkgdown/live-demo.R [site directory]
#
# The site directory is "docs" if you do not give one. The demo goes in
# <site>/demo, and the "Live demo" article shows it in an iframe.
#
# Shinylive runs the app in webR, R in the browser. webR installs packages
# only from a repository of WebAssembly builds, and unsaved is not in the
# default one. But unsaved is pure R: it has no compiled code. So an
# installed copy of unsaved goes into the app itself, and the app adds it to
# its library paths. The demo thus always uses the unsaved of this commit.
# The other packages come from the webR repository.
#
# Only shiny and bslib are bundled from the webR repository. The installed
# unsaved package lives in vendor/lib and uses these runtime dependencies.
# R6 and htmltools are dependencies of shiny and are available in webR.
# Set UNSAVED_LIVE_PACKAGES (comma-separated) to try another list.
#
# shinylive finds the packages to bundle with renv::dependencies(), which
# reads the code of the app for library() and pkg:: calls. It does this
# twice: here, to bundle them, and in the browser, where it downloads each
# one that is missing. renv never reads a folder named "vendor". So the demo
# and unsaved go in vendor/, the three files at the top only source them, and
# live-packages.R names the packages to bundle.
#
#   app/
#     global.R, ui.R, server.R   source the files in vendor/demo
#     live-packages.R            library() calls, for renv to read
#     vendor/demo/               a copy of inst/examples/demo
#     vendor/lib/unsaved/          unsaved, installed from this commit

live_packages <- strsplit(Sys.getenv("UNSAVED_LIVE_PACKAGES", "shiny,bslib"), ",")[[1]]

args <- commandArgs(trailingOnly = TRUE)
site <- if (length(args) >= 1L) args[[1]] else "docs"
if (!dir.exists(site)) {
  stop("The site directory `", site, "` does not exist. Build the site first.", call. = FALSE)
}

# --- The demo and unsaved, in vendor/ -------------------------------------------

app <- file.path(tempfile("unsaved-demo-"), "app")
demo <- file.path(app, "vendor", "demo")
lib <- file.path(app, "vendor", "lib")
dir.create(demo, recursive = TRUE)
dir.create(lib, recursive = TRUE)
invisible(file.copy(list.files("inst/examples/demo", full.names = TRUE), demo))

# --no-test-load: the check that the package loads runs in a new R, which
# does not know this library path yet. The build of the site has loaded
# unsaved already.
status <- system2(
  file.path(R.home("bin"), "R"),
  c("CMD", "INSTALL", "--no-docs", "--no-multiarch", "--no-test-load",
    paste0("--library=", shQuote(lib)), ".")
)
if (status != 0L || !file.exists(file.path(lib, "unsaved", "DESCRIPTION"))) {
  stop("R CMD INSTALL of unsaved into the demo failed.", call. = FALSE)
}

# --- The files at the top of the app ------------------------------------------

writeLines(c(
  "# Live demo. The demo is in vendor/demo, and unsaved is in vendor/lib.",
  "# See pkgdown/live-demo.R in the source of unsaved.",
  ".libPaths(c(normalizePath(\"vendor/lib\"), .libPaths()))",
  "source(\"vendor/demo/global.R\")"
), file.path(app, "global.R"))

# Shiny takes the value of ui.R and server.R: here, the value of the file
# that each one sources.
writeLines("source(\"vendor/demo/ui.R\", local = TRUE)$value", file.path(app, "ui.R"))
writeLines("source(\"vendor/demo/server.R\", local = TRUE)$value", file.path(app, "server.R"))

writeLines(c(
  "# The packages that shinylive bundles for the live demo. This file is not",
  "# run: renv::dependencies() only reads it.",
  sprintf("library(%s)", live_packages)
), file.path(app, "live-packages.R"))

# --- Export -------------------------------------------------------------------

out <- file.path(site, "demo")
unlink(out, recursive = TRUE)
shinylive::export(app, out, quiet = TRUE)
message("Live demo written to: ", out)
