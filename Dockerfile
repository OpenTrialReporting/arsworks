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

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    vim \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Install R packages directly (bypass renv to avoid restoration issues in CI/CD)
# These are the core packages needed for arsworks development
RUN R --vanilla --quiet -e "install.packages(c('devtools', 'shiny', 'pkgdown'), repos='https://cloud.r-project.org')"

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
