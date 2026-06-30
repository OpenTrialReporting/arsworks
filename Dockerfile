# Development / CI image for arsworks (6-package suite)
# Build: docker build -t arsworks:dev .
# Run:   docker run -it --rm -v $(pwd):/workspace arsworks:dev
# Test:  docker run --rm --entrypoint Rscript -v $(pwd):/workspace arsworks:dev run_tests.R
#
# Strategy: Uses rocker/r-ubuntu (pre-compiled R packages via r2u) for fast
# builds. CI/CD: GitHub Actions builds on x86, pushes to ghcr.io.
# Deployment: rk3 pulls pre-built image (instant, no compilation).

FROM rocker/r-ubuntu:latest

LABEL maintainer="Lovemore Gakava <Lovemore.Gakava@gmail.com>"
LABEL description="arsworks: ARS Reporting Suite (arscore, arsshells, arsresult, arstlf, ars, arsstudio)"

# Disable the renv autoloader inside the image. The project's renv setup targets
# R 4.6 with a host-specific lockfile; this CI image is whatever R rocker/r-ubuntu
# ships and uses the system/r2u library instead. Without this, renv/activate.R
# (pulled in by COPY . . and sourced from .Rprofile on every R startup in
# /workspace) activates an EMPTY project library, shadowing the packages
# installed below — which made R fail with "there is no package called 'devtools'".
# NOTE: the var must be one of the names activate.R actually checks
# (RENV_CONFIG_AUTOLOADER_ENABLED / RENV_AUTOLOADER_ENABLED / RENV_ACTIVATE_PROJECT);
# RENV_CONFIG_ACTIVATE_PROJECT is NOT one of them.
ENV RENV_CONFIG_AUTOLOADER_ENABLED=FALSE

# System libraries + a few R packages via r2u apt binaries (fast). r2u also
# pulls the matching system libraries (libcurl, libssl, libxml2, libgit2, ...)
# automatically as dependencies of their corresponding r-cran-* packages.
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    vim \
    curl \
    r-cran-devtools \
    r-cran-shiny \
    r-cran-pkgdown \
    r-cran-officer \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace

# Copy project files (including the six sub-package sources and their tracked
# NAMESPACE/DESCRIPTION) so dependencies can be resolved from DESCRIPTION.
COPY . .

# Install the suite's full dependency set, then the six sub-packages themselves
# in dependency order (arscore -> ... -> arsstudio) so each package's local
# Imports are already present when the next one installs. We deliberately do NOT
# override `repos`: the base image preconfigures r2u, so install.packages()
# resolves dependencies to apt/r2u binaries (via bspm) instead of compiling from
# source. Packages absent from r2u (e.g. cards, webshot2) fall back to source,
# but both are NeedsCompilation=no so that is cheap. Suggests are included so
# testthat and friends are available for `run_tests.R`.
RUN Rscript -e 'pkgs <- c("arscore","arsshells","arsresult","arstlf","ars","arsstudio"); \
      for (p in pkgs) devtools::install(p, dependencies = TRUE, upgrade = "never", quick = TRUE)'

# NOTE: webshot2 (an arsstudio dep, installed above) provides the R interface
# only. Rendering gt/Shiny output to images at runtime additionally requires a
# headless Chrome (driven via the chromote package). It is intentionally NOT
# installed here to keep the image lean — add a `google-chrome-stable`/
# `chromium` apt package if arsstudio's screenshot paths need to run in-container.

# Verify all six packages import cleanly from the system library.
RUN Rscript -e 'for (p in c("arscore","arsshells","arsresult","arstlf","ars","arsstudio")) { \
      suppressPackageStartupMessages(library(p, character.only = TRUE)); cat("loaded", p, "\n") }'

# Create volume mount point for live development
VOLUME ["/workspace"]

# Default to R interactive shell
ENTRYPOINT ["R"]
