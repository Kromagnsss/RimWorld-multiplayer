```bash
#!/usr/bin/env bash

# Copyright (c) 2026 Kromagnsss
# SPDX-License-Identifier: MIT

source /dev/stdin <<< "$(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/ct/build.func)"

APP="RimWorld Multiplayer"
var_tags="games;rimworld;multiplayer"
var_cpu="2"
var_ram="2048"
var_disk="8"
var_unprivileged="1"

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

RIMWORLD_DIR="/opt/rimworld-multiplayer"
SERVER_DIR="${RIMWORLD_DIR}/Server"
LINUX_DIR="${SERVER_DIR}/Linux"

DOWNLOAD_URL="https://github.com/rwmt/Multiplayer/releases/download/continuous/Server-beta.zip"
DOWNLOAD_FILE="/tmp/Server-beta.zip"

SERVICE_NAME="rimworld-multiplayer"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

PORT="30502"

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------

function msg_info() {
    echo -e "\033[1;36m⠋ $1\033[0m"
}

function msg_ok() {
    echo -e "\033[1;32m  ✔️  $1\033[0m"
}

function msg_error() {
    echo -e "\033[1;31m  ✖️  $1\033[0m"
}

function cleanup() {
    rm -f "${DOWNLOAD_FILE}"
    rm -rf /tmp/rimworld-server-extract
}

trap cleanup EXIT

# -----------------------------------------------------------------------------
# Update function
# -----------------------------------------------------------------------------

function update_script() {

    if ! command -v curl >/dev/null 2>&1; then
        apt-get update
        apt-get install -y curl
    fi

    msg_info "Stopping RimWorld Multiplayer"

    systemctl stop "${SERVICE_NAME}" 2>/dev/null || true

    # -------------------------------------------------------------------------
    # Temporary directories
    # -------------------------------------------------------------------------

    local TMP_DIR="/tmp/rimworld-update"
    local EXTRACT_DIR="${TMP_DIR}/extract"
    local DATA_DIR="${TMP_DIR}/data"

    rm -rf "${TMP_DIR}"
    mkdir -p "${EXTRACT_DIR}" "${DATA_DIR}"

    # -------------------------------------------------------------------------
    # Preserve server data
    # -------------------------------------------------------------------------

    msg_info "Preserving RimWorld server data"

    if [[ -f "${LINUX_DIR}/settings.toml" ]]; then
        cp -a "${LINUX_DIR}/settings.toml" "${DATA_DIR}/"
    fi

    if [[ -d "${LINUX_DIR}/Saved" ]]; then
        cp -a "${LINUX_DIR}/Saved" "${DATA_DIR}/"
    fi

    if [[ -f "${LINUX_DIR}/save.zip" ]]; then
        cp -a "${LINUX_DIR}/save.zip" "${DATA_DIR}/"
    fi

    # -------------------------------------------------------------------------
    # Download new version
    # -------------------------------------------------------------------------

    msg_info "Downloading latest RimWorld Multiplayer Server"

    curl -fL --retry 3 --retry-delay 2 \
        "${DOWNLOAD_URL}" \
        -o "${DOWNLOAD_FILE}"

    msg_ok "Downloaded latest server"

    # -------------------------------------------------------------------------
    # Extract
    # -------------------------------------------------------------------------

    msg_info "Extracting server"

    unzip -q -o "${DOWNLOAD_FILE}" -d "${EXTRACT_DIR}"

    # Find Server directory
    local NEW_SERVER_DIR=""

    if [[ -d "${EXTRACT_DIR}/Server" ]]; then
        NEW_SERVER_DIR="${EXTRACT_DIR}/Server"
    elif [[ -d "${EXTRACT_DIR}/Server/Linux" ]]; then
        NEW_SERVER_DIR="${EXTRACT_DIR}/Server"
    else
        NEW_SERVER_DIR="$(find "${EXTRACT_DIR}" -maxdepth 3 -type f -name 'Server.dll' -printf '%h/../\n' | head -n1 || true)"
    fi

    if [[ -z "${NEW_SERVER_DIR}" || ! -d "${NEW_SERVER_DIR}" ]]; then
        msg_error "Could not locate Server directory in archive"
        rm -rf "${TMP_DIR}"
        return 1
    fi

    # -------------------------------------------------------------------------
    # Replace application files
    # -------------------------------------------------------------------------

    msg_info "Installing updated server"

    local BACKUP_DIR="/tmp/rimworld-old-server"

    rm -rf "${BACKUP_DIR}"
    mkdir -p "${BACKUP_DIR}"

    if [[ -d "${SERVER_DIR}" ]]; then
        mv "${SERVER_DIR}" "${BACKUP_DIR}/Server"
    fi

    mkdir -p "${SERVER_DIR}"

    cp -a "${NEW_SERVER_DIR}/." "${SERVER_DIR}/"

    # -------------------------------------------------------------------------
    # Restore persistent data
    # -------------------------------------------------------------------------

    if [[ -f "${DATA_DIR}/settings.toml" ]]; then
        cp -a "${DATA_DIR}/settings.toml" "${LINUX_DIR}/"
    fi

    if [[ -d "${DATA_DIR}/Saved" ]]; then
        cp -a "${DATA_DIR}/Saved" "${LINUX_DIR}/"
    fi

    if [[ -f "${DATA_DIR}/save.zip" ]]; then
        cp -a "${DATA_DIR}/save.zip" "${LINUX_DIR}/"
    fi

    chmod +x "${LINUX_DIR}/Server.sh" 2>/dev/null || true
    chmod +x "${LINUX_DIR}/Server" 2>/dev/null || true

    # -------------------------------------------------------------------------
    # Cleanup old files
    # -------------------------------------------------------------------------

    rm -rf "${BACKUP_DIR}"
    rm -rf "${TMP_DIR}"
    rm -f "${DOWNLOAD_FILE}"

    # -------------------------------------------------------------------------
    # Restart
    # -------------------------------------------------------------------------

    systemctl daemon-reload
    systemctl reset-failed "${SERVICE_NAME}" 2>/dev/null || true
    systemctl start "${SERVICE_NAME}"

    sleep 2

    if systemctl is-active --quiet "${SERVICE_NAME}"; then
        msg_ok "RimWorld Multiplayer updated successfully"
    else
        msg_error "RimWorld Multiplayer failed to start after update"
        systemctl status "${SERVICE_NAME}" --no-pager || true
        journalctl -u "${SERVICE_NAME}" -n 50 --no-pager || true
        return 1
    fi
}

# -----------------------------------------------------------------------------
# Container configuration
# -----------------------------------------------------------------------------

function install_rimworld() {

    msg_info "Installing dependencies"

    apt-get update

    apt-get install -y \
        ca-certificates \
        curl \
        wget \
        unzip \
        util-linux \
        iproute2 \
        procps

    msg_ok "Installed dependencies"

    # -------------------------------------------------------------------------
    # Microsoft .NET repository
    # -------------------------------------------------------------------------

    msg_info "Configuring Microsoft repository"

    local MS_DEB="/tmp/packages-microsoft-prod.deb"

    rm -f "${MS_DEB}"

    wget -q \
        "https://packages.microsoft.com/config/debian/13/packages-microsoft-prod.deb" \
        -O "${MS_DEB}"

    dpkg -i "${MS_DEB}"

    rm -f "${MS_DEB}"

    apt-get update

    msg_ok "Microsoft repository configured"

    # -------------------------------------------------------------------------
    # .NET 8
    # -------------------------------------------------------------------------

    msg_info "Installing .NET 8 Runtime"

    apt-get install -y dotnet-runtime-8.0

    if ! command -v dotnet >/dev/null 2>&1; then
        msg_error ".NET runtime installation failed"
        exit 1
    fi

    msg_ok "Installed .NET 8 Runtime"

    # -------------------------------------------------------------------------
    # Application directory
    # -------------------------------------------------------------------------

    mkdir -p "${RIMWORLD_DIR}"

    msg_ok "Created ${RIMWORLD_DIR}"

    # -------------------------------------------------------------------------
    # Download server
    # -------------------------------------------------------------------------

    msg_info "Downloading RimWorld Multiplayer Server"

    rm -f "${DOWNLOAD_FILE}"
    rm -rf /tmp/rimworld-server-extract

    mkdir -p /tmp/rimworld-server-extract

    curl -fL --retry 3 --retry-delay 2 \
        "${DOWNLOAD_URL}" \
        -o "${DOWNLOAD_FILE}"

    msg_ok "Downloaded server"

    # -------------------------------------------------------------------------
    # Extract
    # -------------------------------------------------------------------------

    unzip -q -o \
        "${DOWNLOAD_FILE}" \
        -d /tmp/rimworld-server-extract

    # -------------------------------------------------------------------------
    # Locate Server directory
    # -------------------------------------------------------------------------

    local SOURCE_SERVER_DIR=""

    if [[ -d "/tmp/rimworld-server-extract/Server" ]]; then
        SOURCE_SERVER_DIR="/tmp/rimworld-server-extract/Server"
    else
        SOURCE_SERVER_DIR="$(find /tmp/rimworld-server-extract \
            -type f \
            -name 'Server.dll' \
            -printf '%h\n' \
            | head -n1 \
            | sed 's#/Linux$##' || true)"
    fi

    if [[ -z "${SOURCE_SERVER_DIR}" || ! -d "${SOURCE_SERVER_DIR}" ]]; then
        msg_error "Server directory was not found in Server-beta.zip"
        exit 1
    fi

    cp -a "${SOURCE_SERVER_DIR}" "${SERVER_DIR}"

    msg_ok "Server extracted"

    # -------------------------------------------------------------------------
    # Verify .NET requirement
    # -------------------------------------------------------------------------

    if [[ -f "${LINUX_DIR}/Server.runtimeconfig.json" ]]; then

        if grep -q '"net8.0"' \
            "${LINUX_DIR}/Server.runtimeconfig.json"; then

            msg_ok "Server requires .NET 8"

        else
            msg_info "Server runtime requirement differs from .NET 8"
        fi
    fi

    chmod +x "${LINUX_DIR}/Server.sh" 2>/dev/null || true
    chmod +x "${LINUX_DIR}/Server" 2>/dev/null || true

    # -------------------------------------------------------------------------
    # Create systemd service
    # -------------------------------------------------------------------------

    msg_info "Creating systemd service"

    cat > "${SERVICE_FILE}" <<EOF
[Unit]
Description=RimWorld Multiplayer Dedicated Server
Documentation=https://github.com/rwmt/Multiplayer/wiki/Hosting-and-joining
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=${LINUX_DIR}

# The RimWorld server uses Console.KeyAvailable().
# Running through 'script' provides the pseudo-terminal it expects.
ExecStart=/usr/bin/script -q -c "${LINUX_DIR}/Server.sh" /dev/null

Restart=on-failure
RestartSec=5

# Give the server enough time to shut down cleanly.
TimeoutStopSec=30

# Keep the service independent from an interactive login session.
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    chmod 644 "${SERVICE_FILE}"

    systemctl daemon-reload
    systemctl enable "${SERVICE_NAME}" >/dev/null

    msg_ok "Created systemd service"

    # -------------------------------------------------------------------------
    # Management command
    # -------------------------------------------------------------------------

    msg_info "Creating management command"

    cat > /usr/local/bin/rimworld <<'EOF'
#!/usr/bin/env bash

SERVICE="rimworld-multiplayer"

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
        if [[ -x /usr/local/bin/rimworld-update ]]; then
            /usr/local/bin/rimworld-update
        else
            echo "Update command is not available."
            exit 1
        fi
        ;;

    port)
        ss -lunp | grep 30502 || true
        ;;

    *)
        echo "RimWorld Multiplayer management"
        echo
        echo "Usage:"
        echo "  rimworld start    Start server"
        echo "  rimworld stop     Stop server"
        echo "  rimworld restart  Restart server"
        echo "  rimworld status   Show service status"
        echo "  rimworld log      Show last 100 log lines"
        echo "  rimworld logs     Follow server logs"
        echo "  rimworld port     Show UDP 30502"
        echo "  rimworld update   Update server"
        echo
        exit 1
        ;;
esac
EOF

    chmod +x /usr/local/bin/rimworld

    # -------------------------------------------------------------------------
    # Update command
    # -------------------------------------------------------------------------

    cat > /usr/local/bin/rimworld-update <<'EOF'
#!/usr/bin/env bash

set -euo pipefail

DOWNLOAD_URL="https://github.com/rwmt/Multiplayer/releases/download/continuous/Server-beta.zip"

RIMWORLD_DIR="/opt/rimworld-multiplayer"
SERVER_DIR="${RIMWORLD_DIR}/Server"
LINUX_DIR="${SERVER_DIR}/Linux"

TMP_DIR="/tmp/rimworld-update"
ZIP_FILE="${TMP_DIR}/Server-beta.zip"
EXTRACT_DIR="${TMP_DIR}/extract"
DATA_DIR="${TMP_DIR}/data"

SERVICE="rimworld-multiplayer"

cleanup() {
    rm -rf "${TMP_DIR}"
}

trap cleanup EXIT

echo "Stopping RimWorld Multiplayer..."

systemctl stop "${SERVICE}" || true

rm -rf "${TMP_DIR}"
mkdir -p "${EXTRACT_DIR}" "${DATA_DIR}"

echo "Preserving server data..."

if [[ -f "${LINUX_DIR}/settings.toml" ]]; then
    cp -a "${LINUX_DIR}/settings.toml" "${DATA_DIR}/"
fi

if [[ -d "${LINUX_DIR}/Saved" ]]; then
    cp -a "${LINUX_DIR}/Saved" "${DATA_DIR}/"
fi

if [[ -f "${LINUX_DIR}/save.zip" ]]; then
    cp -a "${LINUX_DIR}/save.zip" "${DATA_DIR}/"
fi

echo "Downloading latest server..."

curl -fL --retry 3 --retry-delay 2 \
    "${DOWNLOAD_URL}" \
    -o "${ZIP_FILE}"

echo "Extracting..."

unzip -q -o "${ZIP_FILE}" -d "${EXTRACT_DIR}"

if [[ -d "${EXTRACT_DIR}/Server" ]]; then
    NEW_SERVER_DIR="${EXTRACT_DIR}/Server"
else
    NEW_SERVER_DIR="$(find "${EXTRACT_DIR}" \
        -type f \
        -name 'Server.dll' \
        -printf '%h\n' \
        | head -n1 \
        | sed 's#/Linux$##')"
fi

if [[ -z "${NEW_SERVER_DIR}" || ! -d "${NEW_SERVER_DIR}" ]]; then
    echo "ERROR: Server directory not found in archive."
    exit 1
fi

echo "Installing update..."

BACKUP_DIR="${TMP_DIR}/old"

mkdir -p "${BACKUP_DIR}"

if [[ -d "${SERVER_DIR}" ]]; then
    mv "${SERVER_DIR}" "${BACKUP_DIR}/Server"
fi

mkdir -p "${SERVER_DIR}"

cp -a "${NEW_SERVER_DIR}/." "${SERVER_DIR}/"

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

chmod +x "${LINUX_DIR}/Server.sh" 2>/dev/null || true
chmod +x "${LINUX_DIR}/Server" 2>/dev/null || true

systemctl daemon-reload
systemctl reset-failed "${SERVICE}" || true

echo "Starting server..."

systemctl start "${SERVICE}"

sleep 3

if systemctl is-active --quiet "${SERVICE}"; then
    echo
    echo "RimWorld Multiplayer updated successfully."
    echo
    systemctl status "${SERVICE}" --no-pager
else
    echo
    echo "ERROR: Server failed to start."
    echo
    systemctl status "${SERVICE}" --no-pager || true
    echo
    journalctl -u "${SERVICE}" -n 50 --no-pager || true
    exit 1
fi
EOF

    chmod +x /usr/local/bin/rimworld-update

    msg_ok "Created management command"

    # -------------------------------------------------------------------------
    # Check port before first start
    # -------------------------------------------------------------------------

    if ss -lun 2>/dev/null | grep -q ":${PORT} "; then

        msg_error "UDP port ${PORT} is already in use"
        echo
        echo "The RimWorld server was installed but was NOT started."
        echo
        echo "Port owner:"
        ss -lunp | grep ":${PORT} " || true
        echo
        echo "Run:"
        echo "  ss -lunp | grep ${PORT}"
        echo
        echo "Then start the server with:"
        echo "  systemctl start ${SERVICE}"
        echo

        exit 1
    fi

    # -------------------------------------------------------------------------
    # Start service
    # -------------------------------------------------------------------------

    msg_info "Starting RimWorld Multiplayer Server"

    systemctl reset-failed "${SERVICE}" 2>/dev/null || true
    systemctl start "${SERVICE}"

    sleep 3

    if systemctl is-active --quiet "${SERVICE}"; then

        msg_ok "RimWorld Multiplayer Server is running"

        echo
        echo "  Server directory : ${RIMWORLD_DIR}"
        echo "  Server port      : UDP ${PORT}"
        echo "  Service          : ${SERVICE}"
        echo
        echo "  Management:"
        echo "    rimworld status"
        echo "    rimworld logs"
        echo "    rimworld restart"
        echo "    rimworld update"
        echo

    else

        msg_error "RimWorld Multiplayer Server failed to start"

        echo
        systemctl status "${SERVICE}" --no-pager || true
        echo
        journalctl -u "${SERVICE}" -n 50 --no-pager || true

        exit 1
    fi
}

# -----------------------------------------------------------------------------
# Container update
# -----------------------------------------------------------------------------

function update() {
    update_script
}

# -----------------------------------------------------------------------------
# Build container
# -----------------------------------------------------------------------------

start
build_container
install_rimworld
```
