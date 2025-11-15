FROM debian:bookworm-slim

# Build-time arguments
ARG DEBIAN_FRONTEND=noninteractive
ARG CODE_SERVER_VERSION=

ENV HOME=/home/vscodeuser

# Run as root for installation steps
USER root

# Install runtime dependencies and helpers
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    gnupg \
    dumb-init \
    passwd \
    tar \
    xz-utils \
    ca-certificates \
    wget \
    procps \
    jq \
    && rm -rf /var/lib/apt/lists/*

# Install code-server via the official install script (standalone). If
# CODE_SERVER_VERSION is empty, the installer will fetch the latest release.
RUN curl -fsSL https://code-server.dev/install.sh | sh -s -- --method=standalone ${CODE_SERVER_VERSION:+--version $CODE_SERVER_VERSION}

# Create a non-root user matching typical setups
RUN useradd -m -s /bin/bash vscodeuser || true

# Install Docker CLI (docker.io) and small utilities
RUN apt-get update && apt-get install -y --no-install-recommends \
    docker.io \
    docker-cli \
    && rm -rf /var/lib/apt/lists/*

# Install Docker Compose v2 plugin (binary) so `docker compose` works inside container.
# Detect arch and fetch appropriate binary.
RUN set -eux; \
    ARCH=$(uname -m); \
    PLUGIN_DIR=/usr/local/lib/docker/cli-plugins; \
    mkdir -p "$PLUGIN_DIR"; \
    case "$ARCH" in \
      x86_64|amd64) BINNAME=docker-compose-linux-x86_64 ;; \
      aarch64|arm64) BINNAME=docker-compose-linux-aarch64 ;; \
      *) BINNAME=docker-compose-linux-x86_64 ;; \
    esac; \
    curl -fsSL -o "$PLUGIN_DIR/docker-compose" "https://github.com/docker/compose/releases/download/v2.20.2/$BINNAME"; \
    chmod +x "$PLUGIN_DIR/docker-compose" || true

# Provide compatibility shim for legacy `docker-compose` CLI calls
RUN printf '#!/bin/sh\nexec docker compose "$@"' > /usr/local/bin/docker-compose \
    && chmod +x /usr/local/bin/docker-compose \
    && ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose || true

# Copy entrypoint which handles UID/GID mapping and docker socket group
COPY entrypoint.sh /usr/local/bin/vscode-entrypoint.sh
RUN chmod +x /usr/local/bin/vscode-entrypoint.sh

# Copy default settings and install extensions at build-time so the
# remote environment is ready immediately.
COPY settings.json /tmp/code-server-settings.json
RUN mkdir -p /home/vscodeuser/.local/share/code-server/User \
    && mv /tmp/code-server-settings.json /home/vscodeuser/.local/share/code-server/User/settings.json \
    && chown -R vscodeuser:vscodeuser /home/vscodeuser/.local/share/code-server || true

# Install Docker extensions for code-server at build time if `code` CLI exists
RUN if command -v /usr/bin/code >/dev/null 2>&1; then \
      su - vscodeuser -s /bin/bash -c "/usr/bin/code --install-extension ms-azuretools.vscode-docker" || true; \
      su - vscodeuser -s /bin/bash -c "/usr/bin/code --install-extension ms-azuretools.vscode-containers" || true; \
    fi

ENTRYPOINT ["/usr/local/bin/vscode-entrypoint.sh"]
CMD ["/usr/bin/code", "serve-web", "--host", "0.0.0.0", "--port", "8585", "--accept-server-license-terms"]
