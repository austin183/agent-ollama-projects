# Vaultwarden Secure ADMIN_TOKEN — Experiment Timeline

## 2026-05-02 — ASUS TUF — Iteration 1: Plaintext token warning reproduced

**Goal:** Reproduce the plaintext ADMIN_TOKEN warning.

**Setup:**
- Created `infrastructure/vaultwarden-secure-token/` with docker-compose.yml
- Using port 8087 (8086 occupied by existing vaultwarden experiment)
- Initial `.env` contains plaintext token `plaintext-token-for-testing`

**Pre-flight:**
- Port 8087: available
- Port 8086: in use by `homelab-vaultwarden` (expected)

**Verification:**
- Container started and became healthy
- Logs confirmed: `[NOTICE] You are using a plain text ADMIN_TOKEN which is insecure.`
- Admin page reachable at `http://localhost:8087/admin`

## 2026-05-02 — ASUS TUF — Iteration 2: Init container approach

**Goal:** Use an initializer container with `argon2` CLI to hash the plaintext password and pass the PHC string to vaultwarden via shared volume.

**Architecture:**
- `init` service: Alpine + argon2 + openssl, generates PHC string, writes to `phc_data` volume
- `vaultwarden` service: reads PHC string from shared volume at startup via custom entrypoint
- Shared `phc_data` volume passes the hashed token between containers

**Issues:**
- `vaultwarden hash` command requires a TTY for password prompts — doesn't work non-interactively
- Vaultwarden image doesn't include `argon2` CLI
- Initial attempt: bind-mounted script failed with `OCI permission denied` (rootless Podman doesn't preserve execute bits on bind mounts)
- **Fix:** Use `command: ["sh", "/hash-token.sh"]` instead of direct execution
- Second attempt: `entrypoint: ["sh", "/entrypoint.sh"]` didn't propagate ADMIN_TOKEN to PID 1
- **Fix:** Use `entrypoint: ["sh", "-c"]` + `command: ['export ADMIN_TOKEN="..."; exec /start.sh']`

**Resolution:**
- Init container generates PHC string using argon2 with Bitwarden defaults (m=65540, t=3, p=4)
- Vaultwarden entrypoint reads PHC string from `/shared/phc-token` and exports as `ADMIN_TOKEN`
- No more plaintext token warning in logs

**Verification:**
- Container status: healthy
- No `[NOTICE]` warning in logs
- `cat /proc/1/environ | tr '\0' '\n' | grep ADMIN` shows `$argon2id$v=19$m=65540,t=3,p=4$...`
- Admin page reachable at `http://localhost:8087/admin`
- Resource usage: 7.3MB RAM, near-zero CPU

**Learnings:**
- `vaultwarden hash` needs a TTY; use `argon2` CLI for non-interactive hashing
- Rootless Podman doesn't preserve execute permissions on bind-mounted scripts — run through `sh`
- Podman-compose entrypoint array format `["sh", "-c"]` works as two separate args
- `export` in entrypoint command propagates to `exec`'d process but not to `podman exec` subshells
- Check `/proc/1/environ` to verify PID 1's actual environment
