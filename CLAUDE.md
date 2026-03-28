# Dead Man's Switch — OpenClaw Plugin
## Project Context for Claude Code

---

## What We Are Building

An OpenClaw plugin called `openclaw-deadmans-switch` that turns OpenClaw into a
self-healing infrastructure guardian. It monitors critical services, autonomously
diagnoses failures, executes recovery playbooks, and notifies the user via voice
(ElevenLabs). When it encounters unknown errors, it searches for fixes (Tavily)
and writes what it learns back into its own playbooks.

**Core idea:** Not preconfigured monitoring — *emergent monitoring* that grows
from real failures on the user's actual machine.

---

## Tech Stack

- **Runtime:** Node.js (ESM, TypeScript)
- **Plugin SDK:** `openclaw/plugin-sdk/*` subpath imports
- **Skills:** AgentSkills-compatible `SKILL.md` files
- **Hooks:** TypeScript `handler.ts` files reacting to gateway events
- **Shell scripts:** Bash, installed to `/usr/local/bin/openclaw-skills/`
- **Sudoers:** Per-script NOPASSWD rules for privilege escalation
- **External MCPs:** ElevenLabs (voice alerts), Tavily (unknown error search)

---

## Repository Structure

```
openclaw-deadmans-switch/
├── package.json                        # npm package + openclaw entrypoints
├── openclaw.plugin.json                # Plugin manifest + configSchema
├── tsconfig.json                       # TypeScript config
├── index.ts                            # Plugin entry: registerTool + registerHook
├── install.sh                          # One-shot installer: scripts + sudoers
├── README.md                           # User-facing docs
│
├── skills/
│   └── deadmans-switch/
│       ├── SKILL.md                    # Main brain — decision logic
│       └── playbooks/
│           ├── tailscale.md            # Tailscale Funnel recovery (DOCUMENTED BELOW)
│           ├── nginx.md                # Nginx + website monitoring
│           ├── disk.md                 # Disk space recovery
│           └── process.md             # Generic crashed process recovery
│
├── hooks/
│   └── startup-watchdog/
│       ├── HOOK.md                     # Listens to gateway:startup
│       └── handler.ts                  # Checks fix log, creates cron if pattern found
│
└── scripts/
    ├── tailscale-funnel-start.sh       # Privileged: enables Tailscale Funnel
    ├── nginx-check.sh                  # Privileged: nginx status + reload
    ├── disk-cleanup.sh                 # Privileged: disk space recovery
    └── process-restart.sh             # Privileged: restart a named systemd service
```

---

## Plugin Manifest Requirements

`openclaw.plugin.json` must declare:

```json
{
  "id": "deadmans-switch",
  "name": "Dead Man's Switch",
  "description": "Self-healing infrastructure guardian for OpenClaw",
  "version": "0.1.0",
  "skills": ["./skills"],
  "configSchema": {
    "type": "object",
    "additionalProperties": false,
    "properties": {
      "elevenLabsApiKey": { "type": "string" },
      "tavilyApiKey": { "type": "string" },
      "services": {
        "type": "array",
        "items": { "type": "string" }
      },
      "websites": {
        "type": "array",
        "items": { "type": "string" }
      },
      "notifyChannel": { "type": "string" }
    }
  },
  "uiHints": {
    "elevenLabsApiKey": {
      "label": "ElevenLabs API Key",
      "sensitive": true,
      "placeholder": "sk-..."
    },
    "tavilyApiKey": {
      "label": "Tavily API Key",
      "sensitive": true
    }
  }
}
```

`package.json` must include (note: name MUST match the plugin manifest `id`):
```json
{
  "name": "deadmans-switch",
  "version": "0.1.0",
  "type": "module",
  "openclaw": {
    "extensions": ["./index.ts"]
  }
}
```

---

## index.ts Requirements

Use `definePluginEntry` from `openclaw/plugin-sdk/plugin-entry`.

Register:
1. **Tool `dms_recover`** — agent calls this to execute a named playbook script
2. **Tool `dms_status`** — returns current fix log summary
3. **Hook `gateway:startup`** — on boot, read fix log and create cron if recurring pattern found

