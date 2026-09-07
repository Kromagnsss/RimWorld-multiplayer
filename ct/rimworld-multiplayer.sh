#!/usr/bin/env bash

# Copyright (c) 2026 Kromagnsss
# SPDX-License-Identifier: MIT

_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"

source "$_cs_boot" 2>/dev/null || \
source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")

APP="RimWorld Multiplayer"

var_tags="${var_tags:-games;rimworld;multiplayer}"
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

# -----------------------------------------------------------------------------
# Update LXC
# -----------------------------------------------------------------------------

function update_script() {
    header_info
    check_container_storage
    check_container_resources

    if [[ ! -d /var ]]; then
        msg_error "No ${APP} installation found!"
        exit 1
    fi

    msg_info "Updating ${APP} LXC"

    $STD apt-get update
    $STD apt-get -y upgrade

    msg_ok "Updated ${APP} LXC"
    msg_ok "Updated successfully!"
    exit
}

# -----------------------------------------------------------------------------
# Create LXC
# -----------------------------------------------------------------------------

start
build_container
description

msg_ok "Completed successfully!"
echo -e "${CREATING}${GN}${APP} LXC has been successfully created!${CL}"
echo -e "${INFO}${YW}Container ID:${CL} ${PCTID}"
echo -e "${INFO}${YW}IP address:${CL} ${IP}"
echo -e "${INFO}${YW}Server port:${CL} UDP 30502"
echo
echo -e "${INFO}${YW}After installation, manage the server with:${CL}"
echo -e "  ${TAB3}rimworld status"
echo -e "  ${TAB3}rimworld logs"
echo -e "  ${TAB3}rimworld update"