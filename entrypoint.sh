#!/bin/bash
set -e

# Start dockerd in the background
dockerd-entrypoint.sh dockerd --host=unix:///var/run/docker.sock &
DOCKERD_PID=$!

# Wait for Docker socket to be available (timeout after 30s)
TIMEOUT=30
while [ ! -S /var/run/docker.sock ]; do
    if ! kill -0 $DOCKERD_PID 2>/dev/null; then
        echo "dockerd process exited unexpectedly."
        exit 1
    fi
    if [ $TIMEOUT -le 0 ]; then
        echo "Timeout waiting for dockerd to start."
        kill $DOCKERD_PID 2>/dev/null || true
        exit 1
    fi
    sleep 1
    TIMEOUT=$((TIMEOUT - 1))
done

# Start sshd in the foreground
exec /usr/sbin/sshd -D
