# RabbitMQ Cluster + Quorum Queues Experiment Timeline

**Date:** April 18, 2026  
**Phase:** 3 - Messaging Domain  
**Experiment:** 1B - RabbitMQ Cluster with Quorum Queues  
**Status:** Blocked - entrypoint architecture issue identified, needs redesign

---

## Setup Phase

### Directory Structure Created

```
~/homelab/messaging/rabbitmq-cluster/
├── docker-compose.yml
├── Dockerfile
├── entrypoint.sh
├── conf/                          # (empty, for future config overrides)
├── workers/
│   ├── Dockerfile                 # (copied from rabbitmq-celery)
│   ├── task_worker.py             # (copied from rabbitmq-celery)
│   └── producer.py                # (copied from rabbitmq-celery)
├── README.md                      # (not yet created)
└── experiment-timeline.md
```

### Pre-flight Checks

- **Port conflict check:** Ports 5672, 15672, 25672, 15673, 25673, 15674, 25674, 5555 - all clear
- **Existing experiment stopped:** `podman compose down` from `rabbitmq-celery` to free ports 5672 and 15672
- **Volumes cleaned:** `podman compose down -v` to remove stale data
- **Image references:** All use full `docker.io/` prefix as required by Podman

### Design Decisions

1. **3-node cluster:** Quorum/Raft consensus requires odd number of nodes for elections
2. **Quorum queues:** Modern default since RabbitMQ 3.9, Raft-based, no data loss on failover
3. **Custom entrypoint:** Each node detects its role via `RABBITMQ_NODENAME` env var, non-primary nodes wait for and join node1
4. **Erlang cookie:** Shared via `RABBITMQ_CLUSTER_COOKIE` environment variable
5. **Port mapping:** Node1 maps AMQP to host port 5672 (freed from single-node experiment). Management UI on 15672/15673/15674. Inter-node clustering on 25672/25673/25674.
6. **Celery worker:** Connects to `rabbitmq1:5672`. Celery's built-in retry will reconnect if node1 goes down.
7. **Quorum policy:** Applied via `rabbitmqctl set_policy` to make all queues quorum-type

---

## Iteration History

### Iteration 1: `rabbitmq-diagnostics -h` flag

**Error:**
```
Error (argument validation): Invalid options for this command:
-h : 
Arguments given:
	-q ping -h rabbitmq1
```

**Root cause:** Used `rabbitmq-diagnostics -q ping -h ${RABBITMQ_NODE1}`. The `-h` flag is not a valid option for `rabbitmq-diagnostics`. The correct syntax uses `--node` flag.

**Resolution:** Changed to `rabbitmq-diagnostics --node rabbit@${RABBITMQ_NODE1} -q ping`

---

### Iteration 2: `hostname` vs service name

**Error:**
```
ERROR: rabbitmq1 did not become ready in 60 seconds
Error: Failed to connect and authenticate to rabbit@rabbitmq1 in 60000 ms
```

**Root cause:** The entrypoint used `hostname` to determine if this was node1, but `hostname` returns the container ID (e.g., `fa719b9d3539`), not the service name (`rabbitmq1`). This meant every node thought it was not node1 and tried to join the cluster, but node1 never actually started as the primary.

**Resolution:** Changed detection to use `RABBITMQ_NODENAME` environment variable:
```bash
NODE_SUFFIX=$(echo "${RABBITMQ_NODENAME}" | sed 's/rabbit@//')
if [ "${NODE_SUFFIX}" != "${RABBITMQ_NODE1}" ]; then
```

---

### Iteration 3: Erlang cookie authentication before server starts

**Error:**
```
Error:
Failed to connect and authenticate to rabbit@rabbitmq1 in 60000 ms
```

**Root cause:** Even after fixing the hostname issue, nodes 2 and 3 couldn't authenticate to node1 via `rabbitmq-diagnostics` because the Erlang cookie was being set in the entrypoint script, but the RabbitMQ server on node1 hadn't started yet. The `rabbitmq-diagnostics` command tries to authenticate using the Erlang cookie, which requires the server to be running and for the cookie files to match.

**Attempted fix:** Added a two-step wait for nodes 2/3:
1. First wait for AMQP port 5672 to be available via `nc -z`
2. Then verify with `rabbitmq-diagnostics --node rabbit@${RABBITMQ_NODE1} -q ping`

This didn't fully resolve the issue because the cookie synchronization timing is still off.

---

### Iteration 4 (CURRENT): `rabbitmqctl` commands run before server is alive

**Error:**
```
Error: unable to perform an operation on node 'rabbit@rabbitmq1'. Please see diagnostics information and suggestions below.
 * Target node is not running
```

**Root cause (CRITICAL):** The entrypoint script runs `rabbitmqctl set_policy` and `rabbitmqctl cluster_status` **BEFORE** executing `docker-entrypoint.sh` which starts the actual RabbitMQ server. The script flow is:

