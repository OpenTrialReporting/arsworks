# Development image for arsworks (5-package suite)
# Build: docker build -t arsworks:dev .
# Run:   docker run -it --rm -v $(pwd):/workspace arsworks:dev
#
# Strategy: Uses rocker/r-ubuntu (pre-compiled R packages) for fast builds
# CI/CD: GitHub Actions builds on x86, pushes to ghcr.io
# Deployment: rk3 pulls pre-built image (instant, no compilation)

FROM rocker/r-ubuntu:latest

LABEL maintainer="Lovemore Gakava <Lovemore.Gakava@gmail.com>"
LABEL description="arsworks: ARS Reporting Suite (arscore, arsshells, arsresult, arstlf, ars)"

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
    && rm -rf /var/lib/apt/lists/*

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
