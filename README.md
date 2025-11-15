# vscode-server-docker

Derived code-server image with Docker CLI & Compose support, plus entrypoint to map PUID/PGID and access the docker socket.

Files:
- , ,  — image build and runtime config
-  — example Compose file for running the container

Usage:
1. Build or pull the image.
2. Start with .

Notes:
- Keep secrets out of the repository; use an  file and update  accordingly.
