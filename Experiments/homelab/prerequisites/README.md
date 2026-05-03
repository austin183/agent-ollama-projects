# Homelab Prerequisites & Setup Guide

**Dell Inspiron 5502 Homelab**  
**Date:** April 15, 2026  
**Version:** 1.0

---

## Overview

This document covers the prerequisites and initial setup required to run container-based experiments on your Dell Inspiron 5502 running Pop!_OS 24.04. We'll use **Podman** as the container runtime instead of Docker for better security (rootless containers, no daemon) while maintaining compatibility with docker-compose.yml files.

---

## Why Podman Over Docker?

| Consideration | Decision | Rationale |
|---------------|----------|-----------|
| **Daemon requirement** | Podman wins | No background daemon = less attack surface, simpler management |
| **Root privileges** | Podman wins | Rootless containers by default = better security on a mobile laptop |
| **Docker Hub compatibility** | Tie | Both pull from same registries identically |
| **Compose support** | Slight Docker edge | Podman compose is compatible but newer/less mature |
| **Systemd integration** | Podman wins | Built-in container autostart generation |
| **Learning resources** | Docker wins | More tutorials exist, but podman commands are nearly identical |

**Bottom line:** For a personal homelab on a laptop you move around, Podman's security advantages outweigh the minor ecosystem differences. All `docker-compose.yml` files work with both runtimes.

---

## Installation Steps

### Step 1: Install Podman

```bash
# Update package lists
sudo apt update

# Install Podman (includes built-in compose support in recent versions)
sudo apt install podman

# Verify installation
podman --version
```

**Expected output:** `podman version 4.x.x` or higher

### Step 2: Install Podman Compose Plugin

Pop!_OS 24.04 should include the compose plugin with Podman, but verify:

```bash
# Check if compose is built-in
podman compose version

# If that fails, install podman-compose (Python-based alternative)
sudo apt install podman-compose
```

**Note:** The built-in `podman compose` is preferred over the Python `podman-compose` package. Both work similarly.

### Step 3: Configure Rootless Containers (Default Behavior)

Podman runs rootless by default, which is what we want. Verify:

```bash
# This should work without sudo
podman run hello-world

# Check your container storage location
echo $XDG_RUNTIME_DIR
# Typically: /run/user/1000
```

### Step 4: Enable Systemd Integration (Optional but Recommended)
**Skipping for now** - Skipping because I would rather start containers from the command line than have them start automatically.

Podman can generate systemd service files for containers that should start on boot:

```bash
# Enable podman auto-generation of systemd units
mkdir -p ~/.config/systemd/user/

# Create a simple systemd service template (for later use)
cat > ~/.config/systemd/user/podman-autoupdate.service << 'EOF'
[Unit]
Description=Podman Auto Update Service
After=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/podman system update

[Install]
WantedBy=default.target
EOF

# Reload systemd user daemon
systemctl --user daemon-reload
```

### Step 5: Configure Network Access for Rootless Containers
**Skipping for now** - We are going to work from this machine only for the time being.

Rootless containers need special network configuration to be accessible from other devices on your LAN:

```bash
# Check current network mode
podman network ls

# For rootless containers to bind to ports < 1024, we need to configure port forwarding
# Option A: Use nftables (recommended for Pop!_OS)
sudo apt install nftables

# Create nftables rule for rootless port forwarding
cat > ~/homelab/nftables-rules.nft << 'EOF'
table ip nat {
    chain postrouting {
        type nat hook postrouting priority srcnat; policy accept;
        # Forward ports from host to rootless containers
        # Add rules here as needed for each service
    }
}
EOF

# Option B: Just use ports > 1024 (simpler, recommended for homelab)
# Our compose files already use non-standard ports (3000, 8080, etc.)
```

**For this homelab:** We'll stick to **ports > 1024** in all docker-compose.yml files to avoid complexity. No special nftables configuration needed.

---

## Verification Tests

