# Boomi Installers

Scripts for installing, autostarting, and managing a Boomi Runtime (Atom) as a background service on Linux and macOS.

## Contents

| File | Platform | Purpose |
|---|---|---|
| [`linux-systemd-installer/`](linux-systemd-installer/) | Linux (systemd) | Folder containing the systemd service installer and its own [README](linux-systemd-installer/README.md) |
| [`linux-systemd-installer/install-boomi-systemd.sh`](linux-systemd-installer/install-boomi-systemd.sh) | Linux (systemd) | Generates a `systemd` unit file for an existing Boomi runtime and enables it to start on boot. Run with `sudo ./install-boomi-systemd.sh -u <user> -p <runtime_path>`. |
| [`macos-launchd-autostart.sh`](macos-launchd-autostart.sh) | macOS (launchd) | The launchd equivalent of the systemd installer above. Interactively installs, updates, or removes a `LaunchDaemon` (`com.boomi.runtime`) that starts an existing local runtime on boot. Run with `./macos-launchd-autostart.sh` (uses `sudo` internally for privileged steps). |
| [`restart-boomi-systemd.sh`](restart-boomi-systemd.sh) | Linux (systemd) | Gracefully restarts an already-installed Boomi systemd service: stops it via `systemctl`, falls back to `./atom stop`/`./atom start` if the service doesn't respond, verifies status, and logs each step to `restart<LOCALHOST_ID>.log`. Intended to be run from the runtime's install directory. |

## Which script do I need?

- **First-time install on Linux**, running as a systemd service → [`linux-systemd-installer/install-boomi-systemd.sh`](linux-systemd-installer/install-boomi-systemd.sh)
- **First-time autostart setup on macOS** → [`macos-launchd-autostart.sh`](macos-launchd-autostart.sh)
- **Restarting an existing Linux systemd install** (e.g. from a maintenance job) → [`restart-boomi-systemd.sh`](restart-boomi-systemd.sh)

All scripts assume the Boomi runtime itself is already installed locally (i.e. `<runtime_path>/bin/atom` exists) — none of them install the runtime software, only the service/autostart wiring around it.
