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
        # Attempt graceful shutdown
        kill -TERM $DOCKERD_PID 2>/dev/null || true
        # Wait up to 5 seconds for dockerd to exit
        for i in {1..5}; do
            if ! kill -0 $DOCKERD_PID 2>/dev/null; then
                break
            fi
            sleep 1
        done
        # If still running, force kill
        if kill -0 $DOCKERD_PID 2>/dev/null; then
            echo "dockerd did not exit gracefully; sending SIGKILL."
            kill -KILL $DOCKERD_PID 2>/dev/null || true
        fi
        exit 1
    fi
    sleep 1
    TIMEOUT=$((TIMEOUT - 1))
done

# Start sshd in the foreground
exec /usr/sbin/sshd -D
