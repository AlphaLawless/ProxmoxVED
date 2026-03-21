#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: AlphaLawless
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/rustfs/rustfs

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

fetch_and_deploy_gh_release "rustfs" "rustfs/rustfs" "prebuild" "latest" "/usr/bin" "rustfs-linux-x86_64-gnu-latest.zip"
chmod +x /usr/bin/rustfs

msg_info "Configuring RustFS"
mkdir -p /opt/rustfs/data /var/log/rustfs

ACCESS_KEY=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | cut -c1-20)
SECRET_KEY=$(openssl rand -base64 36 | tr -dc 'a-zA-Z0-9' | cut -c1-40)

cat <<EOF >/opt/rustfs/.env
RUSTFS_ACCESS_KEY=${ACCESS_KEY}
RUSTFS_SECRET_KEY=${SECRET_KEY}
RUSTFS_VOLUMES=/opt/rustfs/data
RUSTFS_OBS_LOGGER_LEVEL=warn
RUSTFS_OBS_LOG_DIRECTORY=/var/log/rustfs
RUSTFS_OBS_ENVIRONMENT=production
RUSTFS_CORS_ALLOWED_ORIGINS=*
RUSTFS_CONSOLE_CORS_ALLOWED_ORIGINS=*
EOF

chmod 600 /opt/rustfs/.env
msg_ok "Configured RustFS"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/rustfs.service
[Unit]
Description=RustFS Object Storage
After=network.target

[Service]
Type=simple
User=root
EnvironmentFile=/opt/rustfs/.env
ExecStart=/usr/bin/rustfs /opt/rustfs/data
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now rustfs
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
