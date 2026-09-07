#!/usr/bin/env bash

# Copyright (c) 2026 Kromagnsss
# SPDX-License-Identifier: MIT

source /dev/stdin <<< "$FUNCTIONS_FILE_PATH"

color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

RIMWORLD_DIR="/opt/rimworld-multiplayer"
SERVER_DIR="${RIMWORLD_DIR}/Server"
LINUX_DIR="${SERVER_DIR}/Linux"

DOWNLOAD_URL="https://github.com/rwmt/Multiplayer/releases/download/continuous/Server-beta.zip"

SERVICE_NAME="rimworld-multiplayer"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

UPDATE_SCRIPT="/usr/local/bin/rimworld-update"
MANAGEMENT_SCRIPT="/usr/local/bin/rimworld"

PORT="30502"

TMP_BASE="/tmp/rimworld-multiplayer"

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------

function cleanup() {
    rm -rf "${TMP_BASE}"
}

trap cleanup EXIT

# -----------------------------------------------------------------------------
# Dependencies
# -----------------------------------------------------------------------------

msg_info "Installing dependencies"

$STD apt-get install -y \
    ca-certificates \
    curl \
    wget \
    unzip \
    util-linux \
    iproute2 \
    procps

msg_ok "Installed dependencies"

# -----------------------------------------------------------------------------
# Microsoft repository
# -----------------------------------------------------------------------------

msg_info "Configuring Microsoft repository"

MS_DEB="/tmp/packages-microsoft-prod.deb"

rm -f "${MS_DEB}"

if ! wget -q \
    "https://packages.microsoft.com/config/debian/13/packages-microsoft-prod.deb" \
    -O "${MS_DEB}"; then

    msg_error "Failed to download Microsoft repository package"
    exit 1
fi

$STD dpkg -i "${MS_DEB}"

rm -f "${MS_DEB}"

$STD apt-get update

msg_ok "Microsoft repository configured"

# -----------------------------------------------------------------------------
# .NET 8
# -----------------------------------------------------------------------------

msg_info "Installing .NET 8 Runtime"

$STD apt-get install -y dotnet-runtime-8.0

if ! command -v dotnet >/dev/null 2>&1; then
    msg_error ".NET 8 Runtime installation failed"
    exit 1
fi

if ! dotnet --list-runtimes | grep -q "Microsoft.NETCore.App 8."; then
    msg_error ".NET 8 Runtime is not available"
    exit 1
fi

msg_ok "Installed .NET 8 Runtime"

# -----------------------------------------------------------------------------
# Application directories
# -----------------------------------------------------------------------------

msg_info "Preparing RimWorld Multiplayer directories"

mkdir -p "${RIMWORLD_DIR}"

rm -rf "${TMP_BASE}"
mkdir -p "${TMP_BASE}/download"
mkdir -p "${TMP_BASE}/extract"

msg_ok "Created ${RIMWORLD_DIR}"

# -----------------------------------------------------------------------------
# Download
# -----------------------------------------------------------------------------

msg_info "Downloading RimWorld Multiplayer Server"

ZIP_FILE="${TMP_BASE}/download/Server-beta.zip"

if ! curl -fL \
    --retry 5 \
    --retry-delay 2 \
    --connect-timeout 15 \
    --max-time 300 \
    "${DOWNLOAD_URL}" \
    -o "${ZIP_FILE}"; then

    msg_error "Failed to download RimWorld Multiplayer Server"
    exit 1
fi

if [[ ! -s "${ZIP_FILE}" ]]; then
    msg_error "Downloaded archive is empty"
    exit 1
fi

msg_ok "Downloaded server"

# -----------------------------------------------------------------------------
# Extract
# -----------------------------------------------------------------------------

msg_info "Extracting RimWorld Multiplayer Server"

EXTRACT_DIR="${TMP_BASE}/extract"

if ! unzip -q -o "${ZIP_FILE}" -d "${EXTRACT_DIR}"; then
    msg_error "Failed to extract Server-beta.zip"
    exit 1