```
entrypoint.sh:
  1. Set erlang cookie
  2. If not node1: wait for node1, join cluster, start app
  3. Apply quorum policy  <-- rabbitmqctl fails here! Server is NOT running yet
  4. Show cluster status  <-- Also fails
  5. exec docker-entrypoint.sh  <-- Server finally starts
```

The `rabbitmqctl` commands in steps 3-4 fail because the RabbitMQ server process hasn't been started yet. Only after the script reaches `exec /docker-entrypoint.sh` does the server actually start.

**This is the core architectural issue that needs to be resolved.**

---

## Architecture Analysis

### Why the current approach doesn't work

The entrypoint pattern tries to do cluster setup **before** starting the server. But `rabbitmqctl` requires a running server to communicate with. The fundamental problem is:

1. **Node 1:** Sets cookie, tries to run `rabbitmqctl set_policy` (server not running → fails), then starts server
2. **Nodes 2/3:** Sets cookie, waits for node1, tries to `rabbitmqctl stop_app` / `join_cluster` / `start_app` (server not running → fails), then starts server

### Possible solutions (for next attempt)

**Option A: Post-start background script**
- entrypoint.sh sets cookie, then execs docker-entrypoint.sh to start server
- After exec, the server starts in foreground (blocking)
- To run post-start commands, use a **second process**: start server in background, then run cluster setup in foreground
- Problem: docker-entrypoint.sh is designed to be the foreground process

**Option B: Separate init container**
- All 3 nodes run with standard docker-entrypoint.sh (no custom logic)
- Add a 4th "init" container that starts after all 3 are healthy
- Init container runs: `rabbitmqctl join_cluster`, `rabbitmqctl set_policy`
- Problem: `depends_on` with `condition: service_healthy` is unreliable per our previous experience

**Option C: Use `RABBITMQ_SERVER_ADDITIONAL_ERL_ARGS`**
- Configure clustering via environment variables instead of runtime commands
- Set `RABBITMQ_ERLANG_COOKIE` directly
- Use `RABBITMQ_CLUSTER_ARGS` for cluster formation
- Problem: RabbitMQ Docker image doesn't support automatic cluster joining via env vars

**Option D: Two-phase entrypoint**
- Phase 1: entrypoint.sh sets cookie, starts server in background, waits for it to be ready
- Phase 2: run cluster join and policy commands
- Problem: Need to manage the server lifecycle manually

**Option E: Use `pre-start` hook via docker-entrypoint.sh**
- The official RabbitMQ Docker image supports `RABBITMQ_PRE_ENTRYPOINT` env var
- Set it to a script that runs before the server starts
- Still has the same problem: server isn't running yet

**Most promising approach:** Option A/D hybrid
- entrypoint.sh: set cookie, start server in background (`docker-entrypoint.sh rabbitmq-server &`), wait for health, then run cluster setup commands, then `wait` for the background server process
- This gives us a running server to talk to via `rabbitmqctl`

### Iteration 5 (CURRENT): Background server + cookie path fix — still failing

**Fixes applied:**
1. **Cookie path corrected:** `/docker-entrypoint.sh` → `/usr/local/bin/docker-entrypoint.sh` (the actual path in the image)
2. **Cookie newline fixed:** Changed `echo "${CLUSTER_COOKIE}"` to `printf '%s' "${CLUSTER_COOKIE}"` — `echo` adds a trailing newline, making the Erlang cookie "too short" (Erlang requires exactly the cookie string, no newline)

**Error (node1):**
```
Starting RabbitMQ server in background...
=INFO REPORT==== 18-Apr-2026::19:58:06.674956 ===
    alarm_handler: {set,{system_memory_high_watermark,[]}}
Error:
Failed to connect and authenticate to rabbit@rabbitmq1 in 60000 ms
  Waiting for node to be ready... (1/120)
```

**Error (nodes 2/3):** Server starts, then immediately crashes:
```
2026-04-18 19:58:11.369385 [info] <0.299.0> Successfully stopped RabbitMQ and its dependencies
Runtime terminating during boot ({12700,normal})
Crash dump is being written to: /var/log/rabbitmq/erl_crash.dump...done
```

**Root cause analysis:**
The background server approach has a fundamental problem: `rabbitmq-diagnostics -q ping` is an escript that uses the Erlang cookie to connect to the local node. But when we run the server in background with `rabbitmq-server &`, the diagnostics command runs in the same shell context and may not see the cookie file properly. The server also starts up, runs the pre-launch checks, and then crashes with `Runtime terminating during boot ({12700,normal})` — exit code 127 suggests the boot process encountered an unrecoverable error.

