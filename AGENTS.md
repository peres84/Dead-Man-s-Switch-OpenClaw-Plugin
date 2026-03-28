# AGENTS.md — Dead Man's Switch

Instructions for AI agents (Claude Code, Cursor, Copilot, etc.) assisting with
this plugin. Read this before making any changes or running any install commands.

---

## What This Repo Is

`deadmans-switch` is an OpenClaw plugin that turns OpenClaw into a
self-healing infrastructure guardian. It monitors Tailscale, nginx, disk, and
arbitrary systemd services — autonomously diagnosing and fixing failures.

**Runtime:** Node.js ESM · TypeScript · Linux only (Ubuntu 22.04 / 24.04)

**Important:** The `package.json` `name` field must be `deadmans-switch` (not
`openclaw-deadmans-switch`) — this must match the `id` in
`openclaw.plugin.json`. A mismatch causes the gateway to reject the plugin with
a "plugin id mismatch" error.

---

## Publishing to ClawHub

> Do this from the **development machine** (not the VPS) after making changes.

### Step 1 — Authenticate

```bash
clawhub login
```

### Step 2 — Publish the skill

ClawHub publishes **skill folders** (directories containing a `SKILL.md`), not
the entire repo root. You must pass the absolute path to the skill directory:

```bash
clawhub publish "$(pwd)/skills/deadmans-switch" \
  --slug deadmans-switch \
  --name "Dead Man's Switch" \
  --version 0.1.0 \
  --tags latest,monitoring,infrastructure,self-healing,linux
```

> **Note:** Publishing from `.` (the repo root) will fail with
> `Error: SKILL.md required` because the root directory does not contain a
> `SKILL.md`. Always point to the skill subdirectory.

### Step 3 — Verify it's live

```bash
clawhub search deadmans-switch
```

### Publishing an update

Bump the version in `package.json` and `openclaw.plugin.json` first, then:

```bash
clawhub publish "$(pwd)/skills/deadmans-switch" \
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

### Step 2 — Install the skill from ClawHub

```bash
clawhub install deadmans-switch --force
```

> **Note:** VirusTotal may flag this skill as "suspicious" due to sudo commands
> and API key references in the playbooks. The `--force` flag is required for
> non-interactive installs. Review the code before using `--force`.

The skill is installed to `~/.openclaw/workspace/skills/deadmans-switch/`.

### Step 3 — Clone the repo for the full plugin (scripts + index.ts)

ClawHub only publishes the **skill folder** (SKILL.md + playbooks). The full
plugin (index.ts, install.sh, recovery scripts) must come from the git repo:

```bash
git clone https://github.com/your-user/Dead-Man-s-Switch-OpenClaw-Plugin.git
cd Dead-Man-s-Switch-OpenClaw-Plugin
npm install
```

### Step 4 — Run the installer (requires sudo)

```bash
bash install.sh
```

This must be run in a terminal with sudo access (not from within Claude Code's
sandbox). What it does:

- Copies `scripts/*.sh` → `/usr/local/bin/openclaw-skills/` with `chmod +x`
- Writes `/etc/sudoers.d/openclaw-skills` with NOPASSWD rules
- Validates sudoers syntax with `visudo -c`
- Copies skills to `~/.openclaw/skills/`
- Creates `~/.openclaw/dms-fix-log.jsonl`

### Step 5 — Register the plugin with OpenClaw

```bash
openclaw plugins install /path/to/Dead-Man-s-Switch-OpenClaw-Plugin --link
```

> **Important:** Use `--link` to symlink the local directory instead of copying.
> This way, `git pull` updates are reflected without re-installing.

### Step 6 — Configure

Edit `~/.openclaw/openclaw.json`. Plugin config keys go inside a `config`
sub-object under the plugin entry:

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

> **Warning:** Do NOT put config keys (`elevenLabsApiKey`, etc.) directly under
> the plugin entry — they must be inside the `config` object. Unrecognized
> top-level keys cause the gateway to reject the config on startup.

### Step 7 — Restart the gateway

```bash
# If running as systemd service:
systemctl --user restart openclaw-gateway.service

# Or via CLI:
openclaw gateway restart
```

### Step 8 — Verify

```bash
# Check plugin is loaded (should show "loaded" status)
openclaw plugins list

# Check fix log exists
ls -la ~/.openclaw/dms-fix-log.jsonl

# Check scripts are in place
ls /usr/local/bin/openclaw-skills/

# Check sudoers
sudo cat /etc/sudoers.d/openclaw-skills

# Test the skill — tell your agent:
#   "check my services"
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

> **Required dependency:** `@sinclair/typebox` — used by `index.ts` for tool
> parameter schemas. This is installed automatically by `npm install`.

### Step 3 — Run the installer (requires sudo)

This script is idempotent — safe to run multiple times. Must be run in a
terminal with sudo access:

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

Link the local directory as a plugin:

```bash
openclaw plugins install /path/to/Dead-Man-s-Switch-OpenClaw-Plugin --link
```

This registers the plugin and adds the path to `plugins.load.paths` in
`openclaw.json`.

### Step 5 — Configure

Add to `~/.openclaw/openclaw.json` under `plugins.entries`. Config keys must go
inside a `config` sub-object:

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

### Step 6 — Restart the gateway

```bash
systemctl --user restart openclaw-gateway.service
```

### Step 7 — Verify

```bash
# Plugin loaded (look for "deadmans-switch" with "loaded" status)
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

## Troubleshooting

### "SKILL.md required" when publishing to ClawHub

ClawHub publishes **skill folders**, not entire repos. Use the absolute path to
the skill directory:

```bash
clawhub publish "$(pwd)/skills/deadmans-switch" --slug deadmans-switch ...
```

### "plugin id mismatch" on gateway startup

The `name` in `package.json` must exactly match the `id` in
`openclaw.plugin.json`. Both must be `deadmans-switch`.

### "Unrecognized keys" in config

Plugin config keys (`elevenLabsApiKey`, `tavilyApiKey`, etc.) must be nested
inside a `config` sub-object under `plugins.entries.deadmans-switch`, not at the
top level. See the Configuration section above.

### "Cannot find module '@sinclair/typebox'"

Run `npm install` in the plugin directory. This dependency is required by
`index.ts` for tool parameter schemas.

### "sudo: a terminal is required" during install.sh

`install.sh` requires an interactive terminal with sudo access. Run it directly
in your terminal session, not from within a sandboxed agent environment.

### VirusTotal flags the skill as suspicious

This is expected — the skill contains sudo commands, API key references, and
shell script execution patterns. Use `--force` with `clawhub install` after
reviewing the code.

### Gateway shows "plugin not found" after install

Ensure you used `openclaw plugins install <path> --link` (not `clawhub install`
alone). ClawHub only installs the skill (SKILL.md + playbooks). The full plugin
registration requires `openclaw plugins install` pointed at the repo directory.

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