fi

msg_ok "Server extracted"

# -----------------------------------------------------------------------------
# Locate Server directory
# -----------------------------------------------------------------------------

SOURCE_SERVER_DIR=""

if [[ -d "${EXTRACT_DIR}/Server/Linux" ]]; then
    SOURCE_SERVER_DIR="${EXTRACT_DIR}/Server"
else
    SERVER_DLL="$(find "${EXTRACT_DIR}" \
        -type f \
        -name "Server.dll" \
        -print -quit)"

    if [[ -n "${SERVER_DLL}" ]]; then
        SOURCE_SERVER_DIR="$(dirname "$(dirname "${SERVER_DLL}")")"
    fi
fi

if [[ -z "${SOURCE_SERVER_DIR}" || ! -d "${SOURCE_SERVER_DIR}/Linux" ]]; then
    msg_error "Could not locate Server/Linux in Server-beta.zip"
    exit 1
fi

if [[ ! -f "${SOURCE_SERVER_DIR}/Linux/Server.dll" ]]; then
    msg_error "Server.dll was not found"
    exit 1
fi

if [[ ! -f "${SOURCE_SERVER_DIR}/Linux/Server.sh" ]]; then
    msg_error "Server.sh was not found"
    exit 1
fi

# -----------------------------------------------------------------------------
# Install server
# -----------------------------------------------------------------------------

msg_info "Installing RimWorld Multiplayer Server"

rm -rf "${SERVER_DIR}"

mkdir -p "${SERVER_DIR}"

cp -a "${SOURCE_SERVER_DIR}/." "${SERVER_DIR}/"

chmod +x "${LINUX_DIR}/Server.sh"

if [[ -f "${LINUX_DIR}/Server" ]]; then
    chmod +x "${LINUX_DIR}/Server"
fi

msg_ok "Installed RimWorld Multiplayer Server"

# -----------------------------------------------------------------------------
# Verify .NET requirement
# -----------------------------------------------------------------------------

if [[ -f "${LINUX_DIR}/Server.runtimeconfig.json" ]]; then

    if grep -q '"net8.0"' \
        "${LINUX_DIR}/Server.runtimeconfig.json"; then

        msg_ok "Server requires .NET 8"

    else
        msg_warn "Server runtime requirement is different from .NET 8"
    fi
fi

# -----------------------------------------------------------------------------
# Create systemd service
# -----------------------------------------------------------------------------

msg_info "Creating systemd service"

cat > "${SERVICE_FILE}" <<EOF
[Unit]
Description=RimWorld Multiplayer Dedicated Server
Documentation=https://github.com/rwmt/Multiplayer/wiki/Hosting-and-joining
After=network-online.target
Wants=network-online.target

# Stop endless restart loops when the server itself fails repeatedly.
StartLimitIntervalSec=60
StartLimitBurst=5

[Service]
Type=simple
User=root

WorkingDirectory=${LINUX_DIR}

# RimWorld Multiplayer uses Console.KeyAvailable().
# 'script' allocates a pseudo-terminal so the server can use console input.
ExecStart=/usr/bin/script -q -c "${LINUX_DIR}/Server.sh" /dev/null

Restart=on-failure
RestartSec=5

TimeoutStartSec=30
TimeoutStopSec=30

KillMode=control-group

StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

chmod 644 "${SERVICE_FILE}"

systemctl daemon-reload
systemctl enable "${SERVICE_NAME}" >/dev/null

msg_ok "Created systemd service"

# -----------------------------------------------------------------------------
# Management command
# -----------------------------------------------------------------------------

msg_info "Creating management command"

cat > "${MANAGEMENT_SCRIPT}" <<'EOF'
#!/usr/bin/env bash

SERVICE="rimworld-multiplayer"
PORT="30502"

