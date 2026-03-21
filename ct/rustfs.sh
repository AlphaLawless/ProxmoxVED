#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: AlphaLawless
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/rustfs/rustfs

APP="RustFS"
var_tags="${var_tags:-s3;storage;object-storage}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-10}"
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

  if [[ ! -f /usr/bin/rustfs ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  RELEASE=$(curl -fsSL "https://api.github.com/repos/rustfs/rustfs/releases" | jq -r '.[0].tag_name')
  CURRENT=$(cat ~/.rustfs 2>/dev/null || echo "")

  if [[ -n "$RELEASE" && "$RELEASE" != "$CURRENT" ]]; then
    msg_info "Stopping Service"
    systemctl stop rustfs
    msg_ok "Stopped Service"

    fetch_and_deploy_gh_release "rustfs" "rustfs/rustfs" "prebuild" "${RELEASE}" "/usr/bin" "rustfs-linux-x86_64-gnu-latest.zip"
    chmod +x /usr/bin/rustfs

    msg_info "Starting Service"
    systemctl start rustfs
    msg_ok "Started Service"
    msg_ok "Updated successfully to ${RELEASE}!"
  else
    msg_ok "No update required. ${APP} is already at ${CURRENT}."
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:9001${CL} (Console)"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:9000${CL} (S3 API)"
