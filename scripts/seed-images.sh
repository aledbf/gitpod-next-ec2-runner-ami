#!/bin/bash

echo "Docker details"

docker info

# Embed docker images required to start the node without downloading content.
readonly SEED_FILE="/tmp/devcontainer-seed-images.txt"
if [ -f "${SEED_FILE}" ]; then
	echo "Downloading container images..."
	xargs -a "${SEED_FILE}" -n1 -P4 -I{} -t bash -c "docker pull --quiet {} || true"
fi

echo "Docker images:"
docker images
