#!/bin/bash
# disk-cleanup.sh
# Frees disk space on the root filesystem by cleaning safe targets:
#   - apt package cache
#   - systemd journal (keeps last 7 days, max 500MB)
#   - old rotated log files (compressed/rotated older than 30 days)
#   - stale /tmp files (older than 24h)
#   - unused Docker images/containers (if Docker is installed)
#
# Exit codes:
#   0 - Cleanup completed (may or may not have freed significant space)
#   1 - An error occurred during cleanup

set -e

LOG_PREFIX="[disk-cleanup]"

echo "$LOG_PREFIX Starting disk cleanup"
echo ""

# Capture before state
BEFORE=$(df -h / | tail -1)
BEFORE_PCT=$(df / | tail -1 | awk '{print $5}' | tr -d '%')
echo "$LOG_PREFIX Disk usage before: $BEFORE"
echo ""

FREED_STEPS=0

# Step 1: apt cache
echo "=== Step 1: Cleaning apt cache ==="
if command -v apt-get >/dev/null 2>&1; then
    apt-get clean
    apt-get autoclean -y 2>&1 | tail -5
    echo "$LOG_PREFIX apt cache cleaned"
    FREED_STEPS=$((FREED_STEPS + 1))
else
    echo "$LOG_PREFIX apt not found, skipping"
fi
echo ""

# Step 2: systemd journal
echo "=== Step 2: Vacuuming systemd journal ==="
if command -v journalctl >/dev/null 2>&1; then
    journalctl --vacuum-time=7d 2>&1 || true
    journalctl --vacuum-size=500M 2>&1 || true
    echo "$LOG_PREFIX Journal vacuumed"
    FREED_STEPS=$((FREED_STEPS + 1))
else
    echo "$LOG_PREFIX journalctl not found, skipping"
fi
echo ""

# Step 3: Old rotated logs
echo "=== Step 3: Removing old rotated logs (>30 days) ==="
OLD_GZ=$(find /var/log -name "*.gz" -mtime +30 2>/dev/null | wc -l)
OLD_ROTATED=$(find /var/log -name "*.1" -mtime +30 2>/dev/null | wc -l)
echo "$LOG_PREFIX Found $OLD_GZ .gz files and $OLD_ROTATED .1 files older than 30 days"
find /var/log -name "*.gz" -mtime +30 -delete 2>/dev/null || true
find /var/log -name "*.1" -mtime +30 -delete 2>/dev/null || true
echo "$LOG_PREFIX Old rotated logs removed"
FREED_STEPS=$((FREED_STEPS + 1))
echo ""

# Step 4: Stale /tmp files
echo "=== Step 4: Cleaning stale /tmp files (>24h) ==="
TMP_COUNT=$(find /tmp -type f -atime +1 2>/dev/null | wc -l)
echo "$LOG_PREFIX Found $TMP_COUNT stale files in /tmp"
find /tmp -type f -atime +1 -delete 2>/dev/null || true
echo "$LOG_PREFIX /tmp cleaned"
FREED_STEPS=$((FREED_STEPS + 1))
echo ""

# Step 5: Docker (if present)
echo "=== Step 5: Docker cleanup ==="
if command -v docker >/dev/null 2>&1; then
    echo "$LOG_PREFIX Docker found — pruning stopped containers and dangling images"
    docker system prune -f 2>&1 || true
    FREED_STEPS=$((FREED_STEPS + 1))
else
    echo "$LOG_PREFIX Docker not found, skipping"
fi
echo ""

# Capture after state
AFTER=$(df -h / | tail -1)
AFTER_PCT=$(df / | tail -1 | awk '{print $5}' | tr -d '%')
echo "=== Summary ==="
echo "$LOG_PREFIX Disk usage before: $BEFORE"
echo "$LOG_PREFIX Disk usage after:  $AFTER"
echo "$LOG_PREFIX Space reclaimed: from ${BEFORE_PCT}% to ${AFTER_PCT}%"
echo "$LOG_PREFIX Steps completed: $FREED_STEPS"

if [ "$AFTER_PCT" -ge 85 ]; then
    echo "$LOG_PREFIX WARNING: Disk still at ${AFTER_PCT}% after cleanup — manual investigation needed"
    echo "$LOG_PREFIX Consider: reviewing /var/www, /opt, and /home for large files"
    echo "$LOG_PREFIX Run: du -sh /var/www/* /opt/* /home/* 2>/dev/null | sort -rh | head -20"
fi

exit 0
