#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  sudo ./install_boomi_systemd.sh -u <user> -p <boomi_runtime_path> [-g <group>] [-s <service_name>]

Required:
  -u  Linux user to run the service (matches "User=" in unit)
  -p  Boomi runtime path (the folder that contains bin/atom)
      Example: /opt/boomi/runtime

Optional:
  -g  Linux group to run the service (matches "Group=" in unit). Default: same as -u
  -s  Service name (unit filename). Default: boomi  -> /etc/systemd/system/boomi.service

Examples:
  sudo ./install_boomi_systemd.sh -u boomi -p /opt/boomi/runtime
  sudo ./install_boomi_systemd.sh -u boomi -g boomi -p /opt/boomi/runtime -s boomi
EOF
}

SERVICE_NAME="boomi"
BOOMI_USER=""
BOOMI_GROUP=""
RUNTIME_PATH=""

while getopts ":u:g:p:s:h" opt; do
  case "$opt" in
    u) BOOMI_USER="$OPTARG" ;;
    g) BOOMI_GROUP="$OPTARG" ;;
    p) RUNTIME_PATH="$OPTARG" ;;
    s) SERVICE_NAME="$OPTARG" ;;
    h) usage; exit 0 ;;
    \?) echo "Unknown option: -$OPTARG" >&2; usage; exit 2 ;;
    :)  echo "Missing argument for -$OPTARG" >&2; usage; exit 2 ;;
  esac
done

if [[ -z "${BOOMI_USER}" || -z "${RUNTIME_PATH}" ]]; then
  echo "ERROR: -u <user> and -p <boomi_runtime_path> are required." >&2
  usage
  exit 2
fi

if [[ $EUID -ne 0 ]]; then
  echo "ERROR: Must be run as root (use sudo)." >&2
  exit 1
fi

if [[ -z "${BOOMI_GROUP}" ]]; then
  BOOMI_GROUP="${BOOMI_USER}"
fi

# Normalize runtime path
RUNTIME_PATH="${RUNTIME_PATH%/}"
ATOM_BIN="${RUNTIME_PATH}/bin/atom"

# Validate user/group exist
if ! id -u "${BOOMI_USER}" >/dev/null 2>&1; then
  echo "ERROR: User '${BOOMI_USER}' does not exist." >&2
  exit 1
fi
if ! getent group "${BOOMI_GROUP}" >/dev/null 2>&1; then
  echo "ERROR: Group '${BOOMI_GROUP}' does not exist." >&2
  exit 1
fi

if [[ ! -x "${ATOM_BIN}" ]]; then
  echo "WARNING: '${ATOM_BIN}' not found or not executable yet." >&2
  echo "         The service file will be created, but start may fail until it exists." >&2
fi

UNIT_PATH="/etc/systemd/system/${SERVICE_NAME}.service"

echo "Writing systemd unit to: ${UNIT_PATH}"

cat > "${UNIT_PATH}" <<EOF
[Unit]
Documentation=man:systemd-sysv-generator(8)
Description=LSB: Boomi Clustered Runtime
After=local-fs.target network.target remote-fs.target nss-lookup.target ntpd.service
# For AWS based clusters using EFS mounts use this instead:
# After=efs.mount local-fs.target network.target remote-fs.target nss-lookup.target ntpd.service
Conflicts=shutdown.target

[Service]
LimitNOFILE=65536
LimitNPROC=65536
# Type=forking
Type=simple
Restart=always
TimeoutSec=5min
IgnoreSIGPIPE=no
KillMode=process
GuessMainPID=yes
RemainAfterExit=yes
ExecStart=${ATOM_BIN} start
ExecStop=${ATOM_BIN} stop
ExecReload=${ATOM_BIN} restart
User=${BOOMI_USER}
Group=${BOOMI_GROUP}

[Install]
WantedBy=multi-user.target
EOF

chmod 0644 "${UNIT_PATH}"

echo "Reloading systemd daemon..."
systemctl daemon-reload

echo "Enabling ${SERVICE_NAME}.service..."
systemctl enable "${SERVICE_NAME}.service"

echo "Starting ${SERVICE_NAME}.service..."
systemctl start "${SERVICE_NAME}.service" || {
  echo "ERROR: Failed to start ${SERVICE_NAME}.service" >&2
  echo "Diagnostics:" >&2
  echo "  systemctl status ${SERVICE_NAME}.service --no-pager" >&2
  echo "  journalctl -u ${SERVICE_NAME}.service -n 200 --no-pager" >&2
  exit 1
}

echo "Installed and started ${SERVICE_NAME}.service"
systemctl --no-pager --full status "${SERVICE_NAME}.service" || true