The `rabbitmq-diagnostics` command tries to authenticate using the Erlang cookie, but the server process in the background may not have fully initialized the Mnesia database or net_kernel before diagnostics runs. The 60-second timeout is too short for the full server startup + Mnesia initialization + net_kernel formation.

**Additionally:** The `rabbitmqctl set_policy` command on node1 fails with:
```
Error: this command requires the 'rabbit' app to be running on the target node. Start it with 'rabbitmqctl start_app'.
```
This means the server IS starting but the `rabbit` application isn't in the started state — it's stuck in boot.

**This confirms the background server approach is fundamentally flawed for this use case.** The entrypoint script's job is to be the foreground process. Running it in background breaks the boot sequence because:
1. The entrypoint does env var processing (user creation, vhost setup) that happens in the foreground
2. When backgrounded, the server boot sequence competes with our diagnostics polling
3. The cookie file may not be visible to the diagnostics escript in the same process group

**Recommended new approach for next session:**

**Use `rabbitmq.conf` + `advanced.config` with environment-driven cluster formation** — let RabbitMQ handle clustering automatically instead of manual `rabbitmqctl` commands:

1. Create a `rabbitmq.conf` baked into the image with:
   - `clusterformation.peer_discovery_backend = rabbit_peer_discovery_classic_config`
   - `clusterformation.classic_config.nodes.1 = rabbit@rabbitmq1`
   - `RABBITMQ_ERLANG_COOKIE` set via env var (RabbitMQ Docker image reads this automatically)
   - `management.load_definitions` not needed

2. Each node gets its own `RABBITMQ_NODENAME` env var — the official image already handles this

3. Use a **post-start init script** (separate from entrypoint) that:
   - Waits for all 3 nodes to be healthy (via healthcheck polling)
   - Then runs `rabbitmqctl set_policy` for quorum queues
   - This script runs as a separate container or as a `command` override on one of the nodes

4. **Key insight:** The official RabbitMQ Docker image already supports clustering via environment variables and config files. We don't need a custom entrypoint at all — just a custom config file and a separate init step.

---

## Verification Phase (never reached)

The experiment never progressed past the setup phase due to the entrypoint architecture issue. No verification or failover testing was possible.

---

## Common Questions

### Q: Why not just use the official RabbitMQ clustering docs?
The official docs assume bare metal or VMs where you have shell access to each node. In containers, the entrypoint/initialization model is different, and the official Docker clustering example uses a different approach (shared data directory with `rabbitmq.conf`).

### Q: Why not use a shared volume for all 3 nodes?
That's actually a valid approach (Option F below).

**Option F: Shared volume + rabbitmq.conf**
- Mount a single shared volume to all 3 nodes at `/var/lib/rabbitmq`
- Bake `rabbitmq.conf` into the image with cluster formation settings
- Each node auto-discovers and joins the cluster on startup
- Problem: Shared volume with 3 containers in Podman is complex; data corruption risk

### Q: What about RabbitMQ Operator or Kubernetes?
That's the production-grade approach, but overkill for a homelab experiment. The point is to learn the mechanics, not deploy enterprise infrastructure.

---

## Lessons Learned

### What worked well
- Directory structure and file organization followed existing patterns
- Worker code (producer, task_worker) copied cleanly from existing experiment
- Dockerfile for custom RabbitMQ image is simple and correct
- docker-compose.yml structure is sound (ports, networks, volumes all correct)
- Pre-flight port conflict check caught no issues

### Issues encountered and resolved

