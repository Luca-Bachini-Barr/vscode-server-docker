FROM ghcr.io/nerasse/my-code-server:main

# Run as root to install packages and add entrypoint
USER root

# Install docker client and small utilities
RUN apt-get update && apt-get install -y --no-install-recommends \
    docker.io \
    docker-cli \
    curl \
    passwd \
    && rm -rf /var/lib/apt/lists/*

# Install Docker Compose v2 plugin binary for linux aarch64 so `docker compose` works
RUN mkdir -p /usr/local/lib/docker/cli-plugins && \
    curl -fsSL -o /usr/local/lib/docker/cli-plugins/docker-compose \
      https://github.com/docker/compose/releases/download/v2.20.2/docker-compose-linux-aarch64 && \
    chmod +x /usr/local/lib/docker/cli-plugins/docker-compose || true

# Provide compatibility shim so legacy `docker-compose` calls forward to `docker compose`
RUN printf '#!/bin/sh\nexec docker compose "$@"' > /usr/local/bin/docker-compose \
    && chmod +x /usr/local/bin/docker-compose
RUN ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose || true

# Copy our entrypoint which will create user/group and then exec the original CMD
COPY entrypoint.sh /usr/local/bin/vscode-entrypoint.sh
RUN chmod +x /usr/local/bin/vscode-entrypoint.sh

# Add default user settings and install Docker extension at build-time so the
# remote (container) environment is ready and the extension runs inside the
# container rather than relying on first-boot runtime installation.
COPY settings.json /tmp/code-server-settings.json
RUN mkdir -p /home/vscodeuser/.local/share/code-server/User \
    && mv /tmp/code-server-settings.json /home/vscodeuser/.local/share/code-server/User/settings.json \
    && chown -R vscodeuser:vscodeuser /home/vscodeuser/.local/share/code-server || true

# Install the Docker extension for the default user at build time. If the
# `code` CLI is present and the user exists, install as that user so the
# extension is available immediately inside the image.
RUN if command -v /usr/bin/code >/dev/null 2>&1; then \
      su - vscodeuser -s /bin/bash -c "/usr/bin/code --install-extension ms-azuretools.vscode-docker" || true; \
    fi

ENTRYPOINT ["/usr/local/bin/vscode-entrypoint.sh"]
# keep the base image CMD
