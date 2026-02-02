
# ============================================================
# Infrastructure Bootstrap Script
# Prometheus · Blackbox Exporter · Grafana
# Ubuntu 20.04 / 22.04
# ============================================================

PROM_VERSION="2.51.0"
BLACKBOX_VERSION="0.25.0"

PROM_USER="prometheus"
BLACKBOX_USER="blackbox"

PROM_DIR="/opt/prometheus"
BLACKBOX_DIR="/opt/blackbox_exporter"
PROM_DATA_DIR="/opt/prometheus/data"

GRAFANA_TOKEN="PASTE_YOUR_GRAFANA_API_TOKEN_HERE"

# ------------------------------------------------------------
# Root check
# ------------------------------------------------------------
if [[ "$EUID" -ne 0 ]]; then
  echo "Run as root"
  exit 1
fi

# ------------------------------------------------------------
# System update & deps
# ------------------------------------------------------------
apt-get update -y
apt-get upgrade -y

apt-get install -y \
  build-essential \
  unzip \
  gzip \
  curl \
  wget \
  git \
  htop \
  screen \
  apt-transport-https \
  software-properties-common

# ------------------------------------------------------------
# Users
# ------------------------------------------------------------
id -u $PROM_USER &>/dev/null || useradd --system --no-create-home --shell /usr/sbin/nologin $PROM_USER
id -u $BLACKBOX_USER &>/dev/null || useradd --system --no-create-home --shell /usr/sbin/nologin $BLACKBOX_USER

# ------------------------------------------------------------
# Prometheus
# ------------------------------------------------------------
mkdir -p $PROM_DIR $PROM_DATA_DIR
cd /tmp

if [[ ! -f prometheus-$PROM_VERSION.linux-amd64.tar.gz ]]; then
  wget https://github.com/prometheus/prometheus/releases/download/v$PROM_VERSION/prometheus-$PROM_VERSION.linux-amd64.tar.gz
fi

tar xzf prometheus-$PROM_VERSION.linux-amd64.tar.gz
cp prometheus-$PROM_VERSION.linux-amd64/prometheus $PROM_DIR/
cp prometheus-$PROM_VERSION.linux-amd64/promtool $PROM_DIR/

cat >/opt/prometheus/prometheus.yml <<EOF
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: "prometheus"
    static_configs:
      - targets: ["localhost:9090"]
EOF

chown -R $PROM_USER:$PROM_USER $PROM_DIR

cat >/etc/systemd/system/prometheus.service <<EOF
[Unit]
Description=Prometheus
After=network.target

[Service]
User=$PROM_USER
Group=$PROM_USER
Type=simple
ExecStart=$PROM_DIR/prometheus \\
  --config.file=$PROM_DIR/prometheus.yml \\
  --storage.tsdb.path=$PROM_DATA_DIR \\
  --storage.tsdb.retention.time=15d

NoNewPrivileges=true
ProtectSystem=full
ProtectHome=true

[Install]
WantedBy=multi-user.target
EOF

# ------------------------------------------------------------
# Blackbox Exporter
# ------------------------------------------------------------
mkdir -p $BLACKBOX_DIR /etc/blackbox
cd /tmp

if [[ ! -f blackbox_exporter-$BLACKBOX_VERSION.linux-amd64.tar.gz ]]; then
  wget https://github.com/prometheus/blackbox_exporter/releases/download/v$BLACKBOX_VERSION/blackbox_exporter-$BLACKBOX_VERSION.linux-amd64.tar.gz
fi

tar xzf blackbox_exporter-$BLACKBOX_VERSION.linux-amd64.tar.gz
cp blackbox_exporter-$BLACKBOX_VERSION.linux-amd64/blackbox_exporter $BLACKBOX_DIR/

cat >/etc/blackbox/blackbox.yml <<EOF
modules:
  http_2xx:
    prober: http
    timeout: 5s
    http:
      valid_http_versions:
        - HTTP/1.1
        - HTTP/2
      method: GET

  icmp:
    prober: icmp
    timeout: 5s
EOF

chown -R $BLACKBOX_USER:$BLACKBOX_USER $BLACKBOX_DIR /etc/blackbox

cat >/etc/systemd/system/blackbox_exporter.service <<EOF
[Unit]
Description=Blackbox Exporter
After=network.target

[Service]
User=$BLACKBOX_USER
Group=$BLACKBOX_USER
Type=simple
ExecStart=$BLACKBOX_DIR/blackbox_exporter \\
  --config.file=/etc/blackbox/blackbox.yml

NoNewPrivileges=true
ProtectSystem=full
ProtectHome=true

[Install]
WantedBy=multi-user.target
EOF

# ------------------------------------------------------------
# Grafana OSS
# ------------------------------------------------------------
if ! dpkg -l | grep -q grafana; then
  wget -q -O - https://packages.grafana.com/gpg.key | apt-key add -
  add-apt-repository "deb https://packages.grafana.com/oss/deb stable main"
  apt-get update -y
  apt-get install -y grafana
fi

# ------------------------------------------------------------
# systemd
# ------------------------------------------------------------
systemctl daemon-reload
systemctl enable prometheus blackbox_exporter grafana-server
systemctl restart prometheus blackbox_exporter grafana-server

# ------------------------------------------------------------
# Grafana API Automation (requires token)
# ------------------------------------------------------------
if [[ "$GRAFANA_TOKEN" != "PASTE_YOUR_GRAFANA_API_TOKEN_HERE" ]]; then
  # Prometheus datasource lookup
  curl -s -X POST http://localhost:3000/api/datasources \
    -H "Authorization: Bearer $GRAFANA_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{
      "name": "Prometheus",
      "type": "prometheus",
      "access": "proxy",
      "url": "http://localhost:9090",
      "isDefault": true
    }'

  # Blackbox dashboard
  curl -s -X POST http://localhost:3000/api/dashboards/db \
    -H "Authorization: Bearer $GRAFANA_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{
      "dashboard": {
        "title": "Blackbox Exporter Monitoring",
        "panels": []
      },
      "overwrite": true
    }'
else
  echo "Grafana token not set. Skipping API automation."
fi

echo "Bootstrap complete."
echo "Prometheus  : http://<server-ip>:9090"
echo "Grafana     : http://<server-ip>:3000"
echo "Blackbox    : http://<server-ip>:9115/metrics"
