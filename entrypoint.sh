#!/bin/bash
set -e

# If host Docker socket is mounted, skip starting dockerd (Docker-outside-of-Docker).
DOCKER_SOCKET=${DOCKER_SOCKET:-/var/run/docker.sock}
LOGFILE=/var/log/dockerd.log

start_dockerd() {
    mkdir -p /var/log
    echo "Starting dockerd (DinD) and logging to $LOGFILE"
    dockerd-entrypoint.sh dockerd --host=unix:///var/run/docker.sock >"$LOGFILE" 2>&1 &
    DOCKERD_PID=$!
    # Tail the log so `docker logs` and CI shows dockerd output
    tail -n +1 -F "$LOGFILE" &
    TAIL_PID=$!

    # Wait for socket
    TIMEOUT=30
    while [ ! -S "$DOCKER_SOCKET" ]; do
        if ! kill -0 $DOCKERD_PID 2>/dev/null; then
            echo "dockerd process exited unexpectedly. Check $LOGFILE for details."
            echo "---- /var/log/dockerd.log ----"
            sed -n '1,200p' "$LOGFILE" || true
            exit 1
        fi
        if [ $TIMEOUT -le 0 ]; then
            echo "Timeout waiting for dockerd to start. Check $LOGFILE for details."
            echo "---- /var/log/dockerd.log ----"
            sed -n '1,200p' "$LOGFILE" || true
            echo "Possible fixes: run the container with -v /var/run/docker.sock:/var/run/docker.sock (use host Docker), or run DinD with privileged mode and DOCKER_TLS_CERTDIR=\"\"."
            kill -TERM $DOCKERD_PID 2>/dev/null || true
            for i in {1..5}; do
                if ! kill -0 $DOCKERD_PID 2>/dev/null; then
                    break
                fi
                sleep 1
            done
            if kill -0 $DOCKERD_PID 2>/dev/null; then
                echo "dockerd did not exit gracefully; sending SIGKILL."
                kill -KILL $DOCKERD_PID 2>/dev/null || true
            fi
            exit 1
        fi
        sleep 1
        TIMEOUT=$((TIMEOUT - 1))
    done
}

# If DOCKER_HOST is set (tcp), don't wait for unix socket here; assume user configured DOCKER_HOST externally.
if [ -n "$DOCKER_HOST" ]; then
    echo "DOCKER_HOST is set to '$DOCKER_HOST' - skipping socket check and dockerd auto-start."
    DOCKERD_PID=
else
    if [ -S "$DOCKER_SOCKET" ]; then
        echo "Host Docker socket detected at $DOCKER_SOCKET - skipping dockerd startup (using host Docker)."
        DOCKERD_PID=
    else
        echo "No host Docker socket detected; starting dockerd inside container."
        start_dockerd
    fi
fi

# Setup trap to stop dockerd/sshd/tail on termination signals
cleanup() {
    echo "Shutting down..."
    if [ -n "$SSHD_PID" ]; then
        kill -TERM $SSHD_PID 2>/dev/null || true
    fi
    if [ -n "$DOCKERD_PID" ]; then
        kill -TERM $DOCKERD_PID 2>/dev/null || true
        sleep 1
        if kill -0 $DOCKERD_PID 2>/dev/null; then
            kill -KILL $DOCKERD_PID 2>/dev/null || true
        fi
    fi
    if [ -n "$TAIL_PID" ]; then
        kill -TERM $TAIL_PID 2>/dev/null || true
    fi
}
trap cleanup TERM INT EXIT

# Start sshd in the foreground but keep this script as PID 1 so trap works
/usr/sbin/sshd -D &
SSHD_PID=$!

# Wait for sshd to exit; when it does, cleanup will be triggered by the EXIT trap
wait $SSHD_PID
