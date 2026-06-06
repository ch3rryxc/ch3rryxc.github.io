#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <listen_ip>"
    exit 1
fi

listenIp="$1"

nodeExporterVersion='1.9.1'
nodeExporterUser='node_exporter'

echo "Installing Node Exporter ${nodeExporterVersion}..."

# Create user
if ! id -u "${nodeExporterUser}" >/dev/null 2>&1; then
    useradd --system --no-create-home --shell /usr/sbin/nologin "${nodeExporterUser}"
fi

# Download and install
tmpDir="$(mktemp -d)"
cd "${tmpDir}"

wget -q "https://github.com/prometheus/node_exporter/releases/download/v${nodeExporterVersion}/node_exporter-${nodeExporterVersion}.linux-amd64.tar.gz"

tar -xzf "node_exporter-${nodeExporterVersion}.linux-amd64.tar.gz"

install -m 0755 \
    "node_exporter-${nodeExporterVersion}.linux-amd64/node_exporter" \
    /usr/local/bin/node_exporter

# Create systemd service
cat >/etc/systemd/system/node_exporter.service <<EOF
[Unit]
Description=Prometheus Node Exporter
After=network.target

[Service]
User=${nodeExporterUser}
Group=${nodeExporterUser}
Type=simple
ExecStart=/usr/local/bin/node_exporter --web.listen-address=${listenIp}:9100

Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Configure UFW
if command -v ufw >/dev/null 2>&1; then
    ufw allow in on tailscale0 proto tcp from 100.64.0.3 to any port 9100 comment 'Node Exporter'
fi

# Enable service
systemctl daemon-reload
systemctl enable --now node_exporter

# Cleanup
rm -rf "${tmpDir}"

echo
echo "Node Exporter installed."
echo "Listening on ${listenIp}:9100"
systemctl --no-pager --full status node_exporter
