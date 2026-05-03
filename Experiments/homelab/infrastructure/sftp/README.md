# SFTP Server

## Overview

Stateless SFTP server using `atmoz/sftp` for secure file transfers. Users and directories are configured via environment variables at startup.

## Quick Start

```bash
cd ~/homelab/infrastructure/sftp
podman compose up -d --build
```

## Services

| Service | Port | Purpose |
|---------|------|---------|
| sftp | 2222/tcp | SFTP server |

## Testing

### Check container status

```bash
podman ps | grep homelab-sftp
```

### From test-client container

```bash
# Test DNS resolution between containers
podman exec homelab-sftp-test ping -c 1 sftp

# Run automated connectivity tests (upload, download, verify)
# Uses SFTP_USER and SFTP_PASSWORD from docker-compose.yml
podman exec homelab-sftp-test sh /test-connectivity.sh

# Verify data directory
podman exec homelab-sftp ls -la /home/labratorian/files
```

## Troubleshooting

- **Port 2222 in use**: Check with `ss -tlnp | grep 2222` and stop conflicting service or change port
- **Permission denied**: Ensure `./data` directory exists and is writable: `chmod 755 ./data`
- **Container won't start**: Verify full image reference is used (`docker.io/atmoz/sftp:alpine`)
- **Can't connect from other devices**: Check UFW rules and ensure device is on same network
- **Stale data after config changes**: Run `podman compose down -v` before `podman compose up -d`

## UFW Configuration

```bash
sudo ufw allow 2222/tcp
```

## Connection Details

| Platform | Connection String |
|----------|------------------|
| Linux/macOS Terminal | `sftp labratorian@<YOUR_INTERNAL_IP> -p 2222` |
| macOS Finder | `sftp://labratorian@<YOUR_INTERNAL_IP>:2222` (Cmd+K) |
| Android (Solid Explorer) | Host: <YOUR_INTERNAL_IP>, Port: 2222, User: labratorian |

**Default Credentials:**
- Username: `labratorian`
- Password: see `SFTP_PASSWORD` in `docker-compose.yml`

## Cleanup

```bash
podman compose down -v
```
