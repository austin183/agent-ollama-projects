# AdGuard Home - DNS Ad Blocking

AdGuard Home is a network-wide ad and tracker blocking DNS server. Once configured as your router's DNS server (or set individually on devices), it filters out ads, tracking domains, and malicious sites for all devices on your network.

### How It Works

**DNS Resolution Flow:**
```
Your Device → AdGuard Home → Upstream DNS → Internet
     ↓                  ↓                  ↓
  "What's         "Is this           "Here's
  google.com?"    blocked?"           the IP"
     ↓                  ↓                  ↓
  Gets IP          "No, ask           Returns
  back             upstream"             IP
```

1. **Your device queries AdGuard** - Instead of contacting Google/Cloudflare DNS directly, your device sends DNS queries to AdGuard Home (e.g., `<YOUR_INTERNAL_IP>:5053`)

2. **AdGuard checks blocklists** - Before forwarding, AdGuard checks if the domain matches any blocked patterns (ads, trackers, malware, adult content)

3. **Blocked domains return `0.0.0.0`** - If matched, the query returns a "black hole" IP, preventing the connection (DNS sinkholing)

4. **Allowed queries forward to upstream** - Legitimate queries are forwarded to upstream DNS servers (Google, Cloudflare, Quad9, etc.) and the result is returned to your device

**Key Points:**
- **Full DNS replacement** - Your device never contacts public DNS directly; AdGuard is the intermediary
- **Network-wide coverage** - Works for all devices configured to use it (phones, smart TVs, IoT, computers)
- **No client software needed** - Configuration is at the DNS level, not per-application
- **Logs all queries** - You can see exactly what domains every device on your network requests

**What CAN be blocked:**
- ✅ Display ads on websites
- ✅ Tracking/analytics domains
- ✅ Malware/phishing sites
- ✅ Adult content (with parental controls)
- ✅ Ads in mobile apps
- ✅ Smart TV ads

**What CANNOT be blocked:**
- ❌ YouTube/Twitch video ads (same domain as content)
- ❌ Facebook/Instagram sponsored posts (embedded in feed)
- ❌ Any ad sharing a domain with legitimate content

> **Note:** DNS-level blocking catches ~60-80% of ads. For the rest, you'd need browser extensions or content-blocking proxies.

### Why AdGuard Home over Pi-hole?
- Better out-of-the-box UI/UX
- Built-in DNS-over-HTTPS (DoH) and DNS-over-TLS (DoT) support
- More features enabled by default
- Slightly more modern codebase

---

## Quick Start

```bash
cd ~/homelab/infrastructure/adguard-home
mkdir -p work conf
podman compose up -d
```

### First-Time Setup Wizard

**⚠️ Important:** AdGuard Home's DNS server will NOT work until you complete the setup wizard. The container will start, but DNS queries will fail until configuration is finalized.  If you want to redo the set up wizard, delete the file at conf/AdGuardHome.yaml file.

1. **Open the setup wizard:** `http://localhost:3000` (or `http://<YOUR_INTERNAL_IP>:3000` from other devices)

2. **Interface address:** Keep default `0.0.0.0` (listens on all interfaces)

3. **Web UI port:** 
   - **Keep default `3000`** to match our docker-compose.yml configuration
   - If you change this to port `80`, you'll access it at `http://localhost:8080` after setup
   - ⚠️ **Note:** The wizard defaults to port 80 for the web interface, but our compose file maps port 3000

4. **DNS port:** 
   - Default is `53`, but rootless Podman requires ports > 1024
   - Change to `5053` to match our docker-compose.yml port mapping
   - ⚠️ **Critical:** Must match the host port in docker-compose.yml

5. **Upstream DNS servers:**
   - **Recommended:** `9.9.9.9` (Quad9 - blocks malware) or `1.1.1.1` (Cloudflare)
   - Can leave as "Automatic" to use your system DNS
   - These are the DNS servers AdGuard queries for domains it doesn't block

