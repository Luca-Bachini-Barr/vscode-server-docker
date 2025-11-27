# docker-dev

This directory is a development workspace for rebuilding the VS Code image without relying on the `nerasse` base image.

Work in a feature branch (example):

```bash
git checkout -b feat/remove-nerasse-base
# make changes inside docker-dev/
```

Goals
- Build an arm64 image that runs the official VS Code desktop inside the container and exposes it to a browser (noVNC), preserving the runtime behavior you currently rely on (PUID/PGID, TOKEN/TOKEN_FILE, docker socket access, extension persistence).

Files in this directory
- `Dockerfile.template` - annotated starter Dockerfile (arm64) showing the steps to install VS Code, noVNC stack and Docker CLI.
- `entrypoint.sh` - runtime entrypoint stub that handles UID/GID mapping, docker socket group handling, and starts the display/VNC stack and VS Code.
- `.gitignore` - includes `.env` (keep real env files out of VCS).

Build & test (local, requires an arm64 builder or an arm64 host)

```bash
# use buildx for arm64
docker buildx create --use --name mybuilder || true
docker buildx inspect --bootstrap
# build and load for local testing (may require qb setup)
docker buildx build --platform linux/arm64 -t my-vscode-arm64:dev --load -f Dockerfile.template .

# run (example)
docker run --rm -e PUID=$(id -u) -e PGID=$(id -g) -e TOKEN=yourtoken \
  -v /path/to/data:/home/vscodeuser \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -p 6080:6080 my-vscode-arm64:dev

# open http://localhost:6080 in your browser to access the desktop session (noVNC)
```

Notes & recommendations
- Work in the branch and open a PR when ready. Keep `main` untouched until you verify the new image.
- Do not commit secrets; use `.env` for local testing and add to `.gitignore`.
- For production, run noVNC behind an authenticated TLS reverse proxy.
