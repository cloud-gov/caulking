# Dockerfile for local Linux testing
# Usage: docker compose run --rm test
#        docker compose run --rm full
#        docker compose run --rm fresh-install
#
# Multi-stage build for different test scenarios

# =============================================================================
# Base image with common dependencies
# =============================================================================
FROM ubuntu:24.04 AS base-ubuntu

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    git \
    curl \
    wget \
    ca-certificates \
    make \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user for realistic testing
RUN useradd -m -s /bin/bash tester \
    && mkdir -p /home/tester/.config \
    && chown -R tester:tester /home/tester

# =============================================================================
# Ubuntu with gitleaks pre-installed (for quick tests)
# =============================================================================
FROM base-ubuntu AS ubuntu-with-gitleaks

ARG GITLEAKS_VERSION=8.30.1
RUN ARCH="$(dpkg --print-architecture)" && \
    case "$ARCH" in \
      amd64) GITLEAKS_ARCH="x64" ;; \
      arm64) GITLEAKS_ARCH="arm64" ;; \
      *) echo "Unsupported architecture: $ARCH" && exit 1 ;; \
    esac && \
    wget --no-check-certificate -q -O /tmp/gitleaks.tar.gz \
      "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_${GITLEAKS_ARCH}.tar.gz" && \
    tar xzf /tmp/gitleaks.tar.gz -C /usr/local/bin gitleaks && \
    rm /tmp/gitleaks.tar.gz && \
    chmod +x /usr/local/bin/gitleaks && \
    gitleaks version

WORKDIR /caulking
COPY --chown=tester:tester . .
USER tester

RUN git config --global user.name "Caulking Test" \
    && git config --global user.email "test@gsa.gov" \
    && git config --global init.defaultBranch main

CMD ["make", "test"]

# =============================================================================
# Fresh install test (no gitleaks pre-installed, simulates new user)
# =============================================================================
FROM base-ubuntu AS fresh-install

WORKDIR /caulking
COPY --chown=tester:tester . .
USER tester

RUN git config --global user.name "Caulking Test" \
    && git config --global user.email "test@gsa.gov" \
    && git config --global init.defaultBranch main

# Fresh install will fail without gitleaks - tests the error messaging
CMD ["bash", "-c", "echo '=== Fresh Install Test (no gitleaks) ===' && make install 2>&1; echo 'Exit code:' $?"]

# =============================================================================
# Debian testing
# =============================================================================
FROM debian:12-slim AS debian

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    git \
    curl \
    wget \
    ca-certificates \
    make \
    && rm -rf /var/lib/apt/lists/*

RUN useradd -m -s /bin/bash tester \
    && mkdir -p /home/tester/.config \
    && chown -R tester:tester /home/tester

ARG GITLEAKS_VERSION=8.30.1
RUN ARCH="$(dpkg --print-architecture)" && \
    case "$ARCH" in \
      amd64) GITLEAKS_ARCH="x64" ;; \
      arm64) GITLEAKS_ARCH="arm64" ;; \
      *) echo "Unsupported architecture: $ARCH" && exit 1 ;; \
    esac && \
    wget --no-check-certificate -q -O /tmp/gitleaks.tar.gz \
      "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_${GITLEAKS_ARCH}.tar.gz" && \
    tar xzf /tmp/gitleaks.tar.gz -C /usr/local/bin gitleaks && \
    rm /tmp/gitleaks.tar.gz && \
    chmod +x /usr/local/bin/gitleaks

WORKDIR /caulking
COPY --chown=tester:tester . .
USER tester

RUN git config --global user.name "Caulking Test" \
    && git config --global user.email "test@gsa.gov" \
    && git config --global init.defaultBranch main

CMD ["make", "test"]

# =============================================================================
# Alpine Linux (musl libc - good for catching glibc assumptions)
# =============================================================================
FROM alpine:3.20 AS alpine

RUN apk add --no-cache \
    bash \
    git \
    curl \
    wget \
    make \
    ca-certificates

RUN adduser -D -s /bin/bash tester \
    && mkdir -p /home/tester/.config \
    && chown -R tester:tester /home/tester

# Note: gitleaks provides musl builds
ARG GITLEAKS_VERSION=8.30.1
# Update CA certs and download gitleaks
RUN update-ca-certificates && \
    ARCH="$(uname -m)" && \
    case "$ARCH" in \
      x86_64) GITLEAKS_ARCH="x64" ;; \
      aarch64) GITLEAKS_ARCH="arm64" ;; \
      *) echo "Unsupported architecture: $ARCH" && exit 1 ;; \
    esac && \
    wget --no-check-certificate -q -O /tmp/gitleaks.tar.gz \
      "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_${GITLEAKS_ARCH}.tar.gz" && \
    tar xzf /tmp/gitleaks.tar.gz -C /usr/local/bin gitleaks && \
    rm /tmp/gitleaks.tar.gz && \
    chmod +x /usr/local/bin/gitleaks

WORKDIR /caulking
COPY --chown=tester:tester . .
USER tester

RUN git config --global user.name "Caulking Test" \
    && git config --global user.email "test@gsa.gov" \
    && git config --global init.defaultBranch main

CMD ["make", "test"]

# =============================================================================
# GitHub Actions CI simulation (ubuntu-latest equivalent)
# =============================================================================
FROM ubuntu:22.04 AS ci-simulation

ENV DEBIAN_FRONTEND=noninteractive
ENV CI=true
ENV GITHUB_ACTIONS=true
ENV RUNNER_OS=Linux

# Match GitHub Actions runner packages
RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    git \
    curl \
    wget \
    ca-certificates \
    make \
    jq \
    && rm -rf /var/lib/apt/lists/*

RUN useradd -m -s /bin/bash runner \
    && mkdir -p /home/runner/.config \
    && chown -R runner:runner /home/runner

ARG GITLEAKS_VERSION=8.30.1
ARG GITLEAKS_SHA256_LINUX_X64=551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb
# Use wget with --no-check-certificate for Docker build environments with SSL proxy issues
RUN ARCH="$(dpkg --print-architecture)" && \
    case "$ARCH" in \
      amd64) GITLEAKS_ARCH="x64" ;; \
      arm64) GITLEAKS_ARCH="arm64" ;; \
      *) echo "Unsupported architecture: $ARCH" && exit 1 ;; \
    esac && \
    wget --no-check-certificate -q -O /tmp/gitleaks.tar.gz \
      "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_${GITLEAKS_ARCH}.tar.gz" && \
    if [ "$ARCH" = "amd64" ]; then \
      echo "${GITLEAKS_SHA256_LINUX_X64}  /tmp/gitleaks.tar.gz" | sha256sum -c - ; \
    fi && \
    tar xzf /tmp/gitleaks.tar.gz -C /usr/local/bin gitleaks && \
    rm /tmp/gitleaks.tar.gz && \
    chmod +x /usr/local/bin/gitleaks

WORKDIR /github/workspace
COPY --chown=runner:runner . .
USER runner

RUN git config --global user.name "GitHub Actions" \
    && git config --global user.email "actions@github.com" \
    && git config --global init.defaultBranch main

# Simulate the CI workflow steps
CMD ["bash", "-c", "set -euo pipefail && echo '=== CI Simulation ===' && echo 'Step 1: Install' && make install && echo 'Step 2: Verify' && make verify && echo 'Step 3: Test' && make test && echo '=== CI Simulation PASSED ==='"]

# =============================================================================
# Default target (ubuntu with gitleaks)
# =============================================================================
FROM ubuntu-with-gitleaks AS default
