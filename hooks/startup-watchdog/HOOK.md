---
name: startup-watchdog
description: "On gateway startup, reads the DMS fix log and alerts the user if any service has been failing repeatedly in the last 24 hours."
metadata: {"openclaw": {"emoji": "👁️", "events": ["gateway:startup"]}}
---

# Startup Watchdog Hook

This hook fires once on `gateway:startup` and performs a brief audit of the
Dead Man's Switch fix log. Its purpose is to surface recurring failures that
the user should know about when they start a new session.

## What It Does

1. Reads `~/.openclaw/dms-fix-log.jsonl`
2. Counts failures per service in the last 24 hours
3. If any service has failed 2 or more times:
   - Posts an alert message in the gateway chat
   - Suggests a cron command the user can run to set up monitoring
4. Does nothing if the log is empty or no services are recurring

## Why This Exists

The Dead Man's Switch fixes things silently in the background. The startup
watchdog ensures that when you open a new session, you immediately know if
something has been unstable — even if each individual fix succeeded.

## Cron Suggestion Format

When a recurring failure is detected, the hook outputs a message like:

```
⚠️  Dead Man's Switch: tailscale has failed 3 times in the last 24 hours.

To set up automatic monitoring, run:
openclaw cron add --name "DMS: tailscale Monitor" --cron "*/5 * * * *" \
  --session isolated \
  --message "Dead Man's Switch: check tailscale funnel status. If (tailnet only), run recovery." \
  --announce
```

## Implementation

The logic is in `handler.ts`. The hook uses the same fix log format as the
main plugin:

```jsonl
{"timestamp":"ISO8601","service":"tailscale","issue":"...","fix":"...","result":"success","duration_ms":1234}
```
