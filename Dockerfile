# Development image for arsworks (6-package suite)
# Build: docker build -t arsworks:dev .
# Run:   docker run -it --rm -v $(pwd):/workspace arsworks:dev
#
# Strategy: Uses rocker/r-ubuntu (pre-compiled R packages) for fast builds
# CI/CD: GitHub Actions builds on x86, pushes to ghcr.io
# Deployment: rk3 pulls pre-built image (instant, no compilation)

FROM rocker/r-ubuntu:latest

LABEL maintainer="Lovemore Gakava <Lovemore.Gakava@gmail.com>"
LABEL description="arsworks: ARS Reporting Suite (arscore, arsshells, arsresult, arstlf, ars, arsstudio)"

# Install system dependencies AND R packages via r2u (pre-compiled binaries).
# rocker/r-ubuntu ships with r2u preconfigured, so r-cran-* packages install
# from apt in seconds rather than compiling from source. This also pulls in
# system libraries (libcurl, libssl, libxml2, libgit2, etc.) automatically as
# dependencies of their corresponding R packages.
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    vim \
    curl \
    r-cran-devtools \
    r-cran-shiny \
    r-cran-pkgdown \
    r-cran-officer \
    && rm -rf /var/lib/apt/lists/*

# arsstudio also needs cards + webshot2, which are NOT in the r2u/apt set for
# this base image (only officer is). Install them via R: dependencies resolve
# to apt/r2u binaries where available and the two leaf packages build from
# source (both NeedsCompilation=no, so this is cheap on Linux/gcc — no compiler
# trouble here, unlike the host toolchain).
RUN Rscript -e 'options(repos = c(CRAN = "https://cloud.r-project.org")); install.packages(c("cards", "webshot2"))'

# NOTE: webshot2 provides the R interface only. Rendering gt/Shiny output to
# images at runtime additionally requires a headless Chrome (driven via the
# chromote package). It is intentionally NOT installed here to keep the image
# lean — add a `google-chrome-stable`/`chromium` apt package if arsstudio's
# screenshot paths need to execute in-container (e.g. snapshot tests).

# Set working directory
WORKDIR /workspace

# Copy project files
COPY . .

# Optional: Load all packages to verify installation
RUN R --vanilla --quiet -e "library(devtools); message('arsworks container ready')"

# Create volume mount point for live development
VOLUME ["/workspace"]

# Default to R interactive shell
ENTRYPOINT ["R"]
