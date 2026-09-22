#!/usr/bin/env bash
# health_check.sh <url> [retries] [delay_seconds]
#
# Validates that a deployed service is up by polling its /health endpoint.
# Used by Jenkins as an explicit post-deploy gate (separate from the
# in-container HEALTHCHECK and the swap logic inside deploy.sh), so a bad
# deploy fails the pipeline instead of silently going live.
set -euo pipefail

URL="${1:?Usage: health_check.sh <url> [retries] [delay_seconds]}"
RETRIES="${2:-10}"
DELAY="${3:-5}"

echo "==> Validating deployment health at ${URL}"
for attempt in $(seq 1 "${RETRIES}"); do
    http_code=$(curl -s -o /tmp/health_response.json -w '%{http_code}' "${URL}" || echo "000")

    if [ "${http_code}" = "200" ]; then
        status=$(grep -o '"status":"[^"]*"' /tmp/health_response.json | cut -d'"' -f4 || echo "")
        echo "Attempt ${attempt}/${RETRIES}: HTTP 200, status=${status}"
        if [ "${status}" = "healthy" ]; then
            echo "Health check PASSED."
            exit 0
        fi
    else
        echo "Attempt ${attempt}/${RETRIES}: HTTP ${http_code} (not ready yet)"
    fi

    sleep "${DELAY}"
done

echo "Health check FAILED after ${RETRIES} attempts."
exit 1
