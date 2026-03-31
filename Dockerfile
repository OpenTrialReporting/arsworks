# Development image for arsworks (5-package suite)
# Build: docker build -t arsworks:dev .
# Run:   docker run -it --rm -v $(pwd):/workspace arsworks:dev
#
# Strategy: Uses rocker/r-ubuntu (pre-compiled R packages) for fast builds on ARM64
# CI/CD: GitHub Actions builds on x86, pushes to ghcr.io
# Deployment: rk3 pulls pre-built image (instant, no compilation)

FROM rocker/r-ubuntu:latest

LABEL maintainer="Lovemore Gakava <Lovemore.Gakava@gmail.com>"
LABEL description="arsworks: ARS Reporting Suite (arscore, arsshells, arsresult, arstlf, ars)"

# Install additional system dependencies
# (rocker/r-ubuntu already includes r-base, build-essential, gfortran, pandoc, etc.)
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    vim \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Install R package management tools
# (renv for version locking, devtools for package development, pkgdown for docs, shiny for optional apps)
RUN R --vanilla --quiet -e "install.packages(c('devtools', 'renv', 'pkgdown', 'shiny'), repos='https://cloud.r-project.org')"

# Set working directory
WORKDIR /workspace

# Copy project files
COPY . .

# Install all dependencies from renv.lock (exact versions)
RUN R --vanilla --quiet -e "renv::restore(upgrade = FALSE, clean = FALSE)"

# Create volume mount point for live development
VOLUME ["/workspace"]

# Default to R interactive shell
ENTRYPOINT ["R"]
