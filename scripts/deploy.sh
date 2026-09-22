#!/usr/bin/env bash
# deploy.sh <ecr_repo> <image_tag>
#
# Runs ON the target EC2 instance (invoked over SSH by the Jenkins pipeline).
# Pulls the new image, starts it alongside the running container, verifies
# it's healthy, then atomically swaps traffic by renaming containers.
# Exits non-zero on any failure so Jenkins marks the stage failed and
# triggers rollback.sh.
set -euo pipefail

ECR_REPO="${1:?Usage: deploy.sh <ecr_repo> <image_tag>}"
IMAGE_TAG="${2:?Usage: deploy.sh <ecr_repo> <image_tag>}"
IMAGE="${ECR_REPO}:${IMAGE_TAG}"
APP_NAME="cicd-automation-platform"
PORT=8000
AWS_REGION="us-east-1"

echo "==> Logging into ECR"
aws ecr get-login-password --region "${AWS_REGION}" \
    | docker login --username AWS --password-stdin "${ECR_REPO}"

echo "==> Pulling image ${IMAGE}"
docker pull "${IMAGE}"

echo "==> Recording current image for rollback"
docker inspect --format='{{.Config.Image}}' "${APP_NAME}" 2>/dev/null \
    > /tmp/"${APP_NAME}"_previous_image.txt || true

echo "==> Starting new container on a staging port"
docker rm -f "${APP_NAME}-new" 2>/dev/null || true
docker run -d --name "${APP_NAME}-new" \
    -p 127.0.0.1:8001:${PORT} \
    --restart unless-stopped \
    -e APP_VERSION="${IMAGE_TAG}" \
    "${IMAGE}"

echo "==> Waiting for new container to become healthy"
for i in $(seq 1 15); do
    if curl -fsS "http://127.0.0.1:8001/health" > /dev/null 2>&1; then
        echo "New container is healthy."
        break
    fi
    if [ "$i" -eq 15 ]; then
        echo "New container failed health check; aborting deploy."
        docker rm -f "${APP_NAME}-new" || true
        exit 1
    fi
    sleep 2
done

echo "==> Swapping traffic to the new container"
docker rm -f "${APP_NAME}-old" 2>/dev/null || true
docker rename "${APP_NAME}" "${APP_NAME}-old" 2>/dev/null || true
docker rm -f "${APP_NAME}-new" || true
docker run -d --name "${APP_NAME}" \
    -p ${PORT}:${PORT} \
    --restart unless-stopped \
    -e APP_VERSION="${IMAGE_TAG}" \
    "${IMAGE}"

echo "==> Final health check on production port"
for i in $(seq 1 15); do
    if curl -fsS "http://127.0.0.1:${PORT}/health" > /dev/null 2>&1; then
        echo "Deployment succeeded: ${IMAGE} is live."
        docker rm -f "${APP_NAME}-old" 2>/dev/null || true
        docker image prune -f
        exit 0
    fi
    sleep 2
done

echo "Production container failed health check after swap; leaving old container for rollback.sh."
exit 1
