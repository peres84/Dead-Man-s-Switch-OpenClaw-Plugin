<p align="center">
  <img src="images/logo-transparent.png" alt="Dead Man's Switch" width="160" />
</p>

<p align="center">
  <img src="https://img.shields.io/badge/🦞_Dead_Man's_Switch-OpenClaw_Plugin-FF5C1A?style=for-the-badge&labelColor=0A0C10" alt="Dead Man's Switch" />
</p>

<p align="center">
  <img src="https://img.shields.io/badge/version-0.1.0-FF5C1A?style=flat-square&labelColor=111318" />
  <img src="https://img.shields.io/badge/platform-Linux-00D4FF?style=flat-square&labelColor=111318&logo=linux&logoColor=white" />
  <img src="https://img.shields.io/badge/runtime-Node.js_ESM-339933?style=flat-square&labelColor=111318&logo=node.js&logoColor=white" />
  <img src="https://img.shields.io/badge/language-TypeScript-3178C6?style=flat-square&labelColor=111318&logo=typescript&logoColor=white" />
  <img src="https://img.shields.io/badge/license-MIT-22C55E?style=flat-square&labelColor=111318" />
</p>

<p align="center">
  <img src="https://img.shields.io/badge/ElevenLabs-Voice_Alerts-black?style=flat-square&labelColor=111318&logo=elevenlabs&logoColor=white" />
  <img src="https://img.shields.io/badge/Tavily-Unknown_Error_Search-0EA5E9?style=flat-square&labelColor=111318" />
  <img src="https://img.shields.io/badge/OpenClaw-Plugin_SDK-FF5C1A?style=flat-square&labelColor=111318" />
</p>

<p align="center">
  <img src="https://img.shields.io/badge/OpenClaw_Hack__001-Vienna_2026_🏆-FF5C1A?style=flat-square&labelColor=0A0C10" />
</p>

<br />

<p align="center">
  <strong>Your infrastructure, self-healing.</strong><br />
  Not preconfigured monitoring — <em>emergent monitoring</em> that grows from real failures on your actual machine.
</p>

<p align="center">
  <em>PagerDuty costs $500/month. This is a <code>SKILL.md</code>.</em>
</p>

<p align="center">
  <a href="https://deadmans-guard-bot.lovable.app/">
    <img src="https://img.shields.io/badge/🌐_Live_Demo-deadmans--guard--bot.lovable.app-FF5C1A?style=for-the-badge&labelColor=0A0C10" alt="Live Demo" />
  </a>
</p>

---

## What It Does

Dead Man's Switch turns OpenClaw into an autonomous infrastructure guardian. It monitors critical services, diagnoses failures using a priority-ordered playbook system, executes recovery procedures without human intervention, and notifies you by voice via ElevenLabs. When it encounters an error it doesn't recognize, it searches for a fix (Tavily) and writes what it learns back into its own playbooks — so it gets smarter with every incident.

---

## Architecture

<p align="center">
  <img src="images/architecture.png" alt="Dead Man's Switch — How It Works" />
</p>

Three entry points — a user command, a scheduled cron, or the gateway startup hook — all funnel into the same agent loop. Each step runs a prioritized check, branches on a decision diamond, and either executes a recovery script or falls through to the next check. Every outcome writes to the fix log. Voice alert fires last.

> **Priority rule:** Tailscale is always checked first. If the tunnel is down, every external site returns 502 — not because nginx is broken, but because the tunnel is broken.

---

## How It Learns

<p align="center">
  <img src="images/emergent-monitoring.png" alt="The Self-Improving Guardian" />
</p>

The core innovation is **emergent monitoring** — the plugin configures itself from real failures rather than requiring upfront setup.

- **First failure:** fix silently, log the incident
- **Second failure (same service, within 24h):** fix + suggest a cron job to monitor it permanently
- **Unknown error:** search Tavily → attempt fix → if successful, append to the relevant playbook

