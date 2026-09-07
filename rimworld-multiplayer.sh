#!/usr/bin/env bash

source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)

# Copyright (c) 2026
# License: MIT
#
# Source:
# https://github.com/rwmt/Multiplayer
#
# RimWorld Multiplayer Dedicated Server
# Default port: UDP 30502

APP="RimWorld Multiplayer Server"

var_tags="${var_tags:-game;rimworld;multiplayer}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors


# ---------------------------------------------------------
# Configuration
# ---------------------------------------------------------

INSTALL_DIR="/opt/rimworld-multiplayer"
SERVICE_NAME="rimworld-multiplayer"
REPO="rwmt/Multiplayer"
RELEASE="continuous"

DOWNLOAD_URL="https://github.com/${REPO}/releases/download/${RELEASE}/Server-beta.zip"

VERSION_FILE="${INSTALL_DIR}/version.txt"


# ---------------------------------------------------------
# Installation / Update
# ---------------------------------------------------------

function install_server() {

    msg_info "Installing dependencies"

    $STD apt-get update

    $STD apt-get install -y \
        curl \
        unzip \
        ca-certificates \
        wget \
        file

    msg_ok "Installed dependencies"


    msg_info "Creating installation directory"

    mkdir -p "$INSTALL_DIR"

    msg_ok "Created installation directory"


    msg_info "Downloading RimWorld Multiplayer Server"

    cd "$INSTALL_DIR"

    rm -f Server-beta.zip

    $STD curl -L \
        --fail \
        --retry 5 \
        --retry-delay 3 \
        -o Server-beta.zip \
        "$DOWNLOAD_URL"

    msg_ok "Downloaded server"


    msg_info "Extracting server"

    rm -rf "${INSTALL_DIR}/Server"

    $STD unzip -q Server-beta.zip

    rm -f Server-beta.zip

    msg_ok "Extracted server"


    # -----------------------------------------------------
    # Locate Linux server
    # -----------------------------------------------------

    SERVER_SCRIPT=$(find "$INSTALL_DIR" \
        -type f \
        -path "*/Server/Linux/Server.sh" \
        | head -n 1)

    if [[ -z "$SERVER_SCRIPT" ]]; then

        SERVER_SCRIPT=$(find "$INSTALL_DIR" \
            -type f \
            -name "Server.sh" \
            | head -n 1)

    fi


    if [[ -z "$SERVER_SCRIPT" ]]; then

        msg_error "Server.sh not found"

        find "$INSTALL_DIR" -maxdepth 5 -type f

        exit 1

    fi


    SERVER_DIR="$(dirname "$SERVER_SCRIPT")"

    chmod +x "$SERVER_SCRIPT"

    echo "$SERVER_DIR" > "${INSTALL_DIR}/server_dir.txt"

    msg_ok "Linux server found"


    # -----------------------------------------------------
    # Version information
    # -----------------------------------------------------

    RELEASE_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    cat > "$VERSION_FILE" <<EOF
release=${RELEASE}
download=${DOWNLOAD_URL}
installed=${RELEASE_DATE}
EOF

    msg_ok "Version information saved"


    # -----------------------------------------------------
    # systemd service
    # -----------------------------------------------------

    msg_info "Creating systemd service"

    cat > "/etc/systemd/system/${SERVICE_NAME}.service" <<EOF
[Unit]
Description=RimWorld Multiplayer Dedicated Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple

WorkingDirectory=${SERVER_DIR}

ExecStart=${SERVER_SCRIPT}

Restart=always
RestartSec=5

KillSignal=SIGINT
TimeoutStopSec=30

# RimWorld Multiplayer uses UDP 30502 by default.
# No --port argument is passed.

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload

    systemctl enable "$SERVICE_NAME"

    msg_ok "Created systemd service"


    # -----------------------------------------------------
    # Helper commands
    # -----------------------------------------------------

    cat > /usr/local/bin/rimworld-server <<'EOF'
#!/usr/bin/env bash

case "$1" in

    start)
        systemctl start rimworld-multiplayer
        ;;

    stop)
        systemctl stop rimworld-multiplayer
        ;;

    restart)
        systemctl restart rimworld-multiplayer
        ;;

    status)
        systemctl status rimworld-multiplayer
        ;;

    logs)
        journalctl -u rimworld-multiplayer -f
        ;;

    update)
        /usr/local/sbin/rimworld-update
        ;;

    *)
        echo "Usage:"
        echo "  rimworld-server start"
        echo "  rimworld-server stop"
        echo "  rimworld-server restart"
        echo "  rimworld-server status"
        echo "  rimworld-server logs"
        echo "  rimworld-server update"
        ;;

esac
EOF

    chmod +x /usr/local/bin/rimworld-server


    # -----------------------------------------------------
    # Update command inside the container
    # -----------------------------------------------------

    cat > /usr/local/sbin/rimworld-update <<'EOF'
