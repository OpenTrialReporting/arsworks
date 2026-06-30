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

# Minimal system tooling. r2u/bspm pulls each R package's system libraries
# (libcurl, libssl, libxml2, libgit2, ...) automatically when install_suite.R
# installs the corresponding r-cran-* binaries below.
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace

# Copy project files (including the six sub-package sources and their tracked
# NAMESPACE/DESCRIPTION) so dependencies can be resolved from DESCRIPTION.
COPY . .

# Install the suite: CRAN dependencies as r2u binaries (install.packages is
# bridged to apt by bspm), then the six local packages from source in dependency
# order. install_suite.R deliberately avoids devtools::install for the dep tree,
# which would bypass bspm and compile everything from source. Also verifies all
# six load before the image is considered built.
RUN Rscript install_suite.R

# Create volume mount point for live development
VOLUME ["/workspace"]

# Default to R interactive shell
ENTRYPOINT ["R"]
