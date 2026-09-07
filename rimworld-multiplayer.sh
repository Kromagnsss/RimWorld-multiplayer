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


# ==============================================================================
# VARIABLES
# ==============================================================================

INSTALL_DIR="/opt/rimworld-multiplayer"
SERVER_DIR="${INSTALL_DIR}/Server/Linux"

SERVICE_NAME="rimworld-multiplayer"

DOWNLOAD_URL="https://github.com/rwmt/Multiplayer/releases/download/continuous/Server-beta.zip"

DOTNET_VERSION="8.0"


# ==============================================================================
# UPDATE
# ==============================================================================

function update_script() {

    header_info

    check_container_storage
    check_container_resources

    if [[ ! -f "${INSTALL_DIR}/Server/Linux/Server.dll" ]]; then
        msg_error "No ${APP} installation found!"
        exit 1
    fi

    msg_info "Updating ${APP}"

    systemctl stop "${SERVICE_NAME}" 2>/dev/null || true

    TMP_DIR="$(mktemp -d)"

    trap 'rm -rf "$TMP_DIR"' EXIT

    msg_info "Downloading latest RimWorld Multiplayer server"

    curl -L \
        --fail \
        --retry 5 \
        --retry-delay 3 \
        -o "${TMP_DIR}/Server-beta.zip" \
        "${DOWNLOAD_URL}"

    msg_ok "Downloaded latest server"

    msg_info "Extracting update"

    mkdir -p "${TMP_DIR}/new"

    unzip -q \
        "${TMP_DIR}/Server-beta.zip" \
        -d "${TMP_DIR}/new"

    if [[ ! -f "${TMP_DIR}/new/Server/Linux/Server.dll" ]]; then
        msg_error "Invalid server archive: Server/Linux/Server.dll not found"
        exit 1
    fi

    msg_ok "Archive verified"

    msg_info "Installing update"

    rm -rf "${INSTALL_DIR}/Server"

    cp -a \
        "${TMP_DIR}/new/Server" \
        "${INSTALL_DIR}/"

    chmod +x "${SERVER_DIR}/Server.sh"

    msg_ok "Server files updated"

    systemctl daemon-reload
    systemctl start "${SERVICE_NAME}"

    msg_ok "Started ${APP}"
    msg_ok "Updated successfully!"

    exit 0
}


# ==============================================================================
# INSTALLATION
# ==============================================================================

function install_rimworld() {

    # --------------------------------------------------------------------------
    # Dependencies
    # --------------------------------------------------------------------------

    msg_info "Installing dependencies"

    $STD apt-get update

    $STD apt-get install -y \
        ca-certificates \
        curl \
        wget \
        unzip \
        file

    msg_ok "Installed dependencies"


    # --------------------------------------------------------------------------
    # Microsoft repository
    # --------------------------------------------------------------------------

    msg_info "Installing Microsoft package repository"

    if [[ ! -f /etc/apt/sources.list.d/microsoft-prod.list ]]; then

        wget \
            -q \
            "https://packages.microsoft.com/config/debian/13/packages-microsoft-prod.deb" \
            -O /tmp/packages-microsoft-prod.deb

        dpkg -i /tmp/packages-microsoft-prod.deb

        rm -f /tmp/packages-microsoft-prod.deb

    fi

    msg_ok "Microsoft repository configured"


    # --------------------------------------------------------------------------
    # .NET 8 Runtime
    # --------------------------------------------------------------------------

    msg_info "Installing .NET ${DOTNET_VERSION} Runtime"

    $STD apt-get update

    $STD apt-get install -y dotnet-runtime-8.0

    if ! command -v dotnet >/dev/null 2>&1; then
        msg_error ".NET Runtime installation failed"
        exit 1
    fi

    if ! dotnet --list-runtimes | grep -q "^Microsoft.NETCore.App 8\.0"; then
        msg_error ".NET 8 Runtime not found"
        dotnet --list-runtimes
        exit 1
    fi

    msg_ok "Installed .NET ${DOTNET_VERSION} Runtime"


    # --------------------------------------------------------------------------
    # Installation directory
    # --------------------------------------------------------------------------

    msg_info "Creating installation directory"

    mkdir -p "${INSTALL_DIR}"

    msg_ok "Created ${INSTALL_DIR}"


    # --------------------------------------------------------------------------
    # Download server
    # --------------------------------------------------------------------------

    msg_info "Downloading RimWorld Multiplayer Server"

    cd "${INSTALL_DIR}"

    rm -f Server-beta.zip

    curl \
        -L \
        --fail \
        --retry 5 \
        --retry-delay 3 \
        -o Server-beta.zip \
        "${DOWNLOAD_URL}"

    msg_ok "Downloaded server"


    # --------------------------------------------------------------------------
    # Extract
    # --------------------------------------------------------------------------

    msg_info "Extracting RimWorld Multiplayer Server"

    rm -rf "${INSTALL_DIR}/Server"

    unzip -q \
        "${INSTALL_DIR}/Server-beta.zip" \
        -d "${INSTALL_DIR}"

    rm -f "${INSTALL_DIR}/Server-beta.zip"

    if [[ ! -f "${SERVER_DIR}/Server.dll" ]]; then
        msg_error "Invalid archive: Server/Linux/Server.dll not found"
        exit 1
    fi

    if [[ ! -f "${SERVER_DIR}/Server.sh" ]]; then
        msg_error "Invalid archive: Server/Linux/Server.sh not found"
        exit 1
    fi

    chmod +x "${SERVER_DIR}/Server.sh"

    msg_ok "Server extracted"


    # --------------------------------------------------------------------------
    # Verify .NET runtime configuration
    # --------------------------------------------------------------------------

    msg_info "Checking server runtime"

    if ! grep -q '"tfm": "net8.0"' \
        "${SERVER_DIR}/Server.runtimeconfig.json"; then

        msg_error "The RimWorld server does not target .NET 8"
        cat "${SERVER_DIR}/Server.runtimeconfig.json"
        exit 1
    fi

    msg_ok "RimWorld server requires .NET 8"


    # --------------------------------------------------------------------------
    # Test server
    # --------------------------------------------------------------------------

    msg_info "Testing RimWorld Multiplayer Server"

    if ! timeout 5 \
        "${SERVER_DIR}/Server.sh" \
        >/tmp/rimworld-test.log 2>&1; then

        TEST_EXIT=$?

        # timeout returns 124 when the server is still running,
        # which is a successful test for a long-running server.
        if [[ "${TEST_EXIT}" != "124" ]]; then
            cat /tmp/rimworld-test.log
            msg_error "RimWorld Multiplayer Server failed to start"
            exit 1
        fi
    fi

    rm -f /tmp/rimworld-test.log

    msg_ok "Server executable works"


    # --------------------------------------------------------------------------
    # systemd service
    # --------------------------------------------------------------------------

    msg_info "Creating systemd service"

    cat > "/etc/systemd/system/${SERVICE_NAME}.service" <<EOF
[Unit]
Description=RimWorld Multiplayer Dedicated Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=${SERVER_DIR}
ExecStart=${SERVER_DIR}/Server.sh
Restart=always
RestartSec=5
KillSignal=SIGINT
TimeoutStopSec=30

# RimWorld Multiplayer uses UDP port 30502 by default.
# No --port parameter is required.

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload

    systemctl enable "${SERVICE_NAME}"

    msg_ok "Created systemd service"


    # --------------------------------------------------------------------------
    # Management command
    # --------------------------------------------------------------------------

    msg_info "Creating management command"

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
        systemctl status rimworld-multiplayer --no-pager
        ;;

    logs)
        journalctl -u rimworld-multiplayer -f
        ;;

    update)
        update
        ;;

    *)
        echo
        echo "RimWorld Multiplayer Server"
        echo
        echo "Usage:"
        echo
        echo "  rimworld-server start"
        echo "  rimworld-server stop"
        echo "  rimworld-server restart"
        echo "  rimworld-server status"
        echo "  rimworld-server logs"
        echo "  rimworld-server update"
        echo

        exit 1
        ;;

