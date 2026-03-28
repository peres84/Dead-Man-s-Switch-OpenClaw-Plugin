#!/bin/bash
# install.sh
# One-shot installer for Dead Man's Switch — OpenClaw Plugin
#
# What this does:
#   1. Creates /usr/local/bin/openclaw-skills/ and copies all scripts
#   2. Installs sudoers rules for privilege escalation
#   3. Installs skills to ~/.openclaw/skills/
#   4. Creates the fix log file at ~/.openclaw/dms-fix-log.jsonl
#
# This script is idempotent — safe to run multiple times.

set -e

BOLD="\033[1m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
RESET="\033[0m"

log()   { echo -e "${BOLD}$*${RESET}"; }
ok()    { echo -e "${GREEN}✅ $*${RESET}"; }
warn()  { echo -e "${YELLOW}⚠️  $*${RESET}"; }
error() { echo -e "${RED}❌ $*${RESET}" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_INSTALL_DIR="$HOME/.openclaw/skills"
SCRIPTS_DEST="/usr/local/bin/openclaw-skills"
SUDOERS_FILE="/etc/sudoers.d/openclaw-skills"
FIX_LOG="$HOME/.openclaw/dms-fix-log.jsonl"
CURRENT_USER=$(whoami)

echo ""
log "🦞 Dead Man's Switch — OpenClaw Plugin Installer"
echo ""

# Verify running in project directory
if [ ! -f "$SCRIPT_DIR/openclaw.plugin.json" ]; then
    error "Must be run from the plugin directory (openclaw.plugin.json not found)"
fi

# Verify scripts exist
if [ ! -d "$SCRIPT_DIR/scripts" ]; then
    error "scripts/ directory not found in $SCRIPT_DIR"
fi

# Step 1: Create scripts directory
log "Step 1: Installing recovery scripts to $SCRIPTS_DEST"
sudo mkdir -p "$SCRIPTS_DEST"
sudo cp "$SCRIPT_DIR/scripts/tailscale-funnel-start.sh" "$SCRIPTS_DEST/"
sudo cp "$SCRIPT_DIR/scripts/nginx-check.sh" "$SCRIPTS_DEST/"
sudo cp "$SCRIPT_DIR/scripts/disk-cleanup.sh" "$SCRIPTS_DEST/"
sudo cp "$SCRIPT_DIR/scripts/process-restart.sh" "$SCRIPTS_DEST/"
sudo chmod +x "$SCRIPTS_DEST/tailscale-funnel-start.sh"
sudo chmod +x "$SCRIPTS_DEST/nginx-check.sh"
sudo chmod +x "$SCRIPTS_DEST/disk-cleanup.sh"
sudo chmod +x "$SCRIPTS_DEST/process-restart.sh"
ok "Scripts installed to $SCRIPTS_DEST"

# Step 2: Install sudoers rules
log "Step 2: Installing sudoers rules for $CURRENT_USER"

# Validate each script exists before writing sudoers
for script in tailscale-funnel-start.sh nginx-check.sh disk-cleanup.sh process-restart.sh; do
    if [ ! -f "$SCRIPTS_DEST/$script" ]; then
        error "Expected script not found: $SCRIPTS_DEST/$script"
    fi
done

sudo tee "$SUDOERS_FILE" > /dev/null <<EOF
# Dead Man's Switch — OpenClaw Plugin
# Allows the openclaw agent user to run recovery scripts without a password
$CURRENT_USER ALL=(root) NOPASSWD: $SCRIPTS_DEST/tailscale-funnel-start.sh
$CURRENT_USER ALL=(root) NOPASSWD: $SCRIPTS_DEST/nginx-check.sh
$CURRENT_USER ALL=(root) NOPASSWD: $SCRIPTS_DEST/disk-cleanup.sh
$CURRENT_USER ALL=(root) NOPASSWD: $SCRIPTS_DEST/process-restart.sh
EOF

sudo chmod 440 "$SUDOERS_FILE"

# Validate sudoers file syntax
if ! sudo visudo -c -f "$SUDOERS_FILE" >/dev/null 2>&1; then
    warn "Sudoers file failed validation — removing to prevent lockout"
    sudo rm -f "$SUDOERS_FILE"
    error "Sudoers syntax check failed — installation aborted"
fi

ok "Sudoers rules installed at $SUDOERS_FILE"

# Step 3: Install skills to shared OpenClaw skills directory
log "Step 3: Installing skills to $SKILLS_INSTALL_DIR"
mkdir -p "$SKILLS_INSTALL_DIR"

if [ -d "$SKILLS_INSTALL_DIR/deadmans-switch" ]; then
    warn "Existing deadmans-switch skill found — updating in place"
    rm -rf "$SKILLS_INSTALL_DIR/deadmans-switch"
fi

cp -r "$SCRIPT_DIR/skills/deadmans-switch" "$SKILLS_INSTALL_DIR/"
ok "Skills installed to $SKILLS_INSTALL_DIR/deadmans-switch"

# Step 4: Create fix log file and openclaw config directory
log "Step 4: Creating fix log at $FIX_LOG"
mkdir -p "$HOME/.openclaw"
touch "$FIX_LOG"
ok "Fix log ready at $FIX_LOG"

# Step 5: Print verification
echo ""
log "=== Installation Verification ==="
echo ""
echo "Scripts:"
ls -la "$SCRIPTS_DEST/" | grep "\.sh$" | awk '{print "  " $1 " " $NF}'
echo ""
echo "Sudoers:"
sudo cat "$SUDOERS_FILE"
echo ""
echo "Skills:"
ls "$SKILLS_INSTALL_DIR/deadmans-switch/"
echo ""

echo ""
ok "Installation complete!"
echo ""
log "Next steps:"
echo "  1. openclaw plugins install openclaw-deadmans-switch"
echo "  2. Add your API keys to openclaw.json:"
echo ""
echo '     {
       "plugins": {
         "deadmans-switch": {
           "elevenLabsApiKey": "sk-...",
           "tavilyApiKey": "tvly-...",
           "websites": ["https://your-site.com", "https://your-other-site.com"],
           "services": ["tailscale", "nginx"]
         }
       }
     }'
echo ""
echo "  3. openclaw gateway restart"
echo "  4. Test: tell your agent 'check my services'"
echo ""
log "For the live demo: disconnect Tailscale → agent detects → fixes → ElevenLabs confirms 🦞"
echo ""
