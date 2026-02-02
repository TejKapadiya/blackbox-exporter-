#!/bin/bash
set -e

echo "===== SYSTEM UPDATE ====="
apt update && apt upgrade -y

echo "===== PYTHON ====="
apt install -y python3 python3-pip python3-venv
python3 --version
pip3 --version

echo "===== NGINX ====="
apt install -y nginx
systemctl stop nginx
systemctl disable nginx
systemctl status nginx --no-pager || true

echo "===== APACHE ====="
apt install -y apache2
systemctl stop apache2
systemctl disable apache2
systemctl status apache2 --no-pager || true

echo "===== NODEJS ====="
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt install -y nodejs
node -v
npm -v

echo "===== NPM UPDATE ====="
npm install -g npm@latest
npm -v

npm install pm2 -g



echo "===== BUILD TOOLS ====="
apt install -y build-essential unzip gzip

# =========================
# UPDATED PROMETHEUS SECTION
# =========================

echo "===== PROMETHEUS v2.51.0 ====="

useradd --no-create-home --shell /bin/false prometheus || true

cd /opt
rm -rf /opt/prometheus
rm -f prometheus-2.51.0.linux-amd64.tar.gz

wget -q https://github.com/prometheus/prometheus/releases/download/v2.51.0/prometheus-2.51.0.linux-amd64.tar.gz

file prometheus-2.51.0.linux-amd64.tar.gz | grep gzip || { echo "Prometheus download failed"; exit 1; }

tar -xvf prometheus-2.51.0.linux-amd64.tar.gz
mv prometheus-2.51.0.linux-amd64 prometheus
rm prometheus-2.51.0.linux-amd64.tar.gz

mkdir -p /opt/prometheus/data

chown -R prometheus:prometheus /opt/prometheus
chmod -R 755 /opt/prometheus

cat <<EOF >/opt/prometheus/prometheus.yml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: "prometheus"
    static_configs:
      - targets: ["localhost:9090"]

  - job_name: "node_exporter"
    static_configs:
      - targets: ["localhost:9100"]
EOF

chown prometheus:prometheus /opt/prometheus/prometheus.yml

cat <<EOF >/etc/systemd/system/prometheus.service
[Unit]
Description=Prometheus Monitoring System
Wants=network-online.target
After=network-online.target

[Service]
User=prometheus
Group=prometheus
Type=simple
ExecStart=/opt/prometheus/prometheus \
  --config.file=/opt/prometheus/prometheus.yml \
  --storage.tsdb.path=/opt/prometheus/data \
  --storage.tsdb.retention.time=15d \
  --web.enable-lifecycle \
  --web.console.templates=/opt/prometheus/consoles \
  --web.console.libraries=/opt/prometheus/console_libraries

Restart=always
RestartSec=5
LimitNOFILE=65536
NoNewPrivileges=true
ProtectSystem=full
ProtectHome=true

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reexec
systemctl daemon-reload
systemctl enable prometheus

systemctl start prometheus

# =========================
# NODE EXPORTER
# =========================

echo "===== NODE EXPORTER INSTALL ====="

echo "Creating node_exporter system user"
useradd --no-create-home --shell /bin/false node_exporter || true

echo "Downloading Node Exporter"
cd /opt
rm -rf /opt/node_exporter
rm -f node_exporter-1.8.1.linux-amd64.tar.gz

wget -q https://github.com/prometheus/node_exporter/releases/download/v1.8.1/node_exporter-1.8.1.linux-amd64.tar.gz

file node_exporter-1.8.1.linux-amd64.tar.gz | grep gzip || { echo "Download failed"; exit 1; }

echo "Extracting Node Exporter"
tar -xvf node_exporter-1.8.1.linux-amd64.tar.gz
mv node_exporter-1.8.1.linux-amd64 node_exporter
rm node_exporter-1.8.1.linux-amd64.tar.gz

echo "Setting ownership and permissions"
chown -R node_exporter:node_exporter /opt/node_exporter
chmod -R 755 /opt/node_exporter

echo "Creating systemd service"
cat <<EOF >/etc/systemd/system/node_exporter.service
[Unit]
Description=Prometheus Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/opt/node_exporter/node_exporter \
  --collector.systemd \
  --collector.filesystem.mount-points-exclude=^/(sys|proc|dev|run)(\$|/)