esac
EOF

    chmod +x /usr/local/bin/rimworld-server

    msg_ok "Created management command"


    # --------------------------------------------------------------------------
    # Server information
    # --------------------------------------------------------------------------

    cat > "${INSTALL_DIR}/README.txt" <<EOF
RimWorld Multiplayer Dedicated Server
=====================================

Installation:
${INSTALL_DIR}

Server:
${SERVER_DIR}

Protocol:
UDP

Port:
30502

Service:
${SERVICE_NAME}

Commands:

systemctl status ${SERVICE_NAME}
systemctl start ${SERVICE_NAME}
systemctl stop ${SERVICE_NAME}
systemctl restart ${SERVICE_NAME}

Logs:

journalctl -u ${SERVICE_NAME} -f

Management:

rimworld-server start
rimworld-server stop
rimworld-server restart
rimworld-server status
rimworld-server logs
rimworld-server update

Update:

update

.NET Runtime:

.NET 8
EOF


    # --------------------------------------------------------------------------
    # Start server
    # --------------------------------------------------------------------------

    msg_info "Starting RimWorld Multiplayer Server"

    systemctl start "${SERVICE_NAME}"

    sleep 2

    if ! systemctl is-active --quiet "${SERVICE_NAME}"; then

        msg_error "RimWorld Multiplayer Server failed to start"

        systemctl status \
            "${SERVICE_NAME}" \
            --no-pager \
            || true

        journalctl \
            -u "${SERVICE_NAME}" \
            -n 30 \
            --no-pager \
            || true

        exit 1
    fi

    msg_ok "RimWorld Multiplayer Server started"


    # --------------------------------------------------------------------------
    # Verify UDP port
    # --------------------------------------------------------------------------

    if ss -lun | grep -q ':30502 '; then
        msg_ok "UDP port 30502 is listening"
    else
        msg_warn "UDP port 30502 is not detected yet"
        msg_warn "Check: ss -lunp | grep 30502"
    fi
}


# ==============================================================================
# MAIN
# ==============================================================================

start

build_container

msg_info "Installing ${APP}"

install_rimworld

msg_ok "Installed ${APP}"

description

msg_ok "Completed successfully!"

echo

echo -e "${INFO}${YW}RimWorld Multiplayer Server${CL}"
echo -e "${TAB}${GATEWAY}UDP 30502${CL}"

echo

echo -e "${INFO}${YW}Service:${CL}"
echo -e "${TAB}systemctl status ${SERVICE_NAME}${CL}"

echo

echo -e "${INFO}${YW}Logs:${CL}"
echo -e "${TAB}journalctl -u ${SERVICE_NAME} -f${CL}"

echo

echo -e "${INFO}${YW}Management:${CL}"
echo -e "${TAB}rimworld-server status${CL}"
echo -e "${TAB}rimworld-server logs${CL}"
echo -e "${TAB}rimworld-server update${CL}"

echo
