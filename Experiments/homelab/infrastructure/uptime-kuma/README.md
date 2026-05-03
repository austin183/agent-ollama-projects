# Uptime Kuma (Service Monitoring)

## Overview
Uptime Kuma is a lightweight, self-hosted monitoring tool that checks the availability of services and sends notifications when things go down.

**Domain:** Home Infrastructure Services  
**Tech Stack:** `louislam/uptime-kuma:1`  
**RAM Budget:** ~250MB | **Actual:** ~94MB  
**Storage Estimate:** ~300MB

## Quick Start
```bash
cd infrastructure/uptime-kuma
podman compose up -d
```

## Services
| Service | Port | Purpose |
|---------|------|---------|
| uptime-kuma | 3002 (host) / 3001 (container) | Web UI for monitoring |
| test-client | - | Connectivity verification (Alpine) |

## How It Works

Uptime Kuma is a lightweight, self-hosted monitoring tool that checks the availability of services and sends notifications when things go down.

**Architecture:**
- Uptime Kuma runs a Node.js web app on port 3001 (mapped to host port 3002)
- Uses SQLite for storage (no separate database container needed)
- Data persists in the `uptime-kuma_kuma_data` named volume at `/app/data`
- Supports HTTP(s), TCP, DNS, Ping, and many other monitor types
- Includes built-in notification integrations (email, Slack, Discord, Telegram, etc.)

**Data Flow:**
1. User configures monitors via the web UI at `http://<host-ip>:3002`
2. Kuma periodically probes each monitor (HTTP GET, TCP connect, ping, etc.)
3. Results are stored in SQLite and displayed on the status page
4. Notifications are sent when monitors change state (up/down)

## Setup Wizard

Uptime Kuma requires initial user setup via the web interface:

1. Open `http://<your-homelab-ip>:3002` in a browser
2. Create an admin account (username, password, email)
3. Add monitors for your services (e.g., AdGuard Home at `http://homelab-adguard:80`, Prometheus at `http://homelab-prometheus:9090`)
4. Configure notification channels as needed

**Note:** Config is stored in the SQLite database inside the named volume - no manual config files to edit.

## Verification Commands

### Check container status
```bash
podman ps | grep kuma
```
Expected output:
```
homelab-uptime-kuma   Up (healthy)
homelab-uptime-kuma-test   Up
```

### Check health status
```bash
podman inspect homelab-uptime-kuma --format '{{.State.Health.Status}}'
```
Expected output: `healthy`

### Test from test client container
```bash
podman exec homelab-uptime-kuma-test wget --spider -q http://uptime-kuma:3001/ && echo "OK"
```
Expected output: `OK`

### View logs
```bash
podman logs -f homelab-uptime-kuma
```

### Check resource usage
```bash
podman stats homelab-uptime-kuma
```

## Resource Usage

| Resource | Budget | Actual | Notes |
|----------|--------|--------|-------|
| RAM | ~250MB | ~94MB | Well within budget |
| CPU | - | ~4% idle | Minimal when idle |
| Storage | ~300MB | ~50MB | SQLite database grows with monitors |

## Common Pitfalls

- **Port 3002 must be free** - Check with `ss -tlnp | grep 3002` before starting
- **Healthcheck uses curl** - The Uptime Kuma container has curl but not wget (unlike Alpine-based images)
- **No initial user** - The web UI will prompt for setup on first visit; no admin account is created automatically
- **Data persistence** - All config is in the named volume; `podman compose down -v` will delete all monitors

## Stopping the Experiment

```bash
# Stop containers (keep data)
podman compose down

# Stop and remove data
podman compose down -v
```

## Network

This experiment uses the `homelab-uptime-kuma` bridge network. Other containers on this network can reach Uptime Kuma at `http://uptime-kuma:3001`.
