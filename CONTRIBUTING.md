# Contributing

Use a small reproducible example when reporting a bug. Use fictional data.

Run these commands from the package root with the test dependencies in
`.library`. The source-only check does not install the package:

```sh
Rscript verification/verify.R --source-only
Rscript verification/lint.R
Rscript verification/gates.R --anchors-only
```

For the full suite, run `Rscript verification/verify.R`. This installs the
package into `.library` and runs browser tests. Browser tests need Chrome
and shinytest2. Set `CHROMOTE_CHROME` to the Chrome executable if needed.

Use the base pipe `|>`, British English and ASCII text. Keep changes small.
Regenerate help with `roxygen2::roxygenise(".")` after editing roxygen comments.
