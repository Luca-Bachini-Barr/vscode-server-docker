#!/usr/bin/env bash
set -euo pipefail

USERNAME="vscodeuser"

# --- UID/GID handling (allow overriding with PUID/PGID) ---
CURRENT_UID=$(id -u "$USERNAME")
CURRENT_GID=$(id -g "$USERNAME")
TARGET_UID=${PUID:-$CURRENT_UID}
TARGET_GID=${PGID:-$CURRENT_GID}

if [ "$CURRENT_UID" != "$TARGET_UID" ] || [ "$CURRENT_GID" != "$TARGET_GID" ]; then
  echo "Changing $USERNAME UID:GID from $CURRENT_UID:$CURRENT_GID to $TARGET_UID:$TARGET_GID"

  EXISTING_USER=$(getent passwd "$TARGET_UID" | cut -d: -f1 || true)
  if [ -n "$EXISTING_USER" ] && [ "$EXISTING_USER" != "$USERNAME" ]; then
    echo "WARNING: UID $TARGET_UID already exists for user '$EXISTING_USER' - removing it"
    userdel "$EXISTING_USER" || true
  fi

  EXISTING_GROUP=$(getent group "$TARGET_GID" | cut -d: -f1 || true)
  if [ -n "$EXISTING_GROUP" ] && [ "$EXISTING_GROUP" != "$USERNAME" ]; then
    echo "GID $TARGET_GID exists as group '$EXISTING_GROUP', attempting to reuse it"
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

# --- Docker socket group handling ---
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

# --- Mirror build-time preinstalled extensions into user's extensions dir ---
PREINSTALLED_DIR=/opt/preinstalled-extensions
USER_EXT_DIR="/home/$USERNAME/.vscode/extensions"

