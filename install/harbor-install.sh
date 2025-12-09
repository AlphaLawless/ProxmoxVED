#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: AlphaLawless
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://goharbor.io/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y \
  curl \
  sudo \
  mc \
  gpg \
  ca-certificates \
  openssl \
  jq
msg_ok "Installed Dependencies"

msg_info "Installing Docker"
DOCKER_CONFIG_PATH='/etc/docker/daemon.json'
mkdir -p "$(dirname $DOCKER_CONFIG_PATH)"
echo -e '{\n  "log-driver": "journald"\n}' >/etc/docker/daemon.json
$STD sh <(curl -fsSL https://get.docker.com)
msg_ok "Installed Docker"

msg_info "Installing Docker Compose"
DOCKER_COMPOSE_VERSION=$(curl -fsSL https://api.github.com/repos/docker/compose/releases/latest | grep '"tag_name":' | cut -d'"' -f4)
mkdir -p /usr/local/lib/docker/cli-plugins
curl -fsSL "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" \
  -o /usr/local/lib/docker/cli-plugins/docker-compose
chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
msg_ok "Installed Docker Compose"

msg_info "Downloading Harbor"
RELEASE=$(curl -fsSL https://api.github.com/repos/goharbor/harbor/releases/latest | jq -r '.tag_name')
cd /opt
$STD curl -fsSL "https://github.com/goharbor/harbor/releases/download/${RELEASE}/harbor-online-installer-${RELEASE}.tgz" -o harbor-online-installer.tgz
$STD tar -xzf harbor-online-installer.tgz
rm -f harbor-online-installer.tgz
msg_ok "Downloaded Harbor ${RELEASE}"

msg_info "Configuring Harbor"
cd /opt/harbor
LOCAL_IP=$(hostname -I | awk '{print $1}')
cp harbor.yml.tmpl harbor.yml
sed -i "s|hostname: reg.mydomain.com|hostname: ${LOCAL_IP}|g" harbor.yml
sed -i "s|^https:|#https:|g" harbor.yml
sed -i "s|^  port: 443|#  port: 443|g" harbor.yml
sed -i "s|^  certificate:|#  certificate:|g" harbor.yml
sed -i "s|^  private_key:|#  private_key:|g" harbor.yml
msg_ok "Configured Harbor"

msg_info "Installing Harbor with Trivy (this may take a while)"
$STD ./install.sh --with-trivy
msg_ok "Installed Harbor with Trivy"

echo "${RELEASE#v}" >~/.harbor

motd_ssh
customize
cleanup_lxc