```typescript
import { definePluginEntry } from "openclaw/plugin-sdk/plugin-entry";
import { Type } from "@sinclair/typebox";

export default definePluginEntry({
  id: "deadmans-switch",
  name: "Dead Man's Switch",
  description: "Self-healing infrastructure guardian",
  register(api) {
    // Tool: execute a recovery script
    api.registerTool({
      name: "dms_recover",
      description: "Execute a Dead Man's Switch recovery script for a named service",
      parameters: Type.Object({
        service: Type.String({ description: "Service name: tailscale|nginx|disk|process" }),
        reason: Type.String({ description: "Why recovery is being triggered" }),
      }),
      async execute(_id, params) {
        // Execute /usr/local/bin/openclaw-skills/<service>-check.sh
        // Log result to ~/.openclaw/dms-fix-log.jsonl
        // Return result
      },
    });

    // Tool: get fix log summary
    api.registerTool({
      name: "dms_status",
      description: "Get Dead Man's Switch fix log — recent incidents and recovery history",
      parameters: Type.Object({}),
      async execute(_id, _params) {
        // Read ~/.openclaw/dms-fix-log.jsonl
        // Return last 20 entries as summary
      },
    });

    // Hook: on gateway startup, check fix log for recurring patterns
    api.registerHook(["gateway:startup"], async (event) => {
      // Read fix log
      // If same service failed 2+ times → create cron job to monitor it
      // Notify user via event.messages if cron was created
    });
  },
});
```

---

## SKILL.md Requirements

Location: `skills/deadmans-switch/SKILL.md`

Frontmatter:
```yaml
---
name: deadmans-switch
description: Self-healing infrastructure guardian. Monitors services, diagnoses failures, executes recovery playbooks, and learns from incidents.
user-invocable: true
metadata: {"openclaw": {"emoji": "🦞", "os": ["linux"], "requires": {"bins": ["tailscale", "nginx", "curl", "systemctl"]}}}
---
```

The SKILL.md body must teach the agent:

1. **Decision logic** — when to use which playbook
2. **Cron creation rules** — only create crons when pattern is recurring
3. **Fix log format** — how to read/write `~/.openclaw/dms-fix-log.jsonl`
4. **Self-improvement** — after fixing, append new knowledge to the playbook
5. **Priority order** — check Tailscale BEFORE nginx (nginx 502 may be caused by tunnel)
6. **ElevenLabs** — use for voice alerts when API key is configured
7. **Tavily** — use for unknown errors not in any playbook

---

## ⚠️ CRITICAL: Tailscale Funnel Issue (Real Production Bug)

This is a **real documented bug** on the user's VPS. The Tailscale playbook must
handle this specific case correctly.

### The Problem

The user's VPS exposes an OpenClaw gateway via Tailscale Funnel at:
`https://your-server.ts.net`

Tailscale Funnel randomly reverts from `(Funnel on)` to `(tailnet only)`, making
the gateway unreachable from the public internet. This breaks the SpecTalk app
which calls the gateway from Google Cloud.

### Root Cause (Confirmed)

The systemd service `tailscale-funnel-openclaw.service` was failing at boot with
`unexpected state: NoState` because:
1. The service started before `tailscaled` fully authenticated
2. The heredoc-based ExecStart had shell escaping issues with Python quotes
3. The fix was to move the retry logic to a dedicated script file

### The Fix (Already Applied)

**Script:** `/usr/local/bin/tailscale-funnel-start.sh`
```bash
#!/bin/bash
for i in $(seq 1 30); do
    STATUS=$(/usr/bin/tailscale --socket /var/run/tailscale/tailscaled.sock status --json 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('BackendState',''))" 2>/dev/null)
    echo "Attempt $i: BackendState=$STATUS"
    if [ "$STATUS" = "Running" ]; then
        /usr/bin/tailscale funnel --bg 18789 && echo "Funnel enabled" && exit 0
    fi
    sleep 3
done
echo "Tailscale never reached Running state"
exit 1
```

**Systemd service:** `/etc/systemd/system/tailscale-funnel-openclaw.service`
```ini
[Unit]
Description=Tailscale Funnel for OpenClaw
After=network-online.target tailscaled.service
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/tailscale-funnel-start.sh
ExecStop=/usr/bin/tailscale funnel --https=443 off

[Install]
WantedBy=multi-user.target
```