Restart=always
RestartSec=5
NoNewPrivileges=true
ProtectSystem=full
ProtectHome=true

[Install]
WantedBy=multi-user.target
EOF

echo "Reloading systemd and starting service"
systemctl daemon-reload
systemctl enable node_exporter
  systemctl start node_exporter


echo "===== NODE EXPORTER INSTALLED SUCCESSFULLY ====="



# =========================
# GRAFANA
# =========================



echo "===== GRAFANA INSTALL (OSS) ====="

echo "Updating system packages"
apt update && apt upgrade -y

echo "Installing dependencies"
apt install -y apt-transport-https software-properties-common wget gpg

echo "Adding Grafana GPG key"
wget -q -O - https://packages.grafana.com/gpg.key \
| gpg --dearmor -o /usr/share/keyrings/grafana.gpg

echo "Adding Grafana OSS repository"
echo "deb [signed-by=/usr/share/keyrings/grafana.gpg] https://packages.grafana.com/oss/deb stable main" \
> /etc/apt/sources.list.d/grafana.list

echo "Updating package index"
apt update

echo "Installing Grafana OSS"
apt install -y grafana

echo "Verifying Grafana version"
grafana-server -v

echo "Reloading systemd"
systemctl daemon-reload

echo "Stopping Grafana service"
systemctl stop grafana-server || true

echo "Disabling Grafana at boot"
systemctl enable grafana-server
systemctl start grafana-server


echo "===== GRAFANA INSTALL COMPLETE ====="

# =========================
# TOOLS
# =========================

echo "===== TOOLS ====="
apt install -y git htop screen
git --version

sudo apt install mysql-server -y
sudo systemctl stop mysql



# cd /opt
# sudo wget https://github.com/prometheus/blackbox_exporter/releases/download/v0.25.0/blackbox_exporter-0.25.0.linux-amd64.tar.gz
# sudo tar xvf blackbox_exporter-0.25.0.linux-amd64.tar.gz
# sudo mv blackbox_exporter-0.25.0.linux-amd64 blackbox_exporter
 
# sudo mkdir -p /etc/blackbox
 
# cat <<EOF >/etc/blackbox/blackbox.yml
 
 
# modules:
#   http_2xx:
#     prober: http
#     timeout: 5s
# http:
#       valid_http_versions: ["HTTP/1.1", "HTTP/2"]
#       method: GET
 
#   icmp:
#     prober: icmp
#     timeout: 5s
# EOF



 
VERSION="0.25.0"
INSTALL_DIR="/opt/blackbox_exporter"
CONFIG_DIR="/etc/blackbox"
SERVICE_FILE="/etc/systemd/system/blackbox_exporter.service"
 
echo "==> Installing Blackbox Exporter v${VERSION}"
 
# Go to /opt
cd /opt
 
# Download if not already present
if [ ! -f "blackbox_exporter-${VERSION}.linux-amd64.tar.gz" ]; then
  echo "==> Downloading Blackbox Exporter"
  wget https://github.com/prometheus/blackbox_exporter/releases/download/v${VERSION}/blackbox_exporter-${VERSION}.linux-amd64.tar.gz
 
# Extract
echo "==> Extracting"
tar xvf blackbox_exporter-${VERSION}.linux-amd64.tar.gz
 
# Move to final directory
echo "==> Setting up directory"
rm -rf "${INSTALL_DIR}"
mv blackbox_exporter-${VERSION}.linux-amd64 "${INSTALL_DIR}"
 
# Create config directory
echo "==> Creating config directory"
mkdir -p "${CONFIG_DIR}"
 
# Write config file
echo "==> Writing blackbox.yml"
cat <<EOF > "${CONFIG_DIR}/blackbox.yml"
modules:
  http_2xx:
    prober: http
    timeout: 5s
    http:
      valid_http_versions: ["HTTP/1.1", "HTTP/2"]
      method: GET
 
  icmp:
    prober: icmp
    timeout: 5s
EOF
 
