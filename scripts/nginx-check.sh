#!/bin/bash
# nginx-check.sh
# Checks a URL and dumps nginx diagnostics if the response is not HTTP 200.
#
# Usage: nginx-check.sh [url]
#   Default URL: http://localhost
#
# Exit codes:
#   0 - URL returned HTTP 200
#   1 - URL returned non-200 or connection failed

set -e

LOG_PREFIX="[nginx-check]"
URL=${1:-"http://localhost"}

echo "$LOG_PREFIX Checking $URL"

STATUS=$(curl -sI --max-time 10 -o /dev/null -w "%{http_code}" "$URL" 2>/dev/null || echo "000")

echo "$LOG_PREFIX HTTP $STATUS for $URL"

if [ "$STATUS" = "200" ]; then
    echo "$LOG_PREFIX OK — site is healthy"
    exit 0
fi

echo "$LOG_PREFIX Non-200 response ($STATUS) — collecting diagnostics"
echo ""

echo "=== nginx process status ==="
systemctl status nginx --no-pager -l 2>&1 || true
echo ""

echo "=== nginx config test ==="
nginx -t 2>&1 || true
echo ""

echo "=== active sites ==="
ls /etc/nginx/sites-enabled/ 2>&1 || true
echo ""

echo "=== last 20 nginx error log lines ==="
tail -20 /var/log/nginx/error.log 2>&1 || echo "(no error log found)"
echo ""

echo "=== last 10 nginx access log lines ==="
tail -10 /var/log/nginx/access.log 2>&1 || echo "(no access log found)"
echo ""

echo "=== system resources ==="
free -h
df -h / 2>&1
echo ""

exit 1