Playbooks are living documents. The agent rewrites them.

---

## Installation

### Option 1 — ClawHub *(recommended, already published)*

The plugin is live on ClawHub. One command to install:

```bash
clawhub install https://clawhub.ai/peres84/deadmans-switch
```

Then run the recovery script installer:

```bash
bash install.sh
```

> This copies scripts to `/usr/local/bin/openclaw-skills/`, writes sudoers rules, installs the skill to `~/.openclaw/skills/`, and creates the fix log.

### Option 2 — From source (GitHub)

```bash
# 1. Clone the repo
git clone https://github.com/your-user/Dead-Man-s-Switch-OpenClaw-Plugin.git
cd Dead-Man-s-Switch-OpenClaw-Plugin

# 2. Install dependencies
npm install

# 3. Install recovery scripts + sudoers rules (requires sudo, idempotent)
bash install.sh

# 4. Register with OpenClaw (--link for live updates via git pull)
openclaw plugins install "$(pwd)" --link

# 5. Restart the gateway
systemctl --user restart openclaw-gateway.service

# 6. Tell your agent:
#    "check my services"
```

---

## Configuration

Add to your `~/.openclaw/openclaw.json`:

```json
{
  "plugins": {
    "entries": {
      "deadmans-switch": {
        "enabled": true,
        "config": {
          "elevenLabsApiKey": "your-elevenlabs-key",
          "tavilyApiKey": "tvly-your-tavily-key",
          "websites": [
            "https://your-site.com",
            "https://your-other-site.com"
          ],
          "services": ["tailscale", "nginx"]
        }
      }
    }
  }
}
```

| Field | Required | Description |
|-------|:--------:|-------------|
| `websites` | — | URLs to check for HTTP 200 on every run |
| `services` | — | Services to monitor (informational label) |
| `elevenLabsApiKey` | — | Enables voice alerts via ElevenLabs MCP |
| `tavilyApiKey` | — | Enables Tavily search for unknown error fixes |

---

## Plugin Components

<p align="center">
  <img src="images/component-map.png" alt="Plugin Component Map" />
</p>

The plugin registers two tools and one hook through `index.ts`:

| Component | Type | Description |
|-----------|------|-------------|
| `dms_recover` | Tool | Execute a named recovery script · logs result automatically |
| `dms_status` | Tool | Query the fix log — last 20 incidents, per-service counts, recurring patterns |
| `gateway:startup` | Hook | Reads fix log on boot · alerts if any service has failed 2+ times in 24h |

`SKILL.md` is the decision brain — it holds the diagnostic sequence, playbook routing logic, cron rules, and ElevenLabs/Tavily integration instructions. The agent reads it on every invocation.

---

## Playbooks

> Playbooks live in `skills/deadmans-switch/playbooks/` and are **living documents** —
> the agent appends new fixes after learning them via Tavily.

| Playbook | Triggers When | Key Recovery Commands |
|----------|--------------|----------------------|
| [`tailscale.md`](skills/deadmans-switch/playbooks/tailscale.md) | `(tailnet only)` in funnel status | `sudo tailscale-funnel-start.sh` |
| [`nginx.md`](skills/deadmans-switch/playbooks/nginx.md) | Non-200 HTTP, nginx errors | `nginx -t` · `nginx -s reload` · `systemctl restart nginx` |
| [`disk.md`](skills/deadmans-switch/playbooks/disk.md) | Disk ≥ 85% used | `apt-get clean` · `journalctl --vacuum` · log rotation |
| [`process.md`](skills/deadmans-switch/playbooks/process.md) | Any crashed systemd service | `systemctl restart <svc>` · `systemctl reset-failed` |

---

## The Tailscale Recovery Flow

<p align="center">
  <img src="images/tailscale-recovery-flow.png" alt="Tailscale Funnel Recovery Flow" />
</p>

