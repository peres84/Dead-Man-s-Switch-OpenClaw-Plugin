#!/bin/bash
# process-restart.sh
# Restarts a named systemd service and verifies it comes back up.
#
# Usage: process-restart.sh <service-name>
#
# Exit codes:
#   0 - Service restarted and verified running
#   1 - Service failed to start or no service name provided

set -e

LOG_PREFIX="[process-restart]"

if [ -z "$1" ]; then
    echo "$LOG_PREFIX ERROR: No service name provided" >&2
    echo "$LOG_PREFIX Usage: $0 <service-name>" >&2
    exit 1
fi

SERVICE_NAME="$1"

echo "$LOG_PREFIX Attempting to restart service: $SERVICE_NAME"
echo ""

# Step 1: Check current status
echo "=== Current status ==="
systemctl status "$SERVICE_NAME" --no-pager -l 2>&1 || true
echo ""

# Step 2: Get current state
ACTIVE_STATE=$(systemctl show "$SERVICE_NAME" --property=ActiveState 2>/dev/null | cut -d= -f2 || echo "unknown")
echo "$LOG_PREFIX Current state: $ACTIVE_STATE"

# Step 3: Reset failed state if necessary
if [ "$ACTIVE_STATE" = "failed" ]; then
    echo "$LOG_PREFIX Service is in failed state — resetting before restart"
    systemctl reset-failed "$SERVICE_NAME" 2>&1 || true
fi

# Step 4: Restart the service
echo "$LOG_PREFIX Issuing restart command"
if ! systemctl restart "$SERVICE_NAME"; then
    echo "$LOG_PREFIX ERROR: systemctl restart command failed" >&2
    echo ""
    echo "=== Journal (last 30 lines) ==="
    journalctl -u "$SERVICE_NAME" -n 30 --no-pager 2>&1 || true
    exit 1
fi

# Step 5: Wait for service to settle
echo "$LOG_PREFIX Waiting 5 seconds for service to start..."
sleep 5

# Step 6: Verify
echo ""
echo "=== Post-restart status ==="
systemctl status "$SERVICE_NAME" --no-pager -l 2>&1 || true
echo ""

NEW_STATE=$(systemctl show "$SERVICE_NAME" --property=ActiveState 2>/dev/null | cut -d= -f2 || echo "unknown")
echo "$LOG_PREFIX New state: $NEW_STATE"

if [ "$NEW_STATE" = "active" ]; then
    echo "$LOG_PREFIX SUCCESS: $SERVICE_NAME is now running"
    exit 0
else
    echo "$LOG_PREFIX WARNING: $SERVICE_NAME state is '$NEW_STATE' after restart" >&2
    echo ""
    echo "=== Journal (last 50 lines) ==="
    journalctl -u "$SERVICE_NAME" -n 50 --no-pager 2>&1 || true
    exit 1
fi
