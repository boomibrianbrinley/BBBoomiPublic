#!/bin/bash
#
# boomi_runtime_autostart_macos.sh
#
# Sets up (or removes) a launchd LaunchDaemon that starts an EXISTING
# local Boomi runtime automatically on macOS boot. This does not install
# the Boomi runtime itself - it assumes you've already installed it and
# just wires its start command into launchd, the launchd equivalent of
# `systemctl enable` for a systemd service.
#
# Usage:
#   ./boomi_runtime_autostart_macos.sh
#
# If no autostart daemon is currently configured, you'll be walked
# through setting one up. If one already exists, you'll be asked
# whether to update it (new path/user) or remove it.
#
# Uses `sudo` internally for the privileged steps (writing to
# /Library/LaunchDaemons and loading/unloading the daemon), so run this
# as your normal user - macOS will prompt for your password when needed.

set -euo pipefail

LABEL="com.boomi.runtime"
PLIST_PATH="/Library/LaunchDaemons/${LABEL}.plist"

echo "Boomi Local Runtime - macOS autostart setup (launchd)"
echo "--------------------------------------------------------"

# -------------------------------------------------------------------------
# Helpers
# -------------------------------------------------------------------------

is_installed() {
    [[ -f "$PLIST_PATH" ]]
}

show_current_config() {
    echo ""
    echo "Existing autostart entry found at $PLIST_PATH:"
    # Pull a couple of key values out of the existing plist for display.
    /usr/libexec/PlistBuddy -c "Print :ProgramArguments:0" "$PLIST_PATH" 2>/dev/null | sed 's/^/  Runtime script : /' || true
    /usr/libexec/PlistBuddy -c "Print :UserName" "$PLIST_PATH" 2>/dev/null | sed 's/^/  Run as user    : /' || true
    echo ""
    echo "Current status:"
    sudo launchctl list | grep "$LABEL" || echo "  (not currently loaded)"
}

do_uninstall() {
    if ! is_installed; then
        echo "No autostart entry found at $PLIST_PATH. Nothing to do."
        return
    fi
    echo ""
    echo "Unloading and removing $LABEL..."
    sudo launchctl unload "$PLIST_PATH" 2>/dev/null || true
    sudo rm -f "$PLIST_PATH"
    echo "Done. The runtime will no longer start automatically on boot."
    echo "Note: this does not stop a currently running runtime process -"
    echo "use your runtime's bin/atom stop command for that if needed."
}

do_install() {
    # --- Prompt for the runtime install path ------------------------------
    read -r -p "Enter the full path to your existing Boomi runtime install directory: " RUNTIME_DIR

    # Expand a leading ~ if the user typed one
    RUNTIME_DIR="${RUNTIME_DIR/#\~/$HOME}"
    # Strip a trailing slash, if any
    RUNTIME_DIR="${RUNTIME_DIR%/}"

    if [[ -z "$RUNTIME_DIR" ]]; then
        echo "Error: no path entered." >&2
        exit 1
    fi

    if [[ ! -d "$RUNTIME_DIR" ]]; then
        echo "Error: '$RUNTIME_DIR' is not a directory." >&2
        exit 1
    fi

    ATOM_BIN="$RUNTIME_DIR/bin/atom"

    if [[ ! -x "$ATOM_BIN" ]]; then
        echo "Error: control script not found or not executable at:" >&2
        echo "  $ATOM_BIN" >&2
        echo "This should point at an existing Boomi runtime install. Check the path and try again." >&2
        exit 1
    fi

    # --- Determine which user the daemon should run as ---------------------
    if [[ -n "${SUDO_USER:-}" ]]; then
        RUN_USER="$SUDO_USER"
    else
        RUN_USER="$(whoami)"
    fi

    echo ""
    echo "Runtime directory  : $RUNTIME_DIR"
    echo "Control script     : $ATOM_BIN"
    echo "Run as user        : $RUN_USER"
    echo "LaunchDaemon label : $LABEL"
    echo "Plist destination  : $PLIST_PATH"
    echo ""
    read -r -p "Proceed? [y/N] " CONFIRM
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 0
    fi

    # --- Prepare log directory ---------------------------------------------
    LOG_DIR="$RUNTIME_DIR/logs"
    mkdir -p "$LOG_DIR"
    STDOUT_LOG="$LOG_DIR/launchd.out.log"
    STDERR_LOG="$LOG_DIR/launchd.err.log"

    # --- Generate the plist --------------------------------------------------
    TMP_PLIST="$(mktemp)"

    cat > "$TMP_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${LABEL}</string>

    <key>ProgramArguments</key>
    <array>
        <string>${ATOM_BIN}</string>
        <string>console</string>
    </array>

    <key>WorkingDirectory</key>
    <string>${RUNTIME_DIR}</string>

    <key>UserName</key>
    <string>${RUN_USER}</string>

    <key>RunAtLoad</key>
    <true/>

    <key>KeepAlive</key>
    <true/>

    <key>StandardOutPath</key>
    <string>${STDOUT_LOG}</string>

    <key>StandardErrorPath</key>
    <string>${STDERR_LOG}</string>
</dict>
</plist>
EOF

    # --- Install the plist (privileged) -------------------------------------
    echo ""
    echo "Installing autostart entry (you may be prompted for your password)..."

    if sudo launchctl list | grep -q "$LABEL"; then
        echo "Existing entry found, unloading before update..."
        sudo launchctl unload "$PLIST_PATH" 2>/dev/null || true
    fi

    sudo cp "$TMP_PLIST" "$PLIST_PATH"
    sudo chown root:wheel "$PLIST_PATH"
    sudo chmod 644 "$PLIST_PATH"
    rm -f "$TMP_PLIST"

    sudo launchctl load -w "$PLIST_PATH"

    echo ""
    echo "Installed and loaded. Verifying..."
    sleep 2
    sudo launchctl list | grep "$LABEL" || echo "Warning: entry not showing in launchctl list yet - check logs."

    echo ""
    echo "Done. The runtime will now start automatically on boot."
    echo "Logs:"
    echo "  stdout: $STDOUT_LOG"
    echo "  stderr: $STDERR_LOG"
    echo ""
    echo "Useful commands:"
    echo "  sudo launchctl list | grep $LABEL     # check status"
    echo "  sudo launchctl unload $PLIST_PATH     # stop + unload"
    echo "  sudo launchctl load -w $PLIST_PATH    # (re)load"
}

# -------------------------------------------------------------------------
# Main
# -------------------------------------------------------------------------

if is_installed; then
    show_current_config
    echo ""
    echo "What would you like to do?"
    echo "  [U]pdate  - point the autostart entry at a new path/user and reload it"
    echo "  [R]emove  - remove the autostart entry (stop launching on boot)"
    echo "  [C]ancel  - exit without changes"
    read -r -p "Choice [U/R/C]: " ACTION
    case "$ACTION" in
        [Uu]*) do_install ;;
        [Rr]*) do_uninstall ;;
        *) echo "No changes made." ; exit 0 ;;
    esac
else
    echo "No existing autostart entry found - setting one up."
    do_install
fi
