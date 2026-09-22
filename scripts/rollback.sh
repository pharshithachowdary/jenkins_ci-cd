#!/usr/bin/env bash
# rollback.sh <ecr_repo>
#
# Runs ON the target EC2 instance. Restores the previously running
# container if a deployment's health check failed.
set -euo pipefail

APP_NAME="cicd-automation-platform"
PORT=8000

if docker inspect "${APP_NAME}-old" >/dev/null 2>&1; then
    echo "==> Restoring previous container (${APP_NAME}-old)"
    docker rm -f "${APP_NAME}" 2>/dev/null || true
    docker rename "${APP_NAME}-old" "${APP_NAME}"
    docker start "${APP_NAME}"

    for i in $(seq 1 10); do
        if curl -fsS "http://127.0.0.1:${PORT}/health" > /dev/null 2>&1; then
            echo "Rollback successful: previous version restored."
            exit 0
        fi
        sleep 2
    done
    echo "Rollback container did not become healthy. Manual intervention required."
    exit 1
else
    echo "No previous container available to roll back to. Manual intervention required."
    exit 1
fi
