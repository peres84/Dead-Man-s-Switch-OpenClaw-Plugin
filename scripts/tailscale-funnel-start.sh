#!/bin/bash
# tailscale-funnel-start.sh
# Enables Tailscale Funnel for the OpenClaw gateway on port 18789.
# Waits up to 90 seconds for tailscaled to reach Running state before enabling.
#
# Exit codes:
#   0 - Funnel enabled successfully
#   1 - Tailscale never reached Running state within timeout

set -e

LOG_PREFIX="[tailscale-funnel-start]"
TAILSCALE=/usr/bin/tailscale
TAILSCALE_SOCKET=/var/run/tailscale/tailscaled.sock
FUNNEL_PORT=18789
MAX_ATTEMPTS=30
SLEEP_SECONDS=3

echo "$LOG_PREFIX Starting Tailscale Funnel setup for port $FUNNEL_PORT"
echo "$LOG_PREFIX Will attempt up to $MAX_ATTEMPTS times (${SLEEP_SECONDS}s apart)"

for i in $(seq 1 $MAX_ATTEMPTS); do
    STATUS=$($TAILSCALE --socket $TAILSCALE_SOCKET status --json 2>/dev/null \
        | python3 -c "import sys,json; print(json.load(sys.stdin).get('BackendState',''))" 2>/dev/null || echo "")

    echo "$LOG_PREFIX Attempt $i: BackendState=$STATUS"

    if [ "$STATUS" = "Running" ]; then
        echo "$LOG_PREFIX Tailscale is Running — enabling Funnel on port $FUNNEL_PORT"
        if $TAILSCALE funnel --bg $FUNNEL_PORT; then
            echo "$LOG_PREFIX Funnel enabled successfully"
            exit 0
        else
            echo "$LOG_PREFIX ERROR: tailscale funnel command failed" >&2
            exit 1
        fi
    fi

    if [ "$i" -lt "$MAX_ATTEMPTS" ]; then
        sleep $SLEEP_SECONDS
    fi
done

echo "$LOG_PREFIX ERROR: Tailscale never reached Running state after $MAX_ATTEMPTS attempts" >&2
exit 1