# Create systemd service
echo "==> Creating systemd service"
cat <<EOF > "${SERVICE_FILE}"
[Unit]
Description=Prometheus Blackbox Exporter
Wants=network-online.target
After=network-online.target
 
[Service]
User=root
ExecStart=${INSTALL_DIR}/blackbox_exporter \\
  --config.file=${CONFIG_DIR}/blackbox.yml
Restart=always
 
[Install]
WantedBy=multi-user.target
EOF
 
# Reload systemd and start service
echo "==> Enabling and starting service"
systemctl daemon-reexec
systemctl daemon-reload
systemctl enable blackbox_exporter
systemctl restart blackbox_exporter
 
echo "==> Blackbox Exporter installation complete!"
echo "==> Listening on :9115"


echo "===== SETUP COMPLETE ====="






SA_ID=$(curl -s -u admin:admin \
  -H "Content-Type: application/json" \
  -X POST http://localhost:3000/api/serviceaccounts \
  -d '{"name":"cli-sa","role":"Admin"}' \
  | jq -r '.id')

echo "Service Account ID: $SA_ID"


curl -s -u admin:admin \
  -H "Content-Type: application/json" \
  -X POST http://localhost:3000/api/serviceaccounts/$SA_ID/tokens \
  -d '{"name":"cli-token"}' \
  | jq -r '.key'

# ================================
# CONFIG
# ================================
GRAFANA_URL="http://localhost:3000"
GRAFANA_TOKEN="PASTE_YOUR_GRAFANA_API_TOKEN_HERE"
DATASOURCE_NAME="Prometheus"

# ================================
# GET DATASOURCE UID
# ================================
DS_UID=$(curl -s \
  -H "Authorization: Bearer $GRAFANA_TOKEN" \
  "$GRAFANA_URL/api/datasources/name/$DATASOURCE_NAME" \
  | jq -r '.uid')

# ================================
# CREATE BLACKBOX DASHBOARD
# ================================
curl -s -X POST "$GRAFANA_URL/api/dashboards/db" \
  -H "Authorization: Bearer $GRAFANA_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"dashboard\": {
      \"id\": null,
      \"uid\": \"blackbox-dashboard\",
      \"title\": \"Blackbox Exporter Monitoring\",
      \"timezone\": \"browser\",
      \"schemaVersion\": 38,
      \"version\": 1,
      \"refresh\": \"10s\",
      \"panels\": [
        {
          \"type\": \"stat\",
          \"title\": \"Probe Success\",
          \"gridPos\": { \"x\": 0, \"y\": 0, \"w\": 6, \"h\": 5 },
          \"targets\": [
            {
              \"expr\": \"probe_success\",
              \"refId\": \"A\",
              \"datasource\": { \"type\": \"prometheus\", \"uid\": \"$DS_UID\" }
            }
          ]
        },
        {
          \"type\": \"timeseries\",
          \"title\": \"Probe Duration (seconds)\",
          \"gridPos\": { \"x\": 6, \"y\": 0, \"w\": 18, \"h\": 8 },
          \"targets\": [
            {
              \"expr\": \"probe_duration_seconds\",
              \"refId\": \"B\",
              \"datasource\": { \"type\": \"prometheus\", \"uid\": \"$DS_UID\" }
            }
          ]
        },
        {
          \"type\": \"timeseries\",
          \"title\": \"HTTP Status Code\",
          \"gridPos\": { \"x\": 0, \"y\": 8, \"w\": 12, \"h\": 8 },
          \"targets\": [
            {
              \"expr\": \"probe_http_status_code\",
              \"refId\": \"C\",
              \"datasource\": { \"type\": \"prometheus\", \"uid\": \"$DS_UID\" }
            }
          ]
        },
        {
          \"type\": \"timeseries\",
          \"title\": \"DNS Lookup Time\",
          \"gridPos\": { \"x\": 12, \"y\": 8, \"w\": 12, \"h\": 8 },
          \"targets\": [
            {
              \"expr\": \"probe_dns_lookup_time_seconds\",
              \"refId\": \"D\",
              \"datasource\": { \"type\": \"prometheus\", \"uid\": \"$DS_UID\" }
            }
          ]
        }
      ]
    },
    \"overwrite\": true
  }"


