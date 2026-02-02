#!/usr/bin/env bash
set -euo pipefail

############################
# CONFIG (ENV VAR OVERRIDES)
############################
GRAFANA_ADMIN_USER="${GRAFANA_ADMIN_USER:-admin}"
GRAFANA_ADMIN_PASSWORD="${GRAFANA_ADMIN_PASSWORD:-admin}"
PROM_VERSION="2.49.1"
BB_VERSION="0.25.0"
GRAFANA_PORT=3000
RETRY_COUNT=5
RETRY_DELAY=5

############################
# UTILITIES
############################
log() { echo "[INFO] $*"; }
err() { echo "[ERROR] $*" >&2; }

retry() {
  local n=0
  until "$@"; do
    n=$((n+1))
    if [[ $n -ge $RETRY_COUNT ]]; then
      err "Command failed after $RETRY_COUNT attempts: $*"
      return 1
    fi
    log "Retrying ($n/$RETRY_COUNT)..."
    sleep "$RETRY_DELAY"
  done
}

need_root() {
  if [[ $EUID -ne 0 ]]; then
    if command -v sudo >/dev/null 2>&1; then
      exec sudo -E bash "$0"
    else
      err "Root privileges required and sudo not available"
      exit 1
    fi
  fi
}

service_running() {
  systemctl is-active --quiet "$1"
}

############################
# INSTALL PACKAGES
############################
install_packages() {
  log "Installing base packages"
  retry apt-get update -y
  retry apt-get install -y curl wget tar apt-transport-https software-properties-common
}

############################
# PROMETHEUS
############################
install_prometheus() {
  if id prometheus >/dev/null 2>&1; then
    log "Prometheus already installed"
    return
  fi

  log "Installing Prometheus"
  useradd --no-create-home --shell /bin/false prometheus
  mkdir -p /etc/prometheus /var/lib/prometheus

  retry wget -q https://github.com/prometheus/prometheus/releases/download/v${PROM_VERSION}/prometheus-${PROM_VERSION}.linux-amd64.tar.gz
  tar xf prometheus-${PROM_VERSION}.linux-amd64.tar.gz
  cp prometheus-${PROM_VERSION}.linux-amd64/{prometheus,promtool} /usr/local/bin/
  cp -r prometheus-${PROM_VERSION}.linux-amd64/{consoles,console_libraries} /etc/prometheus/

  cat >/etc/prometheus/prometheus.yml <<EOF
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: prometheus
    static_configs:
      - targets: ['localhost:9090']

  - job_name: blackbox
    metrics_path: /probe
    params:
      module: [http_2xx]
    static_configs:
      - targets:
        - https://example.com
    relabel_configs:
      - source_labels: [__address__]
        target_label: __param_target
      - source_labels: [__param_target]
        target_label: instance
      - target_label: __address__
        replacement: localhost:9115
EOF

  chown -R prometheus:prometheus /etc/prometheus /var/lib/prometheus

  cat >/etc/systemd/system/prometheus.service <<EOF
[Unit]
Description=Prometheus
After=network.target

[Service]
User=prometheus
ExecStart=/usr/local/bin/prometheus \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/var/lib/prometheus

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reexec
  systemctl enable --now prometheus
}

############################
# BLACKBOX EXPORTER
############################
install_blackbox() {
  if id blackbox >/dev/null 2>&1; then
    log "Blackbox Exporter already installed"
    return
  fi

  log "Installing Blackbox Exporter"
  useradd --no-create-home --shell /bin/false blackbox
  mkdir -p /etc/blackbox

  retry wget -q https://github.com/prometheus/blackbox_exporter/releases/download/v${BB_VERSION}/blackbox_exporter-${BB_VERSION}.linux-amd64.tar.gz
  tar xf blackbox_exporter-${BB_VERSION}.linux-amd64.tar.gz
  cp blackbox_exporter-${BB_VERSION}.linux-amd64/blackbox_exporter /usr/local/bin/

  cat >/etc/blackbox/blackbox.yml <<EOF
modules:
  http_2xx:
    prober: http
    timeout: 5s
  tcp_connect:
    prober: tcp
    timeout: 5s
  icmp:
    prober: icmp
    timeout: 5s
EOF

  chown -R blackbox:blackbox /etc/blackbox

  cat >/etc/systemd/system/blackbox.service <<EOF
[Unit]
Description=Blackbox Exporter
After=network.target

[Service]
User=blackbox
ExecStart=/usr/local/bin/blackbox_exporter --config.file=/etc/blackbox/blackbox.yml

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reexec
  systemctl enable --now blackbox
}

############################
# GRAFANA
############################
install_grafana() {
  if service_running grafana-server; then
    log "Grafana already installed"
    return
  fi

  log "Installing Grafana"
  retry wget -q -O /usr/share/keyrings/grafana.key https://apt.grafana.com/gpg.key
  echo "deb [signed-by=/usr/share/keyrings/grafana.key] https://apt.grafana.com stable main" \
    >/etc/apt/sources.list.d/grafana.list

  retry apt-get update -y
  retry apt-get install -y grafana

  systemctl enable --now grafana-server
}

configure_grafana() {
  log "Configuring Grafana datasource and dashboards"
  sleep 10

  curl -s -X POST http://localhost:${GRAFANA_PORT}/api/admin/users/1/password \
    -u "${GRAFANA_ADMIN_USER}:${GRAFANA_ADMIN_PASSWORD}" \
    -H "Content-Type: application/json" \
    -d "{\"password\":\"${GRAFANA_ADMIN_PASSWORD}\"}" || true

  curl -s -X POST http://localhost:${GRAFANA_PORT}/api/datasources \
    -u "${GRAFANA_ADMIN_USER}:${GRAFANA_ADMIN_PASSWORD}" \
    -H "Content-Type: application/json" \
    -d '{
      "name":"Prometheus",
      "type":"prometheus",
      "access":"proxy",
      "url":"http://localhost:9090",
      "isDefault":true
    }' || true

  for DASH in 7587 1860; do
    curl -s -X POST http://localhost:${GRAFANA_PORT}/api/dashboards/import \
      -u "${GRAFANA_ADMIN_USER}:${GRAFANA_ADMIN_PASSWORD}" \
      -H "Content-Type: application/json" \
      -d "{\"dashboard\":{\"id\":$DASH},\"overwrite\":true,\"inputs\":[]}"
  done
}

############################
# VALIDATION
############################
validate() {
  log "Validating services"
  service_running prometheus
  service_running blackbox
  service_running grafana-server

  curl -sf http://localhost:9090/-/ready >/dev/null
  curl -sf http://localhost:9115/metrics >/dev/null
  curl -sf http://localhost:${GRAFANA_PORT}/api/health >/dev/null
}

############################
# MAIN
############################
need_root
install_packages
install_prometheus
install_blackbox
install_grafana
configure_grafana
validate

log "Setup complete!"
log "Grafana: http://localhost:${GRAFANA_PORT}"
log "Prometheus: http://localhost:9090"
log "Grafana credentials: ${GRAFANA_ADMIN_USER} / ${GRAFANA_ADMIN_PASSWORD}"

 