### Test 1: Basic Container Run

```bash
# Pull and run a test container
podman run --rm hello-world

# Expected output: "Hello from Docker!" (yes, it still says Docker)
```

### Test 2: Compose File Execution with Network Connectivity

Create a test compose file with two containers on the same network:

```bash
mkdir -p ~/homelab/test-compose
cd ~/homelab/test-compose

cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  container-a:
    image: alpine:latest
    command: sleep 3600
    networks:
      - test-network

  container-b:
    image: alpine:latest
    command: sleep 3600
    networks:
      - test-network

networks:
  test-network:
    driver: bridge
EOF

# Start the compose stack
podman compose up -d

# Check both containers are running
podman ps

# View logs
podman compose logs

# Test network connectivity between containers
# Container A should be able to ping Container B by service name
podman compose exec container-a ping -c 3 container-b

# Container B should be able to ping Container A
podman compose exec container-b ping -c 3 container-a

# Optional: SSH test (install openssh-server in custom image or use busybox)
# podman compose exec container-a sh -c "apk add --no-cache openssh-client && ssh -o StrictHostKeyChecking=no root@container-b echo 'SSH works'"

# Stop and clean up
podman compose down

# Remove test directory
cd ~ && rm -rf ~/homelab/test-compose
```

**Expected output for ping tests:**
```
PING container-b (172.18.0.3): 56 data bytes
32 bytes from 172.18.0.3: seq=0 ttl=64 time=0.123 ms
32 bytes from 172.18.0.3: seq=1 ttl=64 time=0.098 ms
32 bytes from 172.18.0.3: seq=2 ttl=64 time=0.087 ms

--- container-b ping statistics ---
3 packets transmitted, 3 packets received, 0% packet loss
```

**Why the network definition matters:**
- Without the `networks` section, containers wouldn't be able to resolve each other by service name
- The bridge network creates an isolated subnet for container-to-container communication
- Service names (container-a, container-b) act as DNS entries within the network

### Test 3: Port Binding Test

```bash
# Start a simple HTTP server container
podman run -d --name test-web \
  -p 8080:80 \
  nginx:alpine

# Test locally
curl http://localhost:8080

# Should return nginx welcome page HTML

# Clean up
podman stop test-web && podman rm test-web
```

### Test 4: DNS Resolution Tools (Optional but Recommended)

```bash
# Install DNS testing utilities for later experiments
sudo apt install -y dnsutils

# Test DNS resolution (will use system DNS)
nslookup google.com

# Expected output: IP address for google.com

# Alternative: dig command
dig google.com +short
```

**Why install these?** Many experiments (AdGuard Home, Pi-hole, custom DNS) require DNS testing tools to verify functionality.

---

## Command Reference: Docker → Podman

Most commands are identical. Here are the key mappings:

| Task | Docker Command | Podman Command | Notes |
|------|----------------|----------------|-------|
| List running containers | `docker ps` | `podman ps` | Identical |
| Show all containers | `docker ps -a` | `podman ps -a` | Identical |
| Start compose stack | `docker compose up -d` | `podman compose up -d` | Identical |
| Stop compose stack | `docker compose down` | `podman compose down` | Identical |
| View logs | `docker logs -f <container>` | `podman logs -f <container>` | Identical |
| Execute in container | `docker exec -it <c> bash` | `podman exec -it <c> bash` | Identical |
| Remove container | `docker rm <container>` | `podman rm <container>` | Identical |
| Remove image | `docker rmi <image>` | `podman rmi <image>` | Identical |
| Prune unused data | `docker system prune` | `podman system prune` | Identical |
| View resource usage | `docker stats` | `podman stats` | Identical |
| Search images | `docker search <term>` | `podman search <term>` | Identical |

### Key Differences to Remember

