# Prometheus + Grafana Observability Stack

## Overview

Monitor system metrics, container health, and custom metrics with visualization dashboards using Prometheus for time-series data collection and Grafana for visualization.

## Quick Start

```bash
cd observability/prometheus-grafana

# Create .env from template and set a strong password
cp .env.example .env
sed -i 's/CHANGE_ME/your-strong-password/' .env
```

Edit `.env` to replace `your-strong-password` with an actual password.

```bash
podman compose up -d
```

## Services

| Service | Port | Purpose |
|---------|------|---------|
| Prometheus | 9090 | Metrics collection and storage |
| Grafana | 3000 | Visualization dashboards |
| Node Exporter | 9100 | Host system metrics |
| Test Client | - | Network connectivity testing |

## Testing

```bash
# Test Prometheus health
podman exec homelab-prometheus-grafana-test wget -q -O- http://prometheus:9090/-/healthy

# Test Grafana health
podman exec homelab-prometheus-grafana-test wget -q -O- http://grafana:3000/api/health

# Test Node Exporter metrics
podman exec homelab-prometheus-grafana-test wget -q -O- http://node_exporter:9100/metrics | head -20

# Check Prometheus targets
curl http://localhost:9090/api/v1/targets | jq '.data.activeTargets[].labels.job'

# View resource usage
podman stats homelab-prometheus homelab-grafana homelab-node-exporter
```

**Expected Output:**
```
Prometheus health: "Prometheus Server is Healthy."
Grafana health: {"database":"ok","version":"11.1.0",...}
Prometheus targets: ["prometheus", "node_exporter", "grafana"]
```

## How It Works

1. **Prometheus** scrapes metrics from configured targets every 15 seconds
2. **Node Exporter** exposes host system metrics (CPU, memory, disk, network)
3. **Grafana** connects to Prometheus as a data source for visualization
4. All services communicate over isolated `homelab-prometheus-grafana` network

## Adding Grafana Data Source

1. Open Grafana at http://localhost:3000
2. Login with `admin` / password from `.env` file (`GF_SECURITY_ADMIN_PASSWORD`)
3. Click **Connections** → **Data sources** → **Add data source**
4. Select **Prometheus**
5. URL: `http://prometheus:9090`
6. Click **Save & test**

## Importing Dashboards

1. In Grafana, click **Create** → **Dashboard**
2. Click **Import dashboard**
3. Enter dashboard ID (e.g., 1860 for Node Exporter Full)
4. Select Prometheus as data source
5. Click **Import**

**Recommended Dashboard IDs:**
- Node Exporter Full: 1860
- Prometheus Metrics: 16124
- Container Metrics: 11720

## Troubleshooting

- **Grafana won't start**: Check that `.env` file exists and contains `GF_SECURITY_ADMIN_PASSWORD`
- **Prometheus not scraping targets**: Check Prometheus config at `http://localhost:9090/targets` - all should show "UP" status
- **Grafana can't connect to Prometheus**: From within Grafana container, Prometheus is accessible at `http://prometheus:9090` (service name, not localhost)
- **Changing Grafana password**: Update `GF_SECURITY_ADMIN_PASSWORD` in `.env`, then run `podman compose restart grafana`
- **Port 3000 in use**: Check with `ss -tlnp | grep 3000` and stop conflicting services

## Cleanup

```bash
podman compose down -v
```

Note: `podman compose down -v` will delete all metrics and dashboard data.

## Volume Locations

Data persists in Podman managed volumes:

```bash
# View volume locations
podman volume inspect prometheus-grafana_prometheus_grafana_prometheus_data
podman volume inspect prometheus-grafana_prometheus_grafana_grafana_data

# Typically at: ~/.local/share/containers/storage/volumes/
```

## Resources

- **RAM Usage**: ~800MB total (Prometheus 400MB, Grafana 300MB, Node Exporter 50MB)
- **Storage**: ~2GB (metrics retention 15 days, adjustable in compose)
- **Network**: Isolated bridge network `homelab-prometheus-grafana`

## References

- [Prometheus Docs](https://prometheus.io/docs/)
- [Grafana Docs](https://grafana.com/docs/)
- [Grafana Dashboards](https://grafana.com/grafana/dashboards/)
- [Node Exporter Metrics](https://github.com/prometheus/node_exporter#collectors)
