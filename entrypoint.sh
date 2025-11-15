#!/usr/bin/env bash
set -euo pipefail

# Entrypoint: mirror upstream UID/GID handling for 'vscodeuser', then ensure docker socket
# supplementary group membership and finally start code-server as the runtime user.

USERNAME="vscodeuser"

# Get current UID/GID from image
CURRENT_UID=$(id -u "$USERNAME")
CURRENT_GID=$(id -g "$USERNAME")

# Target values come from env or default to current
TARGET_UID=${PUID:-$CURRENT_UID}
TARGET_GID=${PGID:-$CURRENT_GID}

if [ "$CURRENT_UID" != "$TARGET_UID" ] || [ "$CURRENT_GID" != "$TARGET_GID" ]; then
  echo "Changing $USERNAME UID:GID from $CURRENT_UID:$CURRENT_GID to $TARGET_UID:$TARGET_GID"

  # Remove conflicting user if UID already taken by another account
  EXISTING_USER=$(getent passwd "$TARGET_UID" | cut -d: -f1 || true)
  if [ -n "$EXISTING_USER" ] && [ "$EXISTING_USER" != "$USERNAME" ]; then
    echo "WARNING: UID $TARGET_UID already exists for user '$EXISTING_USER'"
    echo "Removing conflicting user '$EXISTING_USER'"
    userdel "$EXISTING_USER" || true
  fi

  # If GID exists for another group, reuse it; otherwise adjust groupid
  EXISTING_GROUP=$(getent group "$TARGET_GID" | cut -d: -f1 || true)
  if [ -n "$EXISTING_GROUP" ] && [ "$EXISTING_GROUP" != "$USERNAME" ]; then
    echo "GID $TARGET_GID already exists as group '$EXISTING_GROUP', using it"
    usermod -u "$TARGET_UID" -g "$TARGET_GID" "$USERNAME" || true
  else
    if [ "$CURRENT_GID" != "$TARGET_GID" ]; then
      groupmod -g "$TARGET_GID" "$USERNAME" || true
    fi
    if [ "$CURRENT_UID" != "$TARGET_UID" ]; then
      usermod -u "$TARGET_UID" "$USERNAME" || true
    fi
  fi

  chown -R "$TARGET_UID":"$TARGET_GID" "/home/$USERNAME" || true
  echo "UID/GID changed successfully to $(id -u "$USERNAME"):$(id -g "$USERNAME")"
else
  echo "Using default UID:GID $CURRENT_UID:$CURRENT_GID"
fi

# If docker socket present, ensure group for its GID exists and add runtime user to it
if [[ -S /var/run/docker.sock ]]; then
  DOCKER_GID=$(stat -c '%g' /var/run/docker.sock || true)
  if [[ -n "$DOCKER_GID" ]]; then
    DOCKER_GNAME=$(getent group "$DOCKER_GID" | cut -d: -f1 || true)
    if [[ -z "$DOCKER_GNAME" ]]; then
      DOCKER_GNAME="docker_${DOCKER_GID}"
      groupadd -g "$DOCKER_GID" "$DOCKER_GNAME" || true
    fi
    usermod -aG "$DOCKER_GNAME" "$USERNAME" || true
  fi
fi

# Fix ownership of common mounts
for d in "/home/$USERNAME" /config /home; do
  if [[ -d "$d" ]]; then
    chown -R "$(id -u "$USERNAME")":"$(id -g "$USERNAME")" "$d" || true
  fi
done

# Docker extension is installed at image build time; runtime installation
# is no longer required. Keep this block removed to avoid first-boot
# network/install activity and to ensure deterministic container start.

# Build the same CMD as upstream start.sh
if [ -z "${PORT:-}" ]; then
  PORT=8585
fi
if [ -z "${HOST:-}" ]; then
  HOST=0.0.0.0
fi

CMD="code serve-web --host $HOST --port $PORT"
if [ -n "${SERVER_DATA_DIR:-}" ]; then
  CMD="$CMD --server-data-dir $SERVER_DATA_DIR"
fi
if [ -n "${SERVER_BASE_PATH:-}" ]; then
  CMD="$CMD --server-base-path $SERVER_BASE_PATH"
fi
if [ -n "${SOCKET_PATH:-}" ]; then
  CMD="$CMD --socket-path $SOCKET_PATH"
fi
if [ -z "${TOKEN:-}" ]; then
  CMD="$CMD --without-connection-token"
else
  CMD="$CMD --connection-token $TOKEN"
fi
if [ -n "${TOKEN_FILE:-}" ]; then
  CMD="$CMD --connection-token-file $TOKEN_FILE"
fi
CMD="$CMD --accept-server-license-terms"
if [ -n "${VERBOSE:-}" ] && [ "$VERBOSE" = "true" ]; then
  CMD="$CMD --verbose"
fi
if [ -n "${LOG_LEVEL:-}" ]; then
  CMD="$CMD --log $LOG_LEVEL"
fi
if [ -n "${CLI_DATA_DIR:-}" ]; then
  CMD="$CMD --cli-data-dir $CLI_DATA_DIR"
fi

echo "Executing: $CMD (as $USERNAME)"
exec su - "$USERNAME" -c "$CMD"
