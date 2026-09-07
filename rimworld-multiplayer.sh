#!/usr/bin/env bash

source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)

# Copyright (c) 2026
# License: MIT
#
# Source: https://github.com/rwmt/Multiplayer
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

INSTALL_DIR="/opt/rimworld-multiplayer"
SERVICE_NAME="rimworld-multiplayer"
REPO="rwmt/Multiplayer"
RELEASE="continuous"
DOWNLOAD_URL="https://github.com/${REPO}/releases/download/${RELEASE}/Server-beta.zip"

function install_server() {

  msg_info "Installing dependencies"

  $STD pct exec "$CTID" -- bash -c \
    'apt-get update && apt-get install -y curl unzip ca-certificates wget file'

  msg_ok "Installed dependencies"


  msg_info "Creating installation directory"

  $STD pct exec "$CTID" -- mkdir -p "$INSTALL_DIR"

  msg_ok "Created installation directory"


  msg_info "Downloading RimWorld Multiplayer Server"

  $STD pct exec "$CTID" -- bash -c "
    cd '$INSTALL_DIR'
    rm -f Server-beta.zip
    curl -L --fail --retry 5 --retry-delay 3 \
      -o Server-beta.zip \
      '$DOWNLOAD_URL'
  "

  msg_ok "Downloaded server"


  msg_info "Extracting server"

  $STD pct exec "$CTID" -- bash -c "
    cd '$INSTALL_DIR'
    rm -rf Server
    unzip -q Server-beta.zip
    rm -f Server-beta.zip
  "

  msg_ok "Extracted server"


  msg_info "Configuring RimWorld Multiplayer Server"

  $STD pct exec "$CTID" -- bash -s <<'EOF'

set -e

INSTALL_DIR="/opt/rimworld-multiplayer"
SERVICE_NAME="rimworld-multiplayer"

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
  echo "ERROR: Server.sh not found"
  find "$INSTALL_DIR" -maxdepth 6 -type f
  exit 1
fi

SERVER_DIR="$(dirname "$SERVER_SCRIPT")"

chmod +x "$SERVER_SCRIPT"

echo "$SERVER_DIR" > "$INSTALL_DIR/server_dir.txt"


cat > "/etc/systemd/system/${SERVICE_NAME}.service" <<SERVICE
[Unit]
Description=RimWorld Multiplayer Dedicated Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
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
SERVICE


cat > /usr/local/bin/rimworld-server <<'COMMANDS'
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
    exit 1
    ;;

esac
COMMANDS

chmod +x /usr/local/bin/rimworld-server


cat > /usr/local/sbin/rimworld-update <<'UPDATE'
#!/usr/bin/env bash

set -euo pipefail

INSTALL_DIR="/opt/rimworld-multiplayer"
SERVICE_NAME="rimworld-multiplayer"

DOWNLOAD_URL="https://github.com/rwmt/Multiplayer/releases/download/continuous/Server-beta.zip"

TMP_DIR=$(mktemp -d)

trap 'rm -rf "$TMP_DIR"' EXIT


echo "Stopping RimWorld Multiplayer Server..."

systemctl stop "$SERVICE_NAME" || true


echo "Downloading latest server..."

curl -L \
  --fail \
  --retry 5 \
  --retry-delay 3 \
  -o "$TMP_DIR/Server-beta.zip" \
  "$DOWNLOAD_URL"


echo "Extracting latest server..."

unzip -q \
  "$TMP_DIR/Server-beta.zip" \
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
  echo "ERROR: Server.sh not found"
  systemctl start "$SERVICE_NAME" || true
  exit 1
fi


rm -rf "$INSTALL_DIR/Server"

if [[ -d "$TMP_DIR/new/Server" ]]; then

  cp -a \
    "$TMP_DIR/new/Server" \
    "$INSTALL_DIR/Server"

else

  cp -a \
    "$TMP_DIR/new"/* \
    "$INSTALL_DIR/"

fi


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
  echo "ERROR: Server.sh not found after installation"
  exit 1
fi


chmod +x "$SERVER_SCRIPT"

SERVER_DIR="$(dirname "$SERVER_SCRIPT")"

echo "$SERVER_DIR" > "$INSTALL_DIR/server_dir.txt"


sed -i \
  "s|^WorkingDirectory=.*|WorkingDirectory=${SERVER_DIR}|" \
  "/etc/systemd/system/${SERVICE_NAME}.service"

sed -i \
  "s|^ExecStart=.*|ExecStart=${SERVER_SCRIPT}|" \
  "/etc/systemd/system/${SERVICE_NAME}.service"


systemctl daemon-reload

systemctl start "$SERVICE_NAME"


echo
echo "RimWorld Multiplayer Server updated successfully."
echo
systemctl --no-pager --full status "$SERVICE_NAME" || true

UPDATE

chmod +x /usr/local/sbin/rimworld-update


systemctl daemon-reload

systemctl enable --now "$SERVICE_NAME"

EOF

  msg_ok "Configured and started RimWorld Multiplayer Server"
}


function update_script() {

  header_info

  check_container_storage
  check_container_resources

  if ! $STD pct exec "$CTID" -- test -d "$INSTALL_DIR"; then
    msg_error "No ${APP} installation found!"
    exit 1
  fi

  msg_info "Updating ${APP}"

  $STD pct exec "$CTID" -- /usr/local/sbin/rimworld-update

  msg_ok "Updated ${APP}"

  exit
}


start

build_container


msg_info "Installing ${APP}"

install_server

msg_ok "Installed ${APP}"


description


msg_ok "Completed successfully!"

echo
echo -e "${INFO}${YW}RimWorld Multiplayer${CL}"
echo -e "${TAB}${GATEWAY}UDP 30502${CL}"

echo
echo -e "${INFO}${YW}Server status:${CL}"
echo -e "${TAB}systemctl status ${SERVICE_NAME}"

echo
echo -e "${INFO}${YW}Server logs:${CL}"
echo -e "${TAB}journalctl -u ${SERVICE_NAME} -f"

echo
echo -e "${INFO}${YW}Update:${CL}"
echo -e "${TAB}update"

echo