case "${1:-status}" in

    start)
        systemctl start "${SERVICE}"
        ;;

    stop)
        systemctl stop "${SERVICE}"
        ;;

    restart)
        systemctl restart "${SERVICE}"
        ;;

    status)
        systemctl status "${SERVICE}" --no-pager
        ;;

    logs)
        journalctl -u "${SERVICE}" -f
        ;;

    log)
        journalctl -u "${SERVICE}" -n 100 --no-pager
        ;;

    update)
        /usr/local/bin/rimworld-update
        ;;

    port)
        echo "UDP port ${PORT}:"
        ss -lunp | grep ":${PORT} " || echo "Port ${PORT} is not currently listening."
        ;;

    version)
        if [[ -f /opt/rimworld-multiplayer/Server/Linux/Server.dll ]]; then
            echo "RimWorld Multiplayer Server installed."
            echo "Location: /opt/rimworld-multiplayer/Server/Linux"
        else
            echo "RimWorld Multiplayer Server is not installed."
            exit 1
        fi
        ;;

    *)
        echo
        echo "RimWorld Multiplayer management"
        echo
        echo "Usage:"
        echo
        echo "  rimworld start       Start server"
        echo "  rimworld stop        Stop server"
        echo "  rimworld restart     Restart server"
        echo "  rimworld status      Show service status"
        echo "  rimworld log         Show last 100 log lines"
        echo "  rimworld logs        Follow server logs"
        echo "  rimworld port        Show UDP 30502"
        echo "  rimworld version      Show installation information"
        echo "  rimworld update      Update server"
        echo
        exit 1
        ;;

esac
EOF

chmod +x "${MANAGEMENT_SCRIPT}"

# -----------------------------------------------------------------------------
# Update script
# -----------------------------------------------------------------------------

msg_info "Creating update system"

cat > "${UPDATE_SCRIPT}" <<'EOF'
#!/usr/bin/env bash

set -euo pipefail

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

RIMWORLD_DIR="/opt/rimworld-multiplayer"
SERVER_DIR="${RIMWORLD_DIR}/Server"
LINUX_DIR="${SERVER_DIR}/Linux"

DOWNLOAD_URL="https://github.com/rwmt/Multiplayer/releases/download/continuous/Server-beta.zip"

SERVICE="rimworld-multiplayer"

BASE_DIR="/tmp/rimworld-multiplayer-update"
ZIP_FILE="${BASE_DIR}/Server-beta.zip"
EXTRACT_DIR="${BASE_DIR}/extract"
DATA_DIR="${BASE_DIR}/data"
NEW_SERVER_DIR="${BASE_DIR}/new-server"
OLD_SERVER_DIR="${BASE_DIR}/old-server"

# -----------------------------------------------------------------------------
# Cleanup
# -----------------------------------------------------------------------------

cleanup() {
    rm -rf "${BASE_DIR}"
}

trap cleanup EXIT

# -----------------------------------------------------------------------------
# Checks
# -----------------------------------------------------------------------------

if [[ ! -d "${LINUX_DIR}" ]]; then
    echo "ERROR: RimWorld Multiplayer installation not found."
    exit 1
fi

if [[ ! -x /usr/bin/dotnet ]]; then
    echo "ERROR: .NET Runtime is not installed."
    exit 1
fi

# -----------------------------------------------------------------------------
# Stop service
# -----------------------------------------------------------------------------

echo
echo "=== RimWorld Multiplayer Update ==="
echo

echo "Stopping server..."

systemctl stop "${SERVICE}" || true

# Make absolutely sure no previous service process remains.
sleep 1

# -----------------------------------------------------------------------------
# Prepare temporary directories
# -----------------------------------------------------------------------------

rm -rf "${BASE_DIR}"

mkdir -p \
    "${EXTRACT_DIR}" \
    "${DATA_DIR}" \
    "${NEW_SERVER_DIR}" \
    "${OLD_SERVER_DIR}"

# -----------------------------------------------------------------------------
# Preserve server data
# -----------------------------------------------------------------------------

echo "Preserving server data..."

# Known persistent files/directories.
if [[ -f "${LINUX_DIR}/settings.toml" ]]; then
    cp -a "${LINUX_DIR}/settings.toml" "${DATA_DIR}/"
