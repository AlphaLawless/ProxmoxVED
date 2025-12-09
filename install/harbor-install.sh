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

setup_docker

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

msg_info "Creating Health Check Service"
mkdir -p /opt/custom_healthcheck
cat <<'EOF' >/opt/custom_healthcheck/harbor-healthcheck.sh
#!/bin/bash
# Harbor Health Check Script
# Ensures all Harbor containers are running after system boot

MAX_RETRIES=30
RETRY_INTERVAL=10

cd /opt/harbor

for i in $(seq 1 $MAX_RETRIES); do
    NOT_RUNNING=$(docker compose ps --format json | jq -r 'select(.State != "running")' | wc -l)

    if [[ "$NOT_RUNNING" -eq 0 ]]; then
        echo "All Harbor containers are running"
        exit 0
    fi

    echo "Waiting for containers... (attempt $i/$MAX_RETRIES)"
    docker compose up -d
    sleep $RETRY_INTERVAL
done

echo "Harbor failed to start all containers"
exit 1
EOF
chmod +x /opt/custom_healthcheck/harbor-healthcheck.sh

cat <<EOF >/etc/systemd/system/harbor-healthcheck.service
[Unit]
Description=Harbor Health Check
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
ExecStart=/opt/custom_healthcheck/harbor-healthcheck.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable -q harbor-healthcheck
msg_ok "Created Health Check Service"

echo "${RELEASE#v}" >~/.harbor

motd_ssh
customize
cleanup_lxc