This plugin was built to solve a **real, recurring production bug**: Tailscale Funnel randomly drops from `(Funnel on)` to `(tailnet only)`, making the OpenClaw gateway unreachable from the public internet.

**Root cause:** The systemd service started before `tailscaled` finished authenticating → `NoState` error. Fixed by moving retry logic to a dedicated script that polls `BackendState` up to 30 times before enabling the funnel.

The recovery script (`tailscale-funnel-start.sh`) is installed to `/usr/local/bin/openclaw-skills/` with a NOPASSWD sudoers rule — so the agent can run it without interrupting you for a password.

---

## Prerequisites

| Requirement | Details |
|-------------|---------|
| ![OS](https://img.shields.io/badge/OS-Ubuntu_22.04_%2F_24.04-E95420?style=flat-square&logo=ubuntu&logoColor=white) | Linux only |
| ![Node](https://img.shields.io/badge/Node.js-≥18-339933?style=flat-square&logo=node.js&logoColor=white) | ESM runtime |
| ![Bins](https://img.shields.io/badge/Requires-tailscale_·_nginx_·_curl_·_systemctl-6B7280?style=flat-square) | Must be in PATH |
| ![Sudo](https://img.shields.io/badge/Sudo-NOPASSWD_rules_installed_by_install.sh-FF5C1A?style=flat-square) | For recovery scripts |
| ![OpenClaw](https://img.shields.io/badge/OpenClaw-installed_%26_running-FF5C1A?style=flat-square) | Gateway must be active |

**Optional but recommended:**

| Integration | Purpose |
|-------------|---------|
| ![ElevenLabs](https://img.shields.io/badge/ElevenLabs-Voice_alerts_after_recovery-black?style=flat-square&logo=elevenlabs) | Speaks the recovery result aloud |
| ![Tavily](https://img.shields.io/badge/Tavily-Searches_fixes_for_unknown_errors-0EA5E9?style=flat-square) | Self-improvement when no playbook matches |

---

## Adding Custom Playbooks

1. Create `skills/deadmans-switch/playbooks/my-service.md`
2. Include: detection commands · recovery steps · logging instructions · cron rule · voice alert text
3. Add detection logic to `SKILL.md`'s diagnostic sequence
4. Drop a script in `scripts/my-service-check.sh` and re-run `install.sh`

---

## The Fix Log

Every incident is recorded to `~/.openclaw/dms-fix-log.jsonl`:

```jsonl
{"timestamp":"2026-03-28T00:15:44Z","service":"tailscale","issue":"funnel reverted to tailnet-only","fix":"ran tailscale-funnel-start.sh","result":"success","duration_ms":3200}
{"timestamp":"2026-03-28T01:00:00Z","service":"nginx","issue":"502 on your-site.com","fix":"restarted upstream process","result":"success","duration_ms":1100}
```

The fix log is **append-only** — nothing is ever deleted. Use `dms_status` to query it.

---

## Hackathon Context

<p>
  <img src="https://img.shields.io/badge/Built_at-OpenClaw_Hack__001_Vienna_2026-FF5C1A?style=flat-square&labelColor=0A0C10" />
  <img src="https://img.shields.io/badge/Track-AI_Agents-00D4FF?style=flat-square&labelColor=0A0C10" />
  <img src="https://img.shields.io/badge/ElevenLabs-Bounty_Eligible-black?style=flat-square&logo=elevenlabs&labelColor=0A0C10" />
</p>

- **Live demo:** disconnect Tailscale on stage → agent detects → fixes → ElevenLabs voice confirms it's back
- **Pitch:** *"PagerDuty costs $500/month. This is a `SKILL.md`."*
- **Key innovation:** Emergent monitoring — configures itself from real failures, not upfront configuration

---

## License

<img src="https://img.shields.io/badge/license-MIT-22C55E?style=flat-square&labelColor=111318" />

MIT — use it, fork it, deploy it.