fi

if [[ -d "${LINUX_DIR}/Saved" ]]; then
    cp -a "${LINUX_DIR}/Saved" "${DATA_DIR}/"
fi

if [[ -f "${LINUX_DIR}/save.zip" ]]; then
    cp -a "${LINUX_DIR}/save.zip" "${DATA_DIR}/"
fi

# -----------------------------------------------------------------------------
# Download
# -----------------------------------------------------------------------------

echo "Downloading latest continuous release..."

curl -fL \
    --retry 5 \
    --retry-delay 2 \
    --connect-timeout 15 \
    --max-time 300 \
    "${DOWNLOAD_URL}" \
    -o "${ZIP_FILE}"

if [[ ! -s "${ZIP_FILE}" ]]; then
    echo "ERROR: Downloaded archive is empty."
    exit 1
fi

echo "Download complete."

# -----------------------------------------------------------------------------
# Extract
# -----------------------------------------------------------------------------

echo "Extracting..."

unzip -q -o "${ZIP_FILE}" -d "${EXTRACT_DIR}"

# -----------------------------------------------------------------------------
# Locate new Server directory
# -----------------------------------------------------------------------------

if [[ -d "${EXTRACT_DIR}/Server/Linux" ]]; then
    SOURCE_SERVER_DIR="${EXTRACT_DIR}/Server"
else
    SERVER_DLL="$(find "${EXTRACT_DIR}" \
        -type f \
        -name "Server.dll" \
        -print -quit)"

    if [[ -z "${SERVER_DLL}" ]]; then
        echo "ERROR: Server.dll not found in archive."
        exit 1
    fi

    SOURCE_SERVER_DIR="$(dirname "$(dirname "${SERVER_DLL}")")"
fi

if [[ ! -d "${SOURCE_SERVER_DIR}/Linux" ]]; then
    echo "ERROR: Server/Linux directory not found."
    exit 1
fi

if [[ ! -f "${SOURCE_SERVER_DIR}/Linux/Server.dll" ]]; then
    echo "ERROR: Server.dll not found."
    exit 1
fi

if [[ ! -f "${SOURCE_SERVER_DIR}/Linux/Server.sh" ]]; then
    echo "ERROR: Server.sh not found."
    exit 1
fi

# -----------------------------------------------------------------------------
# Stage new version
# -----------------------------------------------------------------------------

echo "Preparing new server version..."

cp -a "${SOURCE_SERVER_DIR}/." "${NEW_SERVER_DIR}/"

chmod +x "${NEW_SERVER_DIR}/Linux/Server.sh"

if [[ -f "${NEW_SERVER_DIR}/Linux/Server" ]]; then
    chmod +x "${NEW_SERVER_DIR}/Linux/Server"
fi

# -----------------------------------------------------------------------------
# Backup current version
# -----------------------------------------------------------------------------

echo "Backing up current server..."

if [[ -d "${SERVER_DIR}" ]]; then
    cp -a "${SERVER_DIR}/." "${OLD_SERVER_DIR}/"
fi

# -----------------------------------------------------------------------------
# Install new version
# -----------------------------------------------------------------------------

echo "Installing new version..."

rm -rf "${SERVER_DIR}"

mkdir -p "${SERVER_DIR}"

cp -a "${NEW_SERVER_DIR}/." "${SERVER_DIR}/"

# -----------------------------------------------------------------------------
# Restore persistent data
# -----------------------------------------------------------------------------

echo "Restoring server data..."

if [[ -f "${DATA_DIR}/settings.toml" ]]; then
    cp -a "${DATA_DIR}/settings.toml" "${LINUX_DIR}/"
fi

if [[ -d "${DATA_DIR}/Saved" ]]; then
    cp -a "${DATA_DIR}/Saved" "${LINUX_DIR}/"
fi

if [[ -f "${DATA_DIR}/save.zip" ]]; then
    cp -a "${DATA_DIR}/save.zip" "${LINUX_DIR}/"
fi

