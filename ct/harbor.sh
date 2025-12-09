#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/AlphaLawless/ProxmoxVED/refs/heads/create-harbor/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: AlphaLawless
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://goharbor.io/

APP="Harbor"
var_tags="${var_tags:-docker;registry}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-40}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/harbor ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "harbor" "goharbor/harbor"; then
    msg_info "Stopping $APP"
    cd /opt/harbor
    docker compose down
    msg_ok "Stopped $APP"

    msg_info "Creating Backup"
    tar -czf "/opt/harbor_backup_$(date +%F).tar.gz" /opt/harbor/harbor.yml /opt/harbor/data 2>/dev/null || true
    msg_ok "Backup Created"

    msg_info "Updating $APP to ${CHECK_UPDATE_RELEASE}"
    cd /opt
    curl -fsSL "https://github.com/goharbor/harbor/releases/download/${CHECK_UPDATE_RELEASE}/harbor-online-installer-${CHECK_UPDATE_RELEASE}.tgz" -o harbor-online-installer.tgz
    tar -xzf harbor-online-installer.tgz
    rm -f harbor-online-installer.tgz
    cp "/opt/harbor_backup_$(date +%F).tar.gz" /opt/harbor_config_backup.yml 2>/dev/null || true
    cd /opt/harbor
    ./install.sh
    msg_ok "Updated $APP to ${CHECK_UPDATE_RELEASE}"

    msg_info "Starting $APP"
    docker compose up -d
    msg_ok "Started $APP"

    msg_ok "Update Successful"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}${CL}"