**Sudoers rule:** `/etc/sudoers.d/openclaw-skills`
```
<your-username> ALL=(root) NOPASSWD: /usr/local/bin/tailscale-funnel-start.sh
```

### How the Agent Detects This

```bash
# Check Funnel status
tailscale funnel status

# Output when BROKEN (needs fix):
# https://your-server.ts.net (tailnet only)

# Output when WORKING:
# https://your-server.ts.net (Funnel on)
```

### Recovery Steps the Agent Must Take

1. Run `tailscale funnel status`
2. If output contains `(tailnet only)` → issue detected
3. Run `sudo /usr/local/bin/tailscale-funnel-start.sh`
4. Wait 5 seconds
5. Run `tailscale funnel status` again to verify
6. If `(Funnel on)` → success, log it
7. If still `(tailnet only)` → check `sudo systemctl status tailscale-funnel-openclaw.service`
8. If service failed → `sudo systemctl restart tailscale-funnel-openclaw.service`
9. Log result to `~/.openclaw/dms-fix-log.jsonl`
10. Send ElevenLabs voice alert if API key configured

### Why Check Tailscale Before Nginx

If Tailscale Funnel is down, nginx may appear to be failing (502/timeout) because
external requests can't reach the server. Always check Tailscale first.

### Cron Creation Rule for Tailscale

- First occurrence → fix silently, log it
- Second occurrence (seen in fix log) → fix + create cron:

```bash
openclaw cron add \
  --name "DMS: Tailscale Funnel Monitor" \
  --cron "*/5 * * * *" \
  --session isolated \
  --message "Dead Man's Switch: Check tailscale funnel status. If (tailnet only), run sudo /usr/local/bin/tailscale-funnel-start.sh, verify fix, log result." \
  --announce \
  --channel telegram
```

---

## Nginx Playbook Requirements

The nginx skill must handle:

### Detection
```bash
# Ping each configured website
curl -sI --max-time 10 https://your-site.com
curl -sI --max-time 10 https://your-other-site.com

# Check nginx process
sudo systemctl status nginx

# Check nginx config validity
sudo nginx -t

# Check error logs
sudo tail -50 /var/log/nginx/error.log
```

### Recovery by Status Code

| Status | Diagnosis | Fix |
|--------|-----------|-----|
| 200 | All good | Log OK, do nothing |
| 502 Bad Gateway | Upstream app dead | Check + restart app process |
| 503 | nginx overloaded | Check resources |
| 504 | Upstream timeout | Check app + tailscale |
| timeout | nginx down or tunnel down | Check tailscale FIRST, then nginx |
| 404 | Wrong root or config | Check nginx sites-enabled |

### Recovery Commands

```bash
# Test config (always before reload)
sudo nginx -t

# Reload config (zero downtime)
sudo nginx -s reload

# Restart nginx
sudo systemctl restart nginx

# Check which sites are active
ls /etc/nginx/sites-enabled/

# Check upstream app (example)
sudo systemctl status your-app-name
```

### Script: `/usr/local/bin/openclaw-skills/nginx-check.sh`

```bash
#!/bin/bash
# Usage: nginx-check.sh <url>
URL=${1:-"http://localhost"}
STATUS=$(curl -sI --max-time 10 -o /dev/null -w "%{http_code}" "$URL")
echo "HTTP $STATUS for $URL"

if [ "$STATUS" != "200" ]; then
    echo "--- nginx status ---"
    systemctl status nginx --no-pager
    echo "--- nginx config test ---"
    nginx -t 2>&1
    echo "--- last 20 error log lines ---"
    tail -20 /var/log/nginx/error.log
fi
```

---

## Fix Log Format

All incidents must be logged to `~/.openclaw/dms-fix-log.jsonl`:

```jsonl
{"timestamp":"2026-03-28T00:15:44Z","service":"tailscale","issue":"funnel reverted to tailnet-only","fix":"ran tailscale-funnel-start.sh","result":"success","duration_ms":3200}
{"timestamp":"2026-03-28T01:00:00Z","service":"nginx","issue":"502 on your-site.com","fix":"restarted upstream process","result":"success","duration_ms":1100}
```

---

## Smart Cron Decision Logic

The agent (via SKILL.md instructions) must:

```
On any fix:
    1. Write to fix log
    2. Read fix log for this service
    3. If this service appears 2+ times in last 24h:
        → Create a cron job for it
        → Notify user: "I noticed this keeps happening, set up monitoring"
    4. If user explicitly says "monitor X" or "keep X always up":
        → Create cron immediately
```

**Never create crons preemptively.** Only create when pattern is detected or user asks.

---

## ElevenLabs Voice Alert Integration

When `elevenLabsApiKey` is configured, after any recovery action the agent should
generate a voice message using the ElevenLabs MCP:

Example messages:
- "Your Tailscale tunnel dropped. Recovery was successful."
- "Nginx returned a 502 on your-site.com. I restarted the upstream process. The site is back online."
- "Warning: disk space is at 92%. I cleared old logs. You have 15 gigabytes free now."

The ElevenLabs MCP is configured separately by the user. The SKILL.md should
instruct the agent to use it when available.

---

## Tavily Search Integration

When the agent encounters an error NOT covered by any playbook:

1. Log the unknown error
2. Search Tavily: `"<error message> fix ubuntu 24 <service>"`
3. Read the top result
4. Attempt the fix
5. If successful → append to relevant playbook file
6. Log: "Learned new fix for <service>: <description>"

---

## install.sh Requirements

The install script must:

```bash
#!/bin/bash
set -e

echo "🦞 Dead Man's Switch — OpenClaw Plugin Installer"

# 1. Create scripts directory
sudo mkdir -p /usr/local/bin/openclaw-skills

# 2. Copy all scripts
sudo cp scripts/*.sh /usr/local/bin/openclaw-skills/
sudo chmod +x /usr/local/bin/openclaw-skills/*.sh

# 3. Install sudoers rules
SUDOERS_FILE="/etc/sudoers.d/openclaw-skills"
CURRENT_USER=$(whoami)

sudo tee "$SUDOERS_FILE" > /dev/null <<EOF
$CURRENT_USER ALL=(root) NOPASSWD: /usr/local/bin/openclaw-skills/tailscale-funnel-start.sh
$CURRENT_USER ALL=(root) NOPASSWD: /usr/local/bin/openclaw-skills/nginx-check.sh
$CURRENT_USER ALL=(root) NOPASSWD: /usr/local/bin/openclaw-skills/disk-cleanup.sh
$CURRENT_USER ALL=(root) NOPASSWD: /usr/local/bin/openclaw-skills/process-restart.sh
EOF

sudo chmod 440 "$SUDOERS_FILE"
echo "✅ Sudoers rules installed"

# 4. Install skills to shared OpenClaw skills dir
SKILLS_DIR="$HOME/.openclaw/skills"
mkdir -p "$SKILLS_DIR"
cp -r skills/deadmans-switch "$SKILLS_DIR/"
echo "✅ Skills installed to $SKILLS_DIR"

# 5. Create fix log file
touch "$HOME/.openclaw/dms-fix-log.jsonl"
echo "✅ Fix log created"

echo ""
echo "🦞 Installation complete!"
echo ""
echo "Next steps:"
echo "  1. openclaw plugins install openclaw-deadmans-switch"
echo "  2. Add API keys to openclaw.json (ElevenLabs, Tavily)"
echo "  3. openclaw gateway restart"
echo "  4. Test: tell your agent 'check my services'"
```

---

## Hackathon Notes

- **Live demo:** disconnect Tailscale on stage → agent detects → fixes → ElevenLabs voice says it's back
- **Pitch:** "PagerDuty costs $500/month. This is a SKILL.md."
- **ElevenLabs prize:** voice alerts = easy prize stack
- **Innovation angle:** emergent monitoring — it configures itself from real failures
- **Key differentiator:** LLM decides which playbook to run, not hardcoded logic

---

## Important Constraints

1. **Never create crons preemptively** — only when pattern detected or user asks
2. **Always check Tailscale before nginx** — tunnel down = all sites appear down
3. **Always run `nginx -t` before reload** — never reload broken config
4. **Scripts must be in `/usr/local/bin/openclaw-skills/`** — sudoers rules point there
5. **Fix log is append-only** — never delete entries
6. **Playbooks are living documents** — agent appends new fixes after learning them