#!/usr/bin/env bash

set -e

INSTALL_DIR="/opt/rimworld-multiplayer"
SERVICE_NAME="rimworld-multiplayer"

DOWNLOAD_URL="https://github.com/rwmt/Multiplayer/releases/download/continuous/Server-beta.zip"

echo
echo "=============================================="
echo " RimWorld Multiplayer Server Update"
echo "=============================================="
echo

echo "[1/5] Stopping server..."

systemctl stop "$SERVICE_NAME" || true


echo "[2/5] Downloading current release..."

TMP_DIR=$(mktemp -d)

trap 'rm -rf "$TMP_DIR"' EXIT

curl -L \
    --fail \
    --retry 5 \
    --retry-delay 3 \
    -o "$TMP_DIR/Server-beta.zip" \
    "$DOWNLOAD_URL"


echo "[3/5] Installing new version..."

mkdir -p "$TMP_DIR/new"

unzip -q "$TMP_DIR/Server-beta.zip" \
    -d "$TMP_DIR/new"


SERVER_SCRIPT=$(find "$TMP_DIR/new" \
    -type f \
    -path "*/Server/Linux/Server.sh" \
    | head -n 1)

if [[ -z "$SERVER_SCRIPT" ]]; then

    SERVER_SCRIPT=$(find "$TMP_DIR/new" \
        -type f \
        -name "Server.sh" \
        | head -n 1)

fi

if [[ -z "$SERVER_SCRIPT" ]]; then
    echo
    echo "ERROR: Server.sh not found in downloaded archive."
    echo
    systemctl start "$SERVICE_NAME" || true
    exit 1
fi


# Preserve the complete server directory structure.
rm -rf "${INSTALL_DIR}/Server"

if [[ -d "$TMP_DIR/new/Server" ]]; then

    cp -a "$TMP_DIR/new/Server" \
        "${INSTALL_DIR}/Server"

else

    cp -a "$TMP_DIR/new"/* \
        "${INSTALL_DIR}/"

fi


echo "[4/5] Updating permissions..."

SERVER_SCRIPT=$(find "$INSTALL_DIR" \
    -type f \
    -path "*/Server/Linux/Server.sh" \
    | head -n 1)

if [[ -z "$SERVER_SCRIPT" ]]; then

    SERVER_SCRIPT=$(find "$INSTALL_DIR" \
        -type f \
        -name "Server.sh" \
        | head -n 1)

fi

chmod +x "$SERVER_SCRIPT"

SERVER_DIR=$(dirname "$SERVER_SCRIPT")

echo "$SERVER_DIR" > "${INSTALL_DIR}/server_dir.txt"


echo "[5/5] Starting server..."

systemctl daemon-reload

systemctl start "$SERVICE_NAME"


echo
echo "=============================================="
echo " Update completed"
echo "=============================================="
echo
echo "Server directory:"
echo "$SERVER_DIR"
echo
echo "Service status:"
systemctl --no-pager --full status "$SERVICE_NAME" || true
echo

EOF

    chmod +x /usr/local/sbin/rimworld-update


    # -----------------------------------------------------
    # Start server
    # -----------------------------------------------------

    msg_info "Starting RimWorld Multiplayer Server"

    systemctl daemon-reload

    systemctl enable --now "$SERVICE_NAME"

    msg_ok "Started RimWorld Multiplayer Server"

}


# ---------------------------------------------------------
# Community Scripts UPDATE command
# ---------------------------------------------------------

function update_script() {

    header_info

    check_container_storage
    check_container_resources


    if [[ ! -d "$INSTALL_DIR" ]]; then

        msg_error "No ${APP} Installation Found!"

        exit

    fi


    msg_info "Updating ${APP}"

    /usr/local/sbin/rimworld-update

    msg_ok "Updated ${APP}"

    msg_ok "Updated successfully!"

    exit

}


# ---------------------------------------------------------
# Create LXC
# ---------------------------------------------------------

start

build_container


# ---------------------------------------------------------
# Install application inside LXC
# ---------------------------------------------------------

msg_info "Installing ${APP}"

install_server

msg_ok "Installed ${APP}"


# ---------------------------------------------------------
# Finish
# ---------------------------------------------------------

description

msg_ok "Completed successfully!\n"

echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"

echo
echo -e "${INFO}${YW}RimWorld Multiplayer:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}UDP 30502${CL}"

echo
echo -e "${INFO}${YW}Server commands:${CL}"
echo -e "${TAB}${YW}systemctl status ${SERVICE_NAME}${CL}"
echo -e "${TAB}${YW}systemctl restart ${SERVICE_NAME}${CL}"
echo -e "${TAB}${YW}journalctl -u ${SERVICE_NAME} -f${CL}"
echo
echo -e "${INFO}${YW}Update:${CL}"
echo -e "${TAB}${YW}update${CL}"
echo
