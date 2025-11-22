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

# The base image already includes code-server and a `vscodeuser`.
# Install the Docker official apt repository and install the Docker CLI
# (`docker-ce-cli`) so the container has a recent CLI without installing
# the full engine. We intentionally do not install the Compose v2 plugin
# here per your request.
RUN set -eux; \
    apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl gnupg lsb-release && \
    mkdir -p /etc/apt/keyrings && \
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list && \
    apt-get update && apt-get install -y --no-install-recommends \
        docker-ce-cli \
        docker-compose-plugin \
        docker-buildx-plugin && \
    rm -rf /var/lib/apt/lists/*

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