1. **No daemon:** Commands work directly, no need for `sudo` (when running rootless)
2. **Systemd services:** Use `podman generate systemd` instead of Docker's restart policies for autostart
3. **Volume locations:** Rootless volumes are in `~/.local/share/containers/storage/volumes/` not `/var/lib/docker/`
4. **Network namespacing:** Slightly different, but transparent with compose files

---

## Directory Structure Setup

Create the homelab directory structure:

```bash
# Create main homelab directory
mkdir -p ~/homelab

# Create domain subdirectories (from experiments.md)
mkdir -p ~/homelab/{messaging,databases,observability,ai-inference,security,infrastructure,files,devops,reactive-processing}

# Set appropriate permissions
chmod 755 ~/homelab
chmod 755 ~/homelab/*

# Verify structure
tree -L 2 ~/homelab
```

**Expected output:**
```
~/homelab/
├── ai-inference/
├── databases/
├── devops/
├── files/
├── infrastructure/
│   └── adguard-home/
├── messaging/
├── observability/
├── reactive-processing/
└── security/
```

---

## UFW Firewall Configuration

Pop!_OS comes with UFW (Uncomplicated Firewall) pre-installed. Configure it to allow container ports:

```bash
# Check current status
sudo ufw status verbose

# If inactive, set default policies (safe defaults)
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Allow SSH (CRITICAL - don't lock yourself out if accessing remotely)
sudo ufw allow OpenSSH

# Allow specific ports as we add services
# For AdGuard Home (Phase 1):
sudo ufw allow 53/udp comment 'AdGuard DNS'
sudo ufw allow 53/tcp comment 'AdGuard DNS TCP'
sudo ufw allow 3000/tcp comment 'AdGuard Web UI'

# Enable firewall
sudo ufw enable

# Verify rules
sudo ufw status numbered
```

**Important:** Always test firewall rules from a different terminal window before closing your current session!

---

## Resource Limits (Optional but Recommended)

To prevent containers from consuming all system resources, configure limits:

### Option A: Per-Container Limits in Compose Files

Each `docker-compose.yml` will include resource limits like:

```yaml
services:
  example:
    deploy:
      resources:
        limits:
          cpus: '1.0'
          memory: 512M
        reservations:
          cpus: '0.25'
          memory: 128M
```

### Option B: Global Podman Limits

Create a global configuration file:

```bash
mkdir -p ~/.config/containers

cat > ~/.config/containers/containers.conf << 'EOF'
[engine]
# Default resource limits for all containers
default-shm-size = "64M"
env = ["TZ=America/New_York"]

[containers]
# Default CPU and memory limits
cpu-period = 100000
cpu-quota = 80000  # 80% of one core max per container by default
EOF
```

---

## NVIDIA Container Toolkit (GPU Passthrough)

If your machine has an NVIDIA GPU, install the NVIDIA Container Toolkit to expose it to rootless Podman containers.

### Installation

Follow the [official NVIDIA Container Toolkit install guide](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html):

```bash
# Add NVIDIA package repositories
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg \
  && curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
    sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
    sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

# Update and install
sudo apt-get update
sudo apt-get install -y nvidia-container-toolkit

# Configure CDI (Container Device Interface) for rootless Podman
sudo nvidia-ctk cdi generate --output /var/run/cdi/nvidia.yaml
```

### Verification

```bash
# List available CDI GPU devices
nvidia-ctk cdi list

# Expected output:
# nvidia.com/gpu=0
# nvidia.com/gpu=GPU-<uuid>
# nvidia.com/gpu=all

# Test GPU access in a container
podman run --rm --device nvidia.com/gpu=all ubuntu nvidia-smi
```

### Using in Compose Files

```yaml
services:
  my-gpu-service:
    image: some-cuda-image
    devices:
      - nvidia.com/gpu=all
```

**Note:** The CDI device syntax (`nvidia.com/gpu=all`) is used instead of the older `--gpus all` flag. This works with rootless Podman without requiring additional daemon configuration.

### Troubleshooting

**"nvidia-ctk: command not found"** — The toolkit isn't installed. Run the installation steps above.