6. **Blocking settings:**
   - ✅ Enable "Safe search" (optional)
   - ✅ Enable "Parental control" (optional)
   - ✅ Enable "Block malware, phishing, and other unwanted domains" (recommended)
   - Default blocklists are pre-enabled (AdGuard DNS filter, Peter Lowe's, etc.)

7. **Admin password:** Set a secure password for the web interface

8. **Finish:** Click "Apply settings" - DNS server will now start accepting queries

**After Setup - Finding Your Web UI:**
- If you kept port `3000`: `http://localhost:3000`
- If wizard changed to port `80`: `http://localhost:3080` (our compose maps 3080→80)
- Check logs to confirm: `podman compose logs | grep "go to http"`

**Verify DNS is working:**
```bash
# From host (requires dnsutils installed)
nslookup google.com 127.0.0.1#5053

# From another container on the same network
podman exec <container> nslookup google.com adguardhome

# Should return an IP address, not "connection refused"
```

---

## Configuration

### Ports Explained

| Port | Protocol | Purpose |
|------|----------|---------|
| 5053 | UDP/TCP | Standard DNS queries (host port → container 53) |
| 80 | TCP | HTTP (mapped from host 3080) |
| 443 | TCP | HTTPS (DNS-over-HTTPS) |
| 853 | TCP | DNS-over-TLS |
| 3000 | TCP | Web administration interface |

### Volume Mounts

| Host Path | Container Path | Purpose |
|-----------|----------------|---------|
| `./work` | `/opt/adguardhome/work` | Runtime data, logs, statistics |
| `./conf` | `/opt/adguardhome/conf` | Configuration files (persistent) |

---

## Network Configuration

### Option A: Set as Router DNS (Recommended)
1. Log into your router admin panel
2. Find DHCP/DNS settings
3. Set primary DNS to: `<YOUR_INTERNAL_IP>`
4. Save and reboot client devices

### Option B: Set Per-Device
**Linux:**
```bash
# Edit netplan or NetworkManager
# Set nameserver to <YOUR_INTERNAL_IP>
```

**macOS:**
- System Settings → Network → Advanced → DNS
- Add `<YOUR_INTERNAL_IP>`

**Windows:**
- Control Panel → Network → TCP/IPv4 properties
- Set preferred DNS to `<YOUR_INTERNAL_IP>`

**Android/iOS:**
- Use Private DNS feature (Android 9+)
- Set to: `<YOUR_INTERNAL_IP>` (if DoT supported) or use app

---

## Features to Explore

### Built-in Blocklists
AdGuard comes with several pre-configured blocklists:
- AdGuard DNS filter
- OISD Big
- Peter Lowe's Ad Server list
- Various malware/phishing lists

Enable/disable in: **Filtering → Filter management**

### Custom Rules
Add custom blocking rules in: **Filtering → Filter management → User rules**

Examples:
```
||example.com^       # Block entire domain
||example.com/bad   # Block specific path
@@||whitelist.com   # Whitelist (allow) domain
```

### Parental Control
- Block adult content automatically
- Set time-based schedules
- **Settings → Parental control**

### Query Logging
Enable/disable in: **Settings → Query log**  
Helps debug why certain sites are/aren't blocked

---

## Monitoring Integration

### Prometheus Metrics (Future)
AdGuard Home exposes Prometheus metrics at `/metrics` endpoint. Can be scraped by Prometheus from Experiment 3A.

Example scrape config for future `prometheus.yml`:
```yaml
scrape_configs:
  - job_name: 'adguard'
    static_configs:
      - targets: ['homelab-adguard:80']
    metrics_path: '/metrics'
```

---

## Testing

```bash
# Verify containers are running
podman ps | grep adguard

# Test DNS resolution via test client
podman exec homelab-adguard-test nslookup google.com adguardhome

# Test from host
nslookup google.com 127.0.0.1#5053

# Check AdGuard logs
podman logs homelab-adguard
```

---

## Maintenance

### Update Container
```bash
cd ~/homelab/infrastructure/adguard-home
podman compose pull
podman compose down
podman compose up -d
```

### Backup Configuration
```bash
# Config is in ./conf directory
tar czf adguard-backup-$(date +%Y%m%d).tar.gz conf work
```

### View Statistics
- Web UI: **Dashboard** shows queries blocked/allowed
- Real-time query log available in web interface

---

## Troubleshooting

### Container Won't Start
```bash
# Check logs
podman logs homelab-adguard

# Common issue: Port 53 requires privileged mode or cap_add NET_ADMIN
# Already configured in docker-compose.yml
```

### DNS Not Working on Devices
1. Verify container is running: `podman ps | grep adguard`
2. Test from host: `nslookup google.com 127.0.0.1#5053`
3. Check firewall: `sudo ufw status | grep 53`
4. May need to allow DNS in UFW: `sudo ufw allow 53/udp`

### Web UI Not Accessible
- Default port is 3000, not 80
- Try: `http://<YOUR_INTERNAL_IP>:3000`
- Check port mapping in docker-compose.yml

---

## Cleanup

```bash
cd ~/homelab/infrastructure/adguard-home
podman compose down -v
```

---

## Resource Usage

| Metric | Expected Value |
|--------|----------------|
| RAM (idle) | ~80-120 MB |
| RAM (active) | ~150-200 MB |
| CPU | <1% typically |
| Disk (config) | ~50-100 MB |

---

## Next Steps

After AdGuard is running and configured:
1. Set it as DNS for your devices or router
2. Monitor the dashboard for a day to see query stats
3. Customize blocklists based on your needs
4. Move to next Phase 1 experiment: **Prometheus + Grafana**

---

## References

- Official Docs: https://adguard.com/en/adguard-home/overview.html
- Docker Hub: https://hub.docker.com/r/adguard/adguardhome
- GitHub: https://github.com/AdguardTeam/AdGuardHome
- Blocklist database: https://github.com/AdguardTeam/AdGuardHome/wiki/Filters
