# Troubleshooting — Dead Man's Switch

Common issues encountered during publishing, installation, and operation.

---

## Publishing to ClawHub

### "SKILL.md required" error

ClawHub publishes **skill folders** (directories containing a `SKILL.md`), not
entire repos. Always use the absolute path to the skill subdirectory:

```bash
# Wrong — fails because repo root has no SKILL.md
clawhub publish .

# Correct
clawhub publish "$(pwd)/skills/deadmans-switch" --slug deadmans-switch ...
```

### VirusTotal flags skill as suspicious

Expected behavior. The skill contains sudo commands, API key placeholders, and
shell script execution patterns. Use `--force` after reviewing the code:

```bash
clawhub install deadmans-switch --force
```

---

## Plugin Installation

### "plugin id mismatch" on gateway startup

The `name` field in `package.json` must exactly match the `id` field in
`openclaw.plugin.json`. Both must be `deadmans-switch`.

```
# Error message:
plugin id mismatch (manifest uses "deadmans-switch", entry hints "openclaw-deadmans-switch")
```

**Fix:** Set `"name": "deadmans-switch"` in `package.json`.

### "Cannot find module '@sinclair/typebox'"

The `index.ts` file requires `@sinclair/typebox` for tool parameter schemas.

**Fix:** Run `npm install` in the plugin directory.

### "Unrecognized keys" in config — gateway refuses to start

Plugin config keys (`elevenLabsApiKey`, `tavilyApiKey`, `services`, `websites`)
must be nested inside a `config` sub-object. Putting them at the top level of
the plugin entry causes a validation error.

```json
// Wrong — gateway rejects this:
{
  "plugins": {
    "entries": {
      "deadmans-switch": {
        "enabled": true,
        "elevenLabsApiKey": "..."
      }
    }
  }
}

// Correct:
{
  "plugins": {
    "entries": {
      "deadmans-switch": {
        "enabled": true,
        "config": {
          "elevenLabsApiKey": "...",
          "tavilyApiKey": "...",
          "services": ["tailscale", "nginx"],
          "websites": []
        }
      }
    }
  }
}
```

### "plugin not found: deadmans-switch" after `clawhub install`

ClawHub only installs the **skill** (SKILL.md + playbooks). The full plugin
(index.ts, tools, hooks) must be registered separately:

```bash
openclaw plugins install /path/to/Dead-Man-s-Switch-OpenClaw-Plugin --link
```

The `--link` flag symlinks the directory so `git pull` updates are reflected
without re-installing.

### "sudo: a terminal is required" during install.sh

The `install.sh` script requires an interactive terminal with sudo access. It
cannot run from within a sandboxed agent environment (e.g., Claude Code sandbox).

**Fix:** Run `bash install.sh` directly in your terminal session.

---

## Gateway Issues

### "plugins.allow is empty" warning

This is a non-blocking warning. The gateway auto-loads discovered plugins but
recommends explicitly listing trusted plugin IDs. To suppress:

```json
{
  "plugins": {
    "allow": ["deadmans-switch"]
  }
}
```

### "Skipping skill path that resolves outside its configured root"

Appears when skills reference paths outside their install directory. This is a
warning, not an error — the plugin still loads.

### Gateway token mismatch — CLI commands fail with "unauthorized"

**Symptom:** Commands like `openclaw cron list` fail with:

```
gateway token mismatch (set gateway.remote.token to match gateway.auth.token)
```

Meanwhile, `openclaw gateway status` and `openclaw gateway probe` work fine
(they use a different auth path — RPC probe, not WebSocket token auth).

**What we tried (none resolved it):**

1. Setting `gateway.remote.token` to match `gateway.auth.token` via
   `openclaw config set` — both values confirmed identical in config
2. Regenerating both tokens with `openssl rand -hex 24` and setting both
3. Reinstalling the gateway service with `openclaw gateway install --force --token <token>`
4. Running `openclaw doctor --fix`
5. Running the gateway in foreground with explicit `--token` flag

**Root cause (suspected):** The gateway may regenerate or derive an internal
token at startup that differs from the config file value, or the CLI sends the
token through a code path that doesn't match the gateway's expectation. The
`probe` and `status` commands use a separate RPC mechanism that bypasses token
auth, which is why they succeed.

**Impact on the plugin:** Low. The cron system runs inside the gateway process
and works via the internal API. The `openclaw cron list` CLI command is affected,
but cron jobs created by the agent through the gateway session work normally.

**Workaround:** Manage crons through the agent (e.g., "list my cron jobs") or
check the cron store file directly:

```bash
cat ~/.openclaw/cron/jobs.json
```

**If the issue persists,** try:

```bash
# Full service reinstall
openclaw gateway uninstall
openclaw gateway install --force --port 18789
systemctl --user restart openclaw-gateway.service

# Or reset everything
openclaw doctor --fix
```

This may be a pre-existing issue or an OpenClaw bug. Consider reporting it at
the OpenClaw community or issue tracker.

---

## Cron Jobs

### How crons work in this plugin

The plugin does **not** create cron jobs automatically. It **suggests** cron
commands after detecting recurring failures (same service failing 2+ times in
24 hours). There are two trigger points:

1. **`dms_recover` tool** — after a successful recovery, checks fix log history
2. **`gateway:startup` hook** — on every gateway boot, audits the fix log

The suggested command uses OpenClaw's built-in cron system (not system crontab):

```bash
openclaw cron add \
  --name "DMS: tailscale Monitor" \
  --cron "*/5 * * * *" \
  --session isolated \
  --message "Dead Man's Switch: check tailscale. If issue found, fix it."
```

### Validating cron jobs

```bash
# List all cron jobs (requires working gateway token auth — see above)
openclaw cron list

# Or check the store file directly
cat ~/.openclaw/cron/jobs.json

# View run history for a specific job
openclaw cron runs --id <jobId>
```

### No crons exist yet

This is normal. Crons are only suggested after real failures are logged. Until
a service fails 2+ times in 24 hours, no cron will be suggested.

---

## Fix Log

### Location

```
~/.openclaw/dms-fix-log.jsonl
```

### Checking it

```bash
# View all entries
cat ~/.openclaw/dms-fix-log.jsonl

# Count entries per service
cat ~/.openclaw/dms-fix-log.jsonl | jq -r '.service' | sort | uniq -c

# View last 5 entries
tail -5 ~/.openclaw/dms-fix-log.jsonl | jq .
```

### Fix log is empty

Normal if no incidents have occurred. The agent writes to the fix log only after
executing a recovery action via the `dms_recover` tool.