**"no CDI devices found"** — Run `sudo nvidia-ctk cdi generate --output /var/run/cdi/nvidia.yaml` to regenerate the CDI config.

**"permission denied" accessing GPU** — Ensure your user is in the `video` group: `sudo usermod -aG video $USER` (log out and back in after).

---

## Troubleshooting Common Issues

### Issue: "permission denied" when running podman

**Cause:** SELinux or AppArmor restrictions (unlikely on Pop!_OS)

**Solution:**
```bash
# Check if SELinux is enforcing
getenforce

# If Enforcing, set to Permissive temporarily for testing
sudo setenforce 0

# Better: Configure proper SELinux contexts (if needed)
# This shouldn't be necessary on Pop!_OS by default
```

### Issue: Container can't bind to port < 1024

**Cause:** Rootless containers can't bind privileged ports

**Solution:** Use ports > 1024 in compose files (already done in our templates) or configure subuid/subgid:

```bash
# Check current subuid configuration
cat /etc/subuid | grep $USER

# Add more UIDs if needed (for advanced use cases)
# Not required for this homelab setup
```

### Issue: "network not found" with compose

**Cause:** Podman network backend issue

**Solution:**
```bash
# Recreate the network
podman compose down
podman network rm <network-name>
podman compose up -d
```

### Issue: Slow image pulls

**Cause:** Default Docker Hub rate limiting or slow connection

**Solution:** Configure a mirror in `~/.config/containers/registries.conf`:

```bash
mkdir -p ~/.config/containers

cat > ~/.config/containers/registries.conf << 'EOF'
unqualified-search-registries = ["docker.io"]

[[registry]]
prefix = "docker.io"
location = "docker.io"
tlsverify = true

# Add mirrors if you have access to them
# [[registry.mirror]]
# location = "mirror.gcr.io"
EOF
```

---

## Next Steps After Installation

1. **Run the verification tests** above to confirm everything works
2. **Test AdGuard Home:** `cd ~/homelab/infrastructure/adguard-home && podman compose up -d`
3. **Access web UI:** Open `http://localhost:3000` in your browser
4. **Configure DNS testing:** Point one device's DNS to <YOUR_INTERNAL_IP> and verify ad blocking works
5. **Proceed to Phase 1, Experiment 2:** Prometheus + Grafana monitoring stack

---

## Useful Commands Cheat Sheet

```bash
# Daily operations
podman ps                    # List running containers
podman ps -a                 # List all containers (including stopped)
podman stats                 # Real-time resource usage
podman logs -f <container>   # Follow container logs
podman stop <container>      # Graceful stop
podman start <container>     # Start stopped container
podman rm <container>        # Remove stopped container

# Compose operations
podman compose up -d         # Start stack in background
podman compose down          # Stop and remove stack
podman compose restart       # Restart all services
podman compose logs -f       # View all service logs
podman compose exec <svc> bash  # Execute command in service

# Image management
podman images                # List local images
podman pull <image>          # Pull new image
podman rmi <image>           # Remove image
podman system prune          # Clean unused images/containers/volumes

# Storage cleanup
podman system df             # Show disk usage by type
podman system prune -a       # Aggressive cleanup (removes all unused)

# Advanced
podman inspect <container>   # Detailed container info
podman top <container>       # See running processes in container
podman stats --no-stream     # One-time stats snapshot
```

---

## References

- **Podman Documentation:** https://docs.podman.io/
- **Podman Compose:** https://github.com/containers/podman-compose
- **Rootless Containers:** https://github.com/containers/libpod/blob/main/rootless.md
- **Pop!_OS Container Guide:** https://support.system76.com/articles/docker/ (Docker-focused but applicable)
- **experiments.md:** See `~/workspace/ideas/experiments.md` for full project plan

---

*Last Updated: April 15, 2026*  
*Next Document to Review: experiments.md (Phase 1 execution plan)*