if [ -d "$PREINSTALLED_DIR" ]; then
  echo "Found preinstalled extensions in $PREINSTALLED_DIR - ensuring available to $USERNAME"
  mkdir -p "$USER_EXT_DIR"
  chown -R "$TARGET_UID":"$TARGET_GID" "/home/$USERNAME/.vscode" || true
  # Copy missing extension folders only
  for ext in "$PREINSTALLED_DIR"/*; do
    [ -e "$ext" ] || continue
    name=$(basename "$ext")
    if [ ! -e "$USER_EXT_DIR/$name" ]; then
      echo "Installing preinstalled extension: $name"
      cp -a "$ext" "$USER_EXT_DIR/" || true
      chown -R "$TARGET_UID":"$TARGET_GID" "$USER_EXT_DIR/$name" || true
    fi
  done
fi

# --- Runtime installation from EXTENSIONS env (comma or space separated list) ---
wait_for_code_cli() {
  local retries=${1:-12}
  local delay=${2:-5}
  echo "Waiting for 'code' CLI to be ready (up to $((retries*delay))s)..."
  for i in $(seq 1 $retries); do
    if su - "$USERNAME" -c "code --list-extensions" >/dev/null 2>&1; then
      echo "'code' CLI is available"
      return 0
    fi
    echo "'code' not ready yet ($i/$retries), sleeping $delay s"
    sleep $delay
  done
  echo "Timeout waiting for 'code' CLI"
  return 1
}

install_with_retries() {
  local ext="$1"
  local retries=${2:-6}
  local delay=${3:-5}
  for i in $(seq 1 $retries); do
    echo "Attempting to install $ext (try $i/$retries)"
    if su - "$USERNAME" -c "code --install-extension $ext"; then
      echo "Successfully installed $ext"
      return 0
    fi
    echo "Install attempt $i for $ext failed; sleeping $delay s"
    sleep $delay
  done
  echo "Failed to install $ext after $retries attempts"
  return 1
}

# Runtime extension installs are performed after the server starts (see below)

# --- Build the code serve-web command (nerasse compatibility) ---
if [ -z "${PORT:-}" ]; then
  PORT=8585
  echo "No PORT provided, using default port: $PORT"
else
  echo "Using provided port: $PORT"
fi

if [ -z "${HOST:-}" ]; then
  HOST=0.0.0.0
  echo "No HOST provided, using default host: $HOST"
else
  echo "Using provided host: $HOST"
fi

CMD="/usr/bin/code serve-web --host $HOST --port $PORT"

if [ -n "${SERVER_DATA_DIR:-}" ]; then
  echo "Using server data directory: $SERVER_DATA_DIR"
  CMD="$CMD --server-data-dir $SERVER_DATA_DIR"
fi

if [ -n "${SERVER_BASE_PATH:-}" ]; then
  echo "Using server base path: $SERVER_BASE_PATH"
  CMD="$CMD --server-base-path $SERVER_BASE_PATH"
fi

if [ -n "${SOCKET_PATH:-}" ]; then
  echo "Using socket path: $SOCKET_PATH"
  CMD="$CMD --socket-path $SOCKET_PATH"
fi

if [ -z "${TOKEN:-}" ]; then
  echo "No TOKEN provided, starting without token"
  CMD="$CMD --without-connection-token"
else
  echo "Starting with token from TOKEN env"
  CMD="$CMD --connection-token $TOKEN"
fi

if [ -n "${TOKEN_FILE:-}" ]; then
  echo "Using token file: $TOKEN_FILE"
  CMD="$CMD --connection-token-file $TOKEN_FILE"
fi

# Always accept license
CMD="$CMD --accept-server-license-terms"

if [ -n "${VERBOSE:-}" ] && [ "${VERBOSE}" = "true" ]; then
  echo "Running in verbose mode"
  CMD="$CMD --verbose"
fi

if [ -n "${LOG_LEVEL:-}" ]; then
  echo "Using log level: $LOG_LEVEL"
  CMD="$CMD --log $LOG_LEVEL"
fi

if [ -n "${CLI_DATA_DIR:-}" ]; then
  echo "Using CLI data directory: $CLI_DATA_DIR"
  CMD="$CMD --cli-data-dir $CLI_DATA_DIR"
fi

# Start the server in background, wait for it to respond, then perform runtime extension installs
echo "Starting VS Code server as $USERNAME in background: $CMD"
su - "$USERNAME" -c "$CMD" &
SERVER_PID=$!

wait_for_http() {
  local retries=${1:-20}
  local delay=${2:-3}
  local url="http://127.0.0.1:${PORT:-8585}/"
  echo "Waiting for HTTP response at $url (up to $((retries*delay))s)"
  for i in $(seq 1 $retries); do
    if curl -fsS --max-time 2 "$url" >/dev/null 2>&1; then
      echo "HTTP endpoint is responding"
      return 0
    fi
    echo "HTTP not ready ($i/$retries), sleeping $delay s"
    sleep $delay
  done
  echo "HTTP endpoint did not respond in time"
  return 1
}

# If EXTENSIONS set, wait for server then install (with retries)
if [ -n "${EXTENSIONS:-}" ]; then
  echo "Will attempt runtime installs for EXTENSIONS: $EXTENSIONS"
  ext_list=$(echo "$EXTENSIONS" | tr ',' ' ')
  if wait_for_http 20 3; then
    for ext in $ext_list; do
      [ -n "$ext" ] || continue
      installed=$(su - "$USERNAME" -c "code --list-extensions" || true)
      if echo "$installed" | grep -Fxq "$ext"; then
        echo "Extension $ext already installed, skipping"
      else
        install_with_retries "$ext" 8 6 || echo "Giving up on $ext"
      fi
    done
  else
    echo "Server not responding; attempting installs anyway (may fail)"
    for ext in $ext_list; do
      [ -n "$ext" ] || continue
      install_with_retries "$ext" 8 6 || echo "Giving up on $ext"
    done
  fi
fi

# Wait for the server process (foreground)
wait $SERVER_PID