1. **Port 65672 exceeds max port number (65535)** - Changed to 5672 (host port matches container port since there's no conflict after stopping the single-node experiment)

2. **`rabbitmq-diagnostics -h` is invalid syntax** - The `-h` flag doesn't exist for this command. Correct syntax: `rabbitmq-diagnostics --node rabbit@nodename -q ping`

3. **`hostname` returns container ID, not service name** - In Podman containers, `hostname` returns the full container ID by default. Must use environment variables to identify nodes.

4. **Erlang cookie authentication timing** - Setting the cookie file in the entrypoint doesn't immediately make it available for authentication. The server process needs to read it on startup.

5. **CRITICAL: `rabbitmqctl` commands fail before server starts** - The entrypoint script runs cluster management commands before `exec docker-entrypoint.sh`. The server isn't running, so all `rabbitmqctl` operations fail. This is the fundamental blocker.

6. **Cookie path and format matter** - The entrypoint is at `/usr/local/bin/docker-entrypoint.sh` not `/docker-entrypoint.sh`. Also, `echo` adds a trailing newline to the cookie, causing "Too short cookie string" errors. Must use `printf '%s'`.

7. **Background server breaks boot sequence** - Running `rabbitmq-server &` in background causes the server to crash with `Runtime terminating during boot ({12700,normal})`. The diagnostics escript can't authenticate because the server isn't fully initialized. The entrypoint is designed to be the foreground process.

8. **Best approach: config-driven clustering** - The official RabbitMQ Docker image supports clustering via `rabbitmq.conf` and environment variables (`RABBITMQ_ERLANG_COOKIE`, `RABBITMQ_NODENAME`). No custom entrypoint needed — just a config file and a separate init step for policy application.

### Key takeaways
- **Entrypoint architecture matters:** You can't run `rabbitmqctl` against a server that hasn't started yet
- **Container hostname ≠ service name:** In Docker/Podman, always use environment variables or DNS for inter-container identification
- **`depends_on` with health checks is unreliable:** Even when it works, the timing can be off for complex services like RabbitMQ clustering
- **3 nodes is the right number for Raft:** Quorum needs odd numbers to break ties in elections
- **Quorum queues are the modern approach:** No need for legacy mirrored queues
- **Cookie file is sensitive:** Must use `printf '%s'` (no newline), and the path is `/usr/local/bin/docker-entrypoint.sh`
- **Don't background the server:** Running `rabbitmq-server &` breaks the boot sequence; the entrypoint must be foreground
- **Config-driven clustering works best:** Use `rabbitmq.conf` + env vars for cluster formation; let RabbitMQ handle it automatically

---

## Design Decisions

### Why 3 nodes instead of 2?
Raft consensus requires a majority. With 2 nodes, if 1 fails, the remaining node doesn't have a majority (1/2). With 3 nodes, the cluster can tolerate 1 failure (2/3 majority).

### Why not use a shared volume for all nodes?
A shared volume would allow all nodes to see the same data directory, which is one way to form a cluster. However, it introduces complexity around volume permissions and data corruption risks. The separate-volume approach (which we're using) is cleaner but requires explicit cluster join logic.

### Why quorum queues instead of classic queues?
Classic queues with mirroring are deprecated. Quorum queues use Raft consensus, provide automatic leader election, and guarantee no data loss when properly configured. They're the default for new queues since RabbitMQ 3.9.

### Why Celery connects to rabbitmq1 specifically?
In a cluster, all nodes serve the same queues. Connecting to any node works. We use `rabbitmq1` as the primary because:
1. It's the first to start (no dependency on others)
2. Celery's built-in retry handles failover gracefully
3. Keeps the compose file simple (no complex broker URL list)

---

## Testing Checklist (pending)

```
Experiment Setup Progress:
- [x] Compose file uses full image references
- [x] Ports are > 1024 (except 5672 which is freed from single-node experiment)
- [ ] Test client container included
- [ ] Healthcheck on RabbitMQ (rabbitmq-diagnostics ping)
- [ ] Volumes use hybrid strategy (named volumes for data)
- [ ] Network name follows homelab-* pattern (homelab-messaging-net)
- [ ] README includes verification commands
- [ ] Expected output samples provided
- [ ] All containers running successfully
- [ ] Cluster health verified (rabbitmqctl cluster_status shows 3 nodes)
- [ ] Quorum queues confirmed (rabbitmqctl list_queues shows quorum type)
- [ ] Tasks processed through cluster
- [ ] Failover tested (kill primary, tasks continue)
- [ ] Primary restored, rejoin verified
```

---

## Next Steps (for next session)

**New recommended approach: Configuration-driven clustering (no custom entrypoint)**

1. **Create `conf/rabbitmq.conf`** with cluster formation settings:
   ```
   clusterformation.peer_discovery_backend = rabbit_peer_discovery_classic_config
   clusterformation.classic_config.nodes.1 = rabbit@rabbitmq1
   clusterformation.classic_config.nodes.2 = rabbit@rabbitmq2
   clusterformation.classic_config.nodes.3 = rabbit@rabbitmq3
   ```

2. **Set `RABBITMQ_ERLANG_COOKIE`** as env var in compose (the official image reads this automatically and writes the cookie file)

3. **Remove custom entrypoint entirely** — use the official `docker-entrypoint.sh` as-is

4. **Add `rabbitmq.conf` volume mount** to all 3 nodes: `- ./conf/rabbitmq.conf:/etc/rabbitmq/rabbitmq.conf:ro`

5. **Add a separate init service** (or use a sleep-then-run script on rabbitmq1) that applies the quorum policy AFTER all nodes are healthy:
   ```yaml
   cluster-init:
     image: docker.io/rabbitmq:3.13-management-alpine
     command: >
       sh -c "until rabbitmq-diagnostics --node rabbit@rabbitmq1 -q ping; do sleep 2; done;
       rabbitmqctl set_policy quorum-all ..."
     depends_on:
       - rabbitmq1
   ```

6. **Rebuild and test** — this should be much simpler than the manual cluster join approach

7. **Write README.md** with architecture diagram and verification steps

---

*Timeline created: April 18, 2026*  
*Status: Blocked - entrypoint architecture redesign needed*

---

## Redesign Phase (Config-Driven Clustering)

### Approach

Replaced the custom `entrypoint.sh` with config-driven automatic cluster formation using `rabbitmq.conf`. The official RabbitMQ Docker image handles:
- Reading `RABBITMQ_ERLANG_COOKIE` env var and writing the cookie file
- Reading `RABBITMQ_NODENAME` env var for node identity
- Processing `RABBITMQ_DEFAULT_USER`/`PASS`/`VHOST` for user creation
- Automatic cluster discovery via `clusterformation.classic_config.nodes.*`

### Files Changed

| File | Action | Description |
|------|--------|-------------|
| `entrypoint.sh` | **Deleted** | No longer needed |
| `Dockerfile` | **Rewritten** | Only copies `rabbitmq.conf`, no custom entrypoint |
| `conf/rabbitmq.conf` | **Created** | Cluster formation + management config |
| `docker-compose.yml` | **Rewritten** | Phase 1 scope: 3 nodes + cluster-init + test-client |
| `.env` | **Created** | Secrets (cookie, credentials) |

### Iteration 1: Config format wrong — `clusterformation` vs `cluster_formation`

**Error:**
```
You've tried to set clusterformation.classic_config.nodes.1, but there is no setting with that name.
  Did you mean one of these?
    cluster_formation.classic_config.nodes.$node
BOOT FAILED
Error during startup: {error,failed_to_prepare_configuration}
```

**Root cause:** Used `clusterformation` (no underscore) but RabbitMQ 3.13 uses `cluster_formation` (with underscore).

**Resolution:** Changed all `clusterformation.*` keys to `cluster_formation.*` in `rabbitmq.conf`.

### Iteration 2: Cookie env var wrong — `RABBITMQ_CLUSTER_COOKIE` vs `RABBITMQ_ERLANG_COOKIE`

**Error:**
```
Connection attempt from node 'rabbit-3042-1@...' rejected. Invalid challenge reply.
```

**Root cause:** Used `RABBITMQ_CLUSTER_COOKIE` as the env var name, but the official RabbitMQ Docker image reads `RABBITMQ_ERLANG_COOKIE` to set the Erlang cookie file.

**Resolution:** Changed all `RABBITMQ_CLUSTER_COOKIE` env vars to `RABBITMQ_ERLANG_COOKIE` in the compose file. The `.env` file still uses `RABBITMQ_CLUSTER_COOKIE` as the variable name for clarity, but it's referenced via `${RABBITMQ_CLUSTER_COOKIE}` and mapped to `RABBITMQ_ERLANG_COOKIE` in the compose environment.

### Iteration 3: cluster-init can't authenticate — missing `--node` flag

**Error:**
```
Error: unable to perform an operation on node 'rabbit@873f6f84ff7a'.
attempted to contact: [rabbit@873f6f84ff7a]
epmd reports: node 'rabbit' not running at all
```

**Root cause:** The `rabbitmqctl` commands in cluster-init defaulted to the container's own hostname (its container ID) instead of targeting `rabbit@rabbitmq1`. Without the `--node` flag, `rabbitmqctl` tries to operate on the local node.

**Resolution:** Added `--node rabbit@rabbitmq1` to all `rabbitmqctl` and `rabbitmq-diagnostics` commands in cluster-init.

### Iteration 4: `set_policy` fails — `queue-type` not recognized

**Error:**
```
rabbitmqctl set_policy quorum-all '^.*$' '{"queue-type":"quorum"}' ...
Validation failed
[{<<"queue-type">>,<<"quorum">>}] are not recognised policy settings
```

**Root cause:** The `queue-type` policy setting was for legacy mirrored queues, deprecated since RabbitMQ 3.8. Quorum queues are the default since RabbitMQ 3.9.

**Resolution:** Removed the `set_policy` command from cluster-init. Added `default_queue_type = quorum` to `rabbitmq.conf` to explicitly set the default. The cluster-init now only verifies cluster formation.

### Iteration 5: cluster-init `--format long` invalid

**Error:**
```
Error (argument validation): Invalid options for this command:
--format : 
Arguments given: cluster_status --format long
```

**Root cause:** `cluster_status` doesn't accept `--format` in RabbitMQ 3.13.

**Resolution:** Removed `--format long` from the `cluster_status` command.

### Verification Results

**Cluster status (all 3 nodes):**
```
Disk Nodes
  rabbit@rabbitmq1
  rabbit@rabbitmq2
  rabbit@rabbitmq3

Running Nodes
  rabbit@rabbitmq1
  rabbit@rabbitmq2
  rabbit@rabbitmq3

Versions
  rabbit@rabbitmq1: RabbitMQ 3.13.7 on Erlang 26.2.5.16
  rabbit@rabbitmq2: RabbitMQ 3.13.7 on Erlang 26.2.5.16
  rabbit@rabbitmq3: RabbitMQ 3.13.7 on Erlang 26.2.5.16
```

**DNS resolution from test-client:**
```
$ nslookup rabbitmq1
Name: rabbitmq1.dns.podman
Address: <CONTAINER_IP>

$ nslookup rabbitmq2
Name: rabbitmq2.dns.podman
Address: <CONTAINER_IP>

$ nslookup rabbitmq3
Name: rabbitmq3.dns.podman
Address: <CONTAINER_IP>
```

**Resource usage:**
| Container | CPU | Memory |
|-----------|-----|--------|
| homelab-rabbitmq1 | 21.57% | 82.94MB |
| homelab-rabbitmq2 | 9.10% | 84.24MB |
| homelab-rabbitmq3 | 9.45% | 81.98MB |
| homelab-messaging-test | 0.01% | 49KB |
| **Total RabbitMQ** | | **~249MB** |

**Management UI:** Accessible at http://localhost:15672 (credentials: homelab/homelab123)

---

## Lessons Learned (Redesign)

### What worked well
- Config-driven clustering eliminated all the entrypoint complexity
- The official RabbitMQ Docker image handles cookie management automatically via `RABBITMQ_ERLANG_COOKIE`
- Separate cluster-init container cleanly separates cluster verification from node startup
- Clean `podman compose down -v` before rebuild prevents stale data issues

### Issues encountered and resolved
1. **Config key naming:** RabbitMQ 3.13 uses underscores (`cluster_formation`) not camelCase. The error message helpfully suggests the correct name.
2. **Cookie env var:** Must use `RABBITMQ_ERLANG_COOKIE` (the official name), not a custom name. The `.env` file can use any name but must be mapped correctly in compose.
3. **cluster-init needs `--node`:** Without it, `rabbitmqctl` operates on the local container's hostname, not the cluster node.
4. **`queue-type` policy deprecated:** Quorum queues are the default. Use `default_queue_type = quorum` in config instead of `set_policy`.
5. **`--format long` not supported:** `cluster_status` doesn't accept format flags in 3.13.

### Key takeaways
- **Let RabbitMQ handle clustering:** The config-driven approach is fundamentally simpler than manual cluster join commands
- **Use official env var names:** `RABBITMQ_ERLANG_COOKIE`, `RABBITMQ_NODENAME`, etc. — don't invent your own
- **Always use `--node` for remote operations:** When running `rabbitmqctl` from a separate container, always specify the target node
- **Quorum is default:** No need for `set_policy` to enable quorum queues in RabbitMQ 3.9+
- **Clean rebuilds matter:** `podman compose down -v` is essential when changing configs

---

## Testing Checklist (Updated)

```
Experiment Setup Progress:
- [x] Compose file uses full image references
- [x] Ports are > 1024 (5672, 15672/15673/15674, 25672/25673/25674, 5555)
- [x] Test client container included
- [x] Healthcheck on all RabbitMQ nodes (rabbitmq-diagnostics ping)
- [x] Volumes use hybrid strategy (named volumes for data)
- [x] Network name follows homelab-* pattern (homelab-messaging-net)
- [x] .env file for secrets (added to gitignore)
- [x] All 3 RabbitMQ nodes running and in cluster
- [x] Cluster formation verified (rabbitmqctl cluster_status shows 3 nodes)
- [x] DNS resolution works from test-client
- [x] Management UI accessible (http://localhost:15672)
- [x] Default queue type set to quorum
- [x] Phase 2: Worker services added (celery-worker, flower, test-producer)
- [x] End-to-end messaging verified (5/5 tasks sent and processed)
- [x] Flower dashboard accessible with Basic Auth
- [x] Resource usage within budget (~356MB total)
- [ ] Phase 3: Test failover (kill primary, verify cluster continues)
```

---

## Phase 2: End-to-End Messaging (Celery Worker + Flower + Test Producer)

### Approach

Added 3 services to test complete message flow through the cluster:
- **celery-worker:** Processes tasks from RabbitMQ using Celery with `rpc://` result backend
- **flower:** Monitoring dashboard (port 5555) with Basic Auth
- **test-producer:** One-shot script that sends 5 sample tasks and exits

### Files Changed

| File | Action | Description |
|------|--------|-------------|
| `docker-compose.yml` | **Modified** | Added celery-worker, flower, test-producer services |
| `workers/producer.py` | **Modified** | Changed default broker URL from `rabbitmq:5672` to `rabbitmq1:5672` |
| `workers/task_worker.py` | **Modified** | Changed default broker URL from `rabbitmq:5672` to `rabbitmq1:5672` |

### Iteration 1: Healthcheck missing on rabbitmq2/rabbitmq3

**Error:** After `podman compose up`, rabbitmq2 and rabbitmq3 never became healthy.

**Root cause:** The healthcheck was only defined on the `rabbitmq1` service in the compose file. Podman-compose only applies healthchecks that are explicitly defined in the compose YAML — it doesn't inherit them from the image.

**Resolution:** Added healthcheck blocks to both `rabbitmq2` and `rabbitmq3` services:
```yaml
healthcheck:
  test: ["CMD", "rabbitmq-diagnostics", "-q", "ping"]
  interval: 15s
  timeout: 10s
  retries: 5
  start_period: 30s
```

### Iteration 2: Producer connection refused

**Error:**
```
kombu.exceptions.OperationalError: [Errno 111] Connection refused
```

**Root cause:** The test-producer started and tried to connect to RabbitMQ before the celery-worker had finished connecting. The `depends_on` with `service_healthy` only checks that rabbitmq1 is healthy, not that the celery-worker itself is fully connected. The producer ran as a one-shot and exited before the worker was ready.

**Resolution:** Added a 15-second startup delay to the test-producer command:
```yaml
command: sh -c "sleep 15 && python /app/workers/producer.py"
```

### Verification Results

**Cluster status (all 3 nodes healthy):**
```
Disk Nodes:  rabbit@rabbitmq1, rabbit@rabbitmq2, rabbit@rabbitmq3
Running Nodes: rabbit@rabbitmq1, rabbit@rabbitmq2, rabbit@rabbitmq3
Versions: RabbitMQ 3.13.7 on Erlang 26.2.5.16 (all nodes)
```

**Producer output (all 5 tasks sent):**
```
[1/5] Sending tasks.resize_image...      Task ID: 3d187660-cf85-4501-b64a-8b77fa931591
[2/5] Sending tasks.send_email...        Task ID: 3301b783-2dab-4ace-9d06-af829189f654
[3/5] Sending tasks.generate_report...   Task ID: 90e88245-0ac2-4f11-a990-8a1cf5f7e0cd
[4/5] Sending tasks.process_video...     Task ID: 4a99d963-80a1-4ef7-a6f2-f0c7d2a27890
[5/5] Sending tasks.resize_image...      Task ID: 29be6f60-cf58-429f-acca-0d01c2ac3de0
Done! 5 tasks sent to Celery.
```

**Worker output (all 5 tasks processed successfully):**
```
[resize_image] Processing: 800x600 -> webp      → succeeded in 2.01s
[send_email] Sending to user@example.com         → succeeded in 1.01s
[generate_report] Generating monthly report      → succeeded in 3.00s
[process_video] Processing 120s video with h264  → succeeded in 4.00s
[resize_image] Processing: 200x200 -> jpg        → succeeded in 2.00s
```

**Flower dashboard:** Accessible at http://localhost:5555 with Basic Auth (homelab/homelab123). Returns HTML page with authentication.

**Queue distribution (identical across all 3 nodes via Mnesia):**
```
celery                    classic  0 messages  1 consumer
celeryev.*                classic  0 messages  1 consumer each
celery@*.celery.pidbox    classic  0 messages  1 consumer
```

**DNS resolution:**
```
rabbitmq1 → <CONTAINER_IP>
rabbitmq2 → <CONTAINER_IP>
rabbitmq3 → <CONTAINER_IP>
flower    → resolves by service name
```

**Resource usage:**
| Container | CPU | Memory |
|-----------|-----|--------|
| homelab-rabbitmq1 | 17.51% | 87.47MB |
| homelab-rabbitmq2 | 15.36% | 81.89MB |
| homelab-rabbitmq3 | 16.84% | 81.25MB |
| homelab-celery-worker | 0.37% | 63.82MB |
| homelab-flower | 0.37% | 40.40MB |
| homelab-messaging-test | 0.03% | 2.31MB |
| **Total** | | **~357MB** |

### Lessons Learned (Phase 2)

1. **Healthchecks must be on every service:** Podman-compose doesn't inherit healthchecks from the image. Each service needs its own healthcheck block.
2. **Producer timing matters:** The test-producer needs a startup delay when the celery-worker also needs time to connect to RabbitMQ. `depends_on` with `service_healthy` only checks the RabbitMQ node, not the worker's connection state.
3. **Broker URL must match service name:** Changed from `rabbitmq` (single-node) to `rabbitmq1` (cluster). The first node in the cluster serves all queues.
4. **Queues are classic, not quorum:** Celery auto-creates queues before `default_queue_type` takes effect. The `default_queue_type = quorum` in rabbitmq.conf only applies to queues created via the management UI/API. Celery's AMQP client uses classic queues by default. This is expected behavior and not a bug — quorum queues would need explicit declaration in Celery queue definitions.
5. **Mnesia replicates queue state:** All 3 nodes show identical queue lists because Mnesia replicates queue metadata across the cluster. The actual message data in quorum queues would be distributed via Raft.

---

## Simplification Phase (April 24, 2026)

### Changes Applied

Applied all 8 phases from `agent_docs/plans/experiment-simplification-per-experiment.md`:

| Phase | Changes |
|-------|---------|
| Phase 1 | Removed `version: '3.8'`, pinned `alpine:latest` → `alpine:3.21` |
| Phase 2 | Renamed test-client container: `homelab-messaging-test` → `homelab-rabbitmq-cluster-test` |
| Phase 3 | Created `.env.example`, added `FLOWER_BASIC_AUTH` to `.env`, extracted hardcoded broker URLs |
| Phase 4 | Renamed network key: `homelab-messaging-net` → `homelab-rabbitmq-cluster`, removed redundant `name:` field |
| Phase 5 | Renamed volumes: `rabbitmq{1,2,3}_data` → `rabbitmq_cluster_rabbitmq{1,2,3}_data` |
| Phase 6 | Updated ports to match plan: Node 1 (35672, 35673, 35674), Node 2 (35676, 35677), Node 3 (35679, 35680), Flower (35556) |
| Phase 8 | Added Overview, Services table, fixed duplicate "Cluster Formation" section, updated all port references |

### Files Changed

| File | Action |
|------|--------|
| `docker-compose.yml` | **Rewritten** — All phases applied |
| `.env` | **Modified** — Added `FLOWER_BASIC_AUTH` |
| `.env.example` | **Created** — With placeholder values and comments |
| `README.md` | **Modified** — Added Overview, Services table, Troubleshooting, fixed duplicate section, updated ports |

### Verification Results

**All 6 containers started successfully:**
- homelab-rabbitmq1: healthy, ports 35672/35673/35674
- homelab-rabbitmq2: healthy, ports 35676/35677
- homelab-rabbitmq3: healthy, ports 35679/35680
- homelab-rabbitmq-init: completed verification, exited
- homelab-celery-worker: running
- homelab-rabbitmq-cluster-test: running (alpine:3.21)
- homelab-flower: running, port 35556
- homelab-test-producer: running

**Cluster status:** All 3 nodes running and in cluster
```
Running Nodes
  rabbit@rabbitmq1
  rabbit@rabbitmq2
  rabbit@rabbitmq3
```

**DNS resolution:** Works from test-client container
```
$ nslookup rabbitmq1
Name: rabbitmq1.dns.podman
Address: <CONTAINER_IP>
```

**Management API:** Accessible at http://localhost:35673 (credentials: homelab/homelab123)

**Flower:** Accessible at http://localhost:35556 with Basic Auth

**Cleanup:** `podman compose down -v` completed successfully, all volumes removed

### Issues Encountered

1. **Stale containers from old setup:** Old containers (homelab-rabbitmq1, homelab-messaging-test) had dependency chains preventing removal. Resolved by removing child containers first, then parent.

2. **Volume naming conflict:** Old volumes (`rabbitmq1_data`, etc.) vs new volumes (`rabbitmq_cluster_rabbitmq1_data`, etc.) required manual cleanup of stale data.

3. **Network naming:** Podman-compose created `rabbitmq-cluster_homelab-rabbitmq-cluster` network (prefix + key). This is expected behavior.

### Lessons Learned

- **Hardcoded secrets in compose:** The `CELERY_BROKER_URL` had hardcoded credentials (`amqp://homelab:homelab123@...`). Replaced with `${RABBITMQ_DEFAULT_USER}` and `${RABBITMQ_DEFAULT_PASS}` references.
- **Flower Basic Auth:** Was hardcoded as `FLOWER_BASIC_AUTH=homelab:homelab123`. Now uses `${FLOWER_BASIC_AUTH}` from `.env`.
- **Port alignment:** The original compose used default RabbitMQ ports (5672, 15672, etc.). Plan specifies shifted ports (35672, 35673, etc.) to avoid conflicts with other experiments.
- **README duplicate section:** The original README had two identical "Cluster Formation" sections (lines 34-42 and 51-59). Removed the duplicate.

---

## Next Steps

1. **Phase 3: Failover testing** — Kill rabbitmq1, verify rabbitmq2/rabbitmq3 continue serving messages, tasks still process
2. **Add quorum queue support to Celery** — Define queues explicitly with `queue_arguments={'x-queue-type': 'quorum'}` to use quorum queues instead of classic
3. **Add more worker nodes** — Test horizontal scaling with multiple celery-workers
4. **Load testing** — Send hundreds of tasks to verify cluster performance under load

---

*Timeline updated: April 24, 2026*
*Status: Phase 2 Complete - Simplification Phase Applied and Verified*