chmod +x "${LINUX_DIR}/Server.sh"

if [[ -f "${LINUX_DIR}/Server" ]]; then
    chmod +x "${LINUX_DIR}/Server"
fi

# -----------------------------------------------------------------------------
# Start
# -----------------------------------------------------------------------------

echo "Starting updated server..."

systemctl daemon-reload
systemctl reset-failed "${SERVICE}" || true
systemctl start "${SERVICE}"

sleep 3

# -----------------------------------------------------------------------------
# Validate
# -----------------------------------------------------------------------------

if systemctl is-active --quiet "${SERVICE}"; then

    echo
    echo "========================================"
    echo "RimWorld Multiplayer updated successfully"
    echo "========================================"
    echo

    systemctl --no-pager status "${SERVICE}"

    exit 0
fi

# -----------------------------------------------------------------------------
# Rollback
# -----------------------------------------------------------------------------

echo
echo "ERROR: Updated server failed to start."
echo
echo "Rolling back to previous version..."

systemctl stop "${SERVICE}" || true

rm -rf "${SERVER_DIR}"

mkdir -p "${SERVER_DIR}"

if [[ -d "${OLD_SERVER_DIR}" ]]; then
    cp -a "${OLD_SERVER_DIR}/." "${SERVER_DIR}/"
fi

systemctl daemon-reload
systemctl reset-failed "${SERVICE}" || true
systemctl start "${SERVICE}"

sleep 3

if systemctl is-active --quiet "${SERVICE}"; then
    echo
    echo "Rollback successful."
    echo "The previous RimWorld Multiplayer version is running."
    echo
else
    echo
    echo "CRITICAL ERROR:"
    echo "Rollback also failed."
    echo
    systemctl status "${SERVICE}" --no-pager || true
    journalctl -u "${SERVICE}" -n 100 --no-pager || true
    exit 2
fi
EOF

chmod +x "${UPDATE_SCRIPT}"

msg_ok "Created update system"

# -----------------------------------------------------------------------------
# Initial port check
# -----------------------------------------------------------------------------

if ss -lun 2>/dev/null | grep -q ":${PORT} "; then

    msg_error "UDP port ${PORT} is already in use"

    echo
    echo "The server was installed but will NOT be started automatically."
    echo
    echo "Port owner:"
    ss -lunp | grep ":${PORT} " || true
    echo
    echo "After resolving the conflict, run:"
    echo
    echo "  systemctl start ${SERVICE_NAME}"
    echo

else

    # -------------------------------------------------------------------------
    # Start service
    # -------------------------------------------------------------------------

    msg_info "Starting RimWorld Multiplayer Server"

    systemctl reset-failed "${SERVICE_NAME}" 2>/dev/null || true
    systemctl start "${SERVICE_NAME}"

    sleep 3

    if systemctl is-active --quiet "${SERVICE_NAME}"; then

        msg_ok "RimWorld Multiplayer Server is running"

    else

        msg_error "RimWorld Multiplayer Server failed to start"

        echo
        systemctl status "${SERVICE_NAME}" --no-pager || true
        echo
        journalctl -u "${SERVICE_NAME}" -n 50 --no-pager || true

        exit 1
    fi
fi

# -----------------------------------------------------------------------------
# Final configuration
# -----------------------------------------------------------------------------

motd_ssh
customize
cleanup_lxc

# -----------------------------------------------------------------------------
# Final message
# -----------------------------------------------------------------------------

echo
msg_ok "RimWorld Multiplayer installation completed!"
echo
echo -e "${INFO}${YW}Server directory:${CL} ${RIMWORLD_DIR}"
echo -e "${INFO}${YW}Server port:${CL} UDP ${PORT}"
echo
echo -e "${INFO}${YW}Management commands:${CL}"
echo -e "  ${TAB3}rimworld status"
echo -e "  ${TAB3}rimworld logs"
echo -e "  ${TAB3}rimworld restart"
echo -e "  ${TAB3}rimworld update"
echo -e "  ${TAB3}rimworld port"
echo