# AGENTS.md — Dead Man's Switch

Instructions for AI agents (Claude Code, Cursor, Copilot, etc.) assisting with
this plugin. Read this before making any changes or running any install commands.

---

## What This Repo Is

`openclaw-deadmans-switch` is an OpenClaw plugin that turns OpenClaw into a
self-healing infrastructure guardian. It monitors Tailscale, nginx, disk, and
arbitrary systemd services — autonomously diagnosing and fixing failures.

**Runtime:** Node.js ESM · TypeScript · Linux only (Ubuntu 22.04 / 24.04)

---

## Publishing to ClawHub

> Do this from the **development machine** (not the VPS) after making changes.

### Step 1 — Authenticate

```bash
clawhub login
```

### Step 2 — Publish the full plugin

Run from the repo root. The `openclaw.plugin.json` manifest tells ClawHub what
to bundle.

```bash
clawhub publish . \
  --slug deadmans-switch \
  --name "Dead Man's Switch" \
  --version 0.1.0 \
  --tags latest,monitoring,infrastructure,self-healing,linux
```

### Step 3 — Verify it's live

```bash
clawhub search deadmans-switch
```

### Publishing an update

Bump the version in `package.json` and `openclaw.plugin.json` first, then:

```bash
clawhub publish . \
  --slug deadmans-switch \
  --name "Dead Man's Switch" \
  --version 0.1.1 \
  --changelog "Describe what changed" \
  --tags latest
```

---

## Installing on the VPS — Method A: ClawHub

> Use this when the plugin has already been published to ClawHub.
> Run all commands as the OpenClaw user on the VPS (not root).

### Step 1 — Authenticate with ClawHub

```bash
clawhub login
```

### Step 2 — Install the plugin

```bash
openclaw plugins install deadmans-switch
```

This pulls the full bundle (skills, scripts, hooks, index.ts) from ClawHub and
registers the plugin with the local OpenClaw gateway.

### Step 3 — Run the post-install script

The ClawHub install does not set up sudoers or copy scripts to
`/usr/local/bin/openclaw-skills/`. Run this after:

```bash
# From wherever openclaw installed the plugin, usually:
cd ~/.openclaw/plugins/deadmans-switch
bash install.sh
```

If you cannot find the install path:

```bash
find ~/.openclaw/plugins -name "install.sh" | head -5
```

### Step 4 — Configure

Edit `~/.openclaw/openclaw.json` (or wherever your OpenClaw config lives):

```json
{
  "plugins": {
    "deadmans-switch": {
      "elevenLabsApiKey": "sk-your-key-here",
      "tavilyApiKey": "tvly-your-key-here",
      "websites": [
        "https://your-site.com",
        "https://your-other-site.com"
      ],
      "services": ["tailscale", "nginx"],
      "notifyChannel": "telegram"
    }
  }
}
```

### Step 5 — Restart the gateway

```bash
openclaw gateway restart
```

### Step 6 — Verify

```bash
# Check plugin is loaded
openclaw plugins list

# Check fix log exists
ls -la ~/.openclaw/dms-fix-log.jsonl

# Check scripts are in place
ls /usr/local/bin/openclaw-skills/

# Check sudoers
sudo cat /etc/sudoers.d/openclaw-skills

# Test the skill
# Tell your agent: "check my services"
```

---

## Installing on the VPS — Method B: GitHub Clone

> Use this when ClawHub is unavailable or you want to run from source.
> Run all commands as the OpenClaw user on the VPS (not root).

### Step 1 — Clone the repo

```bash
git clone https://github.com/youruser/openclaw-deadmans-switch.git
cd openclaw-deadmans-switch
```

### Step 2 — Install Node dependencies

```bash
npm install
```

### Step 3 — Run the installer

This script is idempotent — safe to run multiple times.

```bash
bash install.sh
```

What `install.sh` does:
- Copies `scripts/*.sh` → `/usr/local/bin/openclaw-skills/` with `chmod +x`
- Writes `/etc/sudoers.d/openclaw-skills` with NOPASSWD rules for each script
- Validates sudoers syntax with `visudo -c` (aborts if invalid — prevents lockout)
- Copies `skills/deadmans-switch/` → `~/.openclaw/skills/`
- Creates `~/.openclaw/dms-fix-log.jsonl` if it does not exist

### Step 4 — Register with OpenClaw

```bash
openclaw plugins install ./
```

Or if OpenClaw reads from a local path config, add to `openclaw.json`:

```json
{
  "plugins": {
    "deadmans-switch": {
      "localPath": "/path/to/openclaw-deadmans-switch"
    }
  }
}
```

### Step 5 — Configure

```json
{
  "plugins": {
    "deadmans-switch": {
      "elevenLabsApiKey": "sk-your-key-here",
      "tavilyApiKey": "tvly-your-key-here",
      "websites": [
        "https://your-site.com",
        "https://your-other-site.com"
      ],
      "services": ["tailscale", "nginx"],
      "notifyChannel": "telegram"
    }
  }
}
```

### Step 6 — Restart the gateway

```bash
openclaw gateway restart
```

### Step 7 — Verify

```bash
# Plugin loaded
openclaw plugins list

# Scripts in place
ls /usr/local/bin/openclaw-skills/

# Sudoers valid
sudo visudo -c
sudo cat /etc/sudoers.d/openclaw-skills

# Fix log exists
cat ~/.openclaw/dms-fix-log.jsonl

# Manual test — run the Tailscale check script directly
sudo /usr/local/bin/openclaw-skills/tailscale-funnel-start.sh
```

---

## Updating (Method B — GitHub)

```bash
cd openclaw-deadmans-switch
git pull
npm install
bash install.sh          # re-copies scripts and skills
openclaw gateway restart
```

---

## Uninstalling

```bash
# Remove scripts
sudo rm -rf /usr/local/bin/openclaw-skills/

# Remove sudoers rules
sudo rm -f /etc/sudoers.d/openclaw-skills

# Remove skills
rm -rf ~/.openclaw/skills/deadmans-switch

# Unregister plugin
openclaw plugins uninstall deadmans-switch

# Restart gateway
openclaw gateway restart

# Optional: remove fix log (contains incident history — keep if useful)
# rm ~/.openclaw/dms-fix-log.jsonl
```

---

## Key Files to Know

| File | Purpose |
|------|---------|
| `openclaw.plugin.json` | Plugin manifest — id, version, icon, configSchema |
| `index.ts` | Registers `dms_recover`, `dms_status` tools + startup hook |
| `install.sh` | One-shot setup: scripts, sudoers, skills, fix log |
| `skills/deadmans-switch/SKILL.md` | Agent decision logic — the "brain" |
| `skills/deadmans-switch/playbooks/*.md` | Per-service recovery procedures |
| `scripts/*.sh` | Privileged shell scripts run via sudoers |
| `hooks/startup-watchdog/handler.ts` | On gateway boot: audit fix log, alert on patterns |
| `~/.openclaw/dms-fix-log.jsonl` | Append-only incident log (lives on the VPS) |

---

## Constraints — Do Not Violate These

1. **Never delete entries from `dms-fix-log.jsonl`** — it is append-only by design
2. **Never create cron jobs preemptively** — only when 2+ failures detected in 24h
3. **Always check Tailscale before nginx** — tunnel down makes all sites appear broken
4. **Always run `nginx -t` before `nginx -s reload`** — never reload a broken config
5. **Scripts must stay in `/usr/local/bin/openclaw-skills/`** — sudoers rules point there
6. **Playbooks are living documents** — append new fixes after learning via Tavily

---

## System Requirements on the VPS

| Requirement | Check |
|-------------|-------|
| Ubuntu 22.04 or 24.04 | `lsb_release -a` |
| Node.js ≥ 18 | `node --version` |
| `tailscale` in PATH | `which tailscale` |
| `nginx` installed | `which nginx` |
| `curl` installed | `which curl` |
| `systemctl` available | `which systemctl` |
| OpenClaw installed and gateway running | `openclaw gateway status` |
