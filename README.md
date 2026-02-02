# blackbox-exporter
Infrastructure Bootstrap Script
Prometheus ·  Blackbox Exporter · Grafana
Overview
This repository contains a single automated bootstrap script that provisions a complete monitoring and application-ready server on Ubuntu (20.04 / 22.04).
The script installs, configures, and manages:
•	Core system dependencies
•	Prometheus monitoring stack
•	Blackbox Exporter
•	Grafana OSS
•	Grafana API automation (service account + dashboard)
The script is idempotent, systemd-based, and suitable for labs, staging, and controlled environments.
________________________________________
Components Installed
System & Runtime
•	Build tools (build-essential, unzip, gzip)
•	Git, htop, screen
Monitoring Stack
•	Prometheus v2.51.0
•	Blackbox Exporter v0.25.0
•	Grafana OSS (latest stable)
________________________________________
 
Directory Layout
/opt/
├── prometheus/
│   ├── prometheus
│   ├── prometheus.yml
│   └── data/
├── blackbox_exporter/
│   └── blackbox_exporter
/etc/
├── blackbox/
│   └── blackbox.yml
/etc/systemd/system/
├── prometheus.service
└── blackbox_exporter.service
________________________________________
Services & Ports
Service	Port	Status
Prometheus	9090	Enabled
Blackbox Exporter	9115	Enabled
Grafana	3000	Enabled
________________________________________
 
What the Script Does (High Level)
1.	Updates the system
2.	Installs core dependencies
3.	Installs Prometheus with:
o	Custom config
o	15-day retention
o	systemd hardening
4.	Installs Blackbox Exporter with HTTP + ICMP probes
5.	Installs Grafana OSS
6.	Creates:
o	Grafana service account
o	Grafana API token
o	Prometheus datasource lookup
o	Blackbox monitoring dashboard via API
________________________________________
Prometheus Configuration
Scrape targets included by default:
- job_name: "prometheus"
  targets: ["localhost:9090"]

Blackbox jobs should be added manually based on targets.
________________________________________
Blackbox Exporter Modules
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
________________________________________
Grafana Automation
Service Account Creation
The script creates a Grafana Admin service account via API:
•	Name: cli-sa
•	Token: cli-token
Dashboard Created
Dashboard Name:
Blackbox Exporter Monitoring
Panels Included:
•	Probe Success
•	Probe Duration
•	HTTP Status Code
•	DNS Lookup Time
Dashboard is created using:
POST /api/dashboards/db
________________________________________
Required Manual Step (Important)
After Grafana starts, replace the token placeholder:
GRAFANA_TOKEN="PASTE_YOUR_GRAFANA_API_TOKEN_HERE"
Use the token printed by:
curl -u admin:admin http://localhost:3000/api/serviceaccounts/{id}/tokens
________________________________________
How to Run
sudo chmod +x setup.sh
sudo ./setup.sh
Must be executed as root or with sudo.
________________________________________
Verification Checklist
systemctl status Prometheus
systemctl status blackbox_exporter
systemctl status grafana-server
Web access:
•	Prometheus → http://<server-ip>:9090
•	Grafana → http://<server-ip>:3000
•	Blackbox metrics → http://<server-ip>:9115/metrics
________________________________________
Security Notes
•	Dedicated system users for exporters
•	NoNewPrivileges=true
•	ProtectSystem=full
•	ProtectHome=true
•	No services exposed externally by default (firewall required)
________________________________________
Intended Use
•	Monitoring labs
•	DevOps learning environments
•	Internal infrastructure observability
•	SOC / NOC tooling base
•	Prometheus + Grafana automation reference
________________________________________
Not Included (By Design)
•	TLS / HTTPS
•	Authentication hardening
•	Firewall rules
•	Alertmanager
•	Remote storage (Mimir / Thanos)
These should be layered after baseline provisioning.

