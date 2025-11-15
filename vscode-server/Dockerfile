FROM ghcr.io/nerasse/my-code-server:main

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
    git \
    && rm -rf /var/lib/apt/lists/*

# The base image already includes code-server and a `vscodeuser`. We only
# need to install Docker client and helpers in the image.
RUN apt-get update && apt-get install -y --no-install-recommends \
    docker.io \
    && rm -rf /var/lib/apt/lists/*

# Ensure a `docker` CLI binary exists (some base images provide dockerd but
# not the client). Download the Docker static CLI for the detected arch and
# install it to /usr/local/bin/docker so extensions that invoke the CLI work.
RUN set -eux; \
        ARCH=$(uname -m); \
        case "$ARCH" in \
            x86_64|amd64) DLARCH="x86_64" ;; \
            aarch64|arm64) DLARCH="aarch64" ;; \
            *) DLARCH="x86_64" ;; \
        esac; \
        DOCKER_CLI_VER="24.0.6"; \
        TGT="/tmp/docker-cli.tgz"; \
        curl -fsSL -o "$TGT" "https://download.docker.com/linux/static/stable/$DLARCH/docker-$DOCKER_CLI_VER.tgz" || true; \
        if [ -s "$TGT" ]; then \
            tar -xzf "$TGT" -C /tmp; \
            cp -f /tmp/docker/docker /usr/local/bin/docker || true; \
            chmod +x /usr/local/bin/docker || true; \
            rm -rf /tmp/docker* || true; \
        fi

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

# The base image provides `code` at `/usr/bin/code`. We will detect `code`
# at runtime during build-time extension installs below.

# Install extensions into a stable /opt extensions dir so host mounts over
# `/home` won't hide them. We install common Docker and Copilot extensions
# that the nerasse image included.
RUN mkdir -p /opt/code-server-extensions \
    && touch /opt/code-server-extensions/extensions.json \
    && chown -R vscodeuser:vscodeuser /opt/code-server-extensions || true

# Ensure the vscodeuser home is writable so the code CLI can create config
# during extension installation (it may still write to ~/.config even when
# installing into a separate extensions dir).
RUN mkdir -p /home/vscodeuser/.config && chown -R vscodeuser:vscodeuser /home/vscodeuser || true

RUN if command -v code >/dev/null 2>&1; then \
            CODE_BIN=$(command -v code); \
            EXT_DIR=/opt/code-server-extensions; \
            su - vscodeuser -s /bin/bash -c "$CODE_BIN --extensions-dir $EXT_DIR --install-extension ms-azuretools.vscode-docker" || true; \
            su - vscodeuser -s /bin/bash -c "$CODE_BIN --extensions-dir $EXT_DIR --install-extension ms-azuretools.vscode-containers" || true; \
            su - vscodeuser -s /bin/bash -c "$CODE_BIN --extensions-dir $EXT_DIR --install-extension GitHub.copilot" || true; \
            su - vscodeuser -s /bin/bash -c "$CODE_BIN --extensions-dir $EXT_DIR --install-extension GitHub.copilot-chat" || true; \
            su - vscodeuser -s /bin/bash -c "$CODE_BIN --extensions-dir $EXT_DIR --install-extension ms-vscode-remote.remote-containers" || true; \
            chown -R vscodeuser:vscodeuser $EXT_DIR || true; \
        fi

# For nerasse-based images, the server expects extensions under
# /home/vscodeuser/.vscode/extensions. Mirror installed extensions
# there so serve-web (code-tunnel) will load them.
RUN mkdir -p /home/vscodeuser/.vscode/extensions || true; \
    cp -a /opt/code-server-extensions/* /home/vscodeuser/.vscode/extensions/ 2>/dev/null || true; \
    chown -R vscodeuser:vscodeuser /home/vscodeuser/.vscode/extensions || true

ENTRYPOINT ["/usr/local/bin/vscode-entrypoint.sh"]
CMD ["/usr/bin/code", "serve-web", "--host", "0.0.0.0", "--port", "8585", "--accept-server-license-terms"]
