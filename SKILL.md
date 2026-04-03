---
name: ssh-handoff
description: Create and reuse a secure shared terminal handoff when a human must authenticate first and the agent must resume work in the same shell session afterward. Use for SSH handoff, sudo handoff, browser-opened temporary terminal access, or LAN-restricted terminal sharing backed by tmux when direct agent authentication is blocked or undesirable.
---

# SSH Handoff

Use this skill to let a human authenticate first, then continue the task in the exact same terminal session as the agent.

The core idea is simple:

1. keep terminal state in a named `tmux` session
2. let the human perform the sensitive login step
3. let the agent resume work in that same shell

Prefer this skill when the user should not paste credentials into chat and when the agent cannot authenticate directly.

## Recommended modes

Choose the simplest mode that fits the situation.

### Mode A — plain tmux handoff

Use when the user already has terminal access to the host machine.

Typical flow:

1. create or reuse a named tmux session
2. ask the user to attach
3. user logs in or authenticates
4. agent captures the pane and continues

Example attach command:

```bash
tmux attach -t blogai-pi
```

### Mode B — local browser terminal with temporary credentials

Use when the user wants a browser-based terminal on the same machine that hosts the service.

This mode uses `ttyd` directly and is suitable for:

- localhost-only access
- quick temporary sessions
- cases where basic auth is acceptable

Bundled launcher:

```bash
./scripts/start-local-web-terminal.sh blogai-pi
```

### Mode C — LAN-restricted browser terminal with one-shot URL token

Use when the user wants to open the terminal from another machine on the same local network and you want less friction than username/password entry.

This is the **recommended daily-use mode** once configured.

It works like this:

1. a tmux session holds the real shell state
2. `ttyd` runs on localhost only as the terminal backend
3. a small local proxy exposes a LAN URL with a one-shot `?token=`
4. the first valid request becomes a browser session via cookie
5. the agent continues using the same tmux session

Bundled launcher:

```bash
./scripts/start-url-token-web-terminal.sh blogai-pi
```

## Final recommended configuration

For normal repeated use on a trusted local network, keep this setup:

- tmux session name: task-specific, for example `blogai-pi`
- proxy frontend port: **`48080`**
- localhost ttyd backend port: **`48081`**
- firewall rule: allow only the user machine IP to reach `48080`
- launch service only when needed
- stop service after use
- keep the firewall rule if the same trusted client uses it regularly

### Example permanent LAN rule

If the user machine is `192.168.1.30`:

```bash
sudo ufw allow from 192.168.1.30 to any port 48080 proto tcp
```

This avoids reopening a new firewall rule every session.

## Quick usage

### Plain tmux handoff

```bash
tmux has-session -t blogai-pi 2>/dev/null || tmux new-session -d -s blogai-pi
tmux attach -t blogai-pi
```

After the user authenticates, inspect and continue:

```bash
tmux capture-pane -t blogai-pi -p | tail -60
tmux send-keys -t blogai-pi -l -- 'cd /home/admin-rpi/projects/BlogAi && git status --short'
sleep 0.1
tmux send-keys -t blogai-pi Enter
```

### Local browser mode

```bash
./scripts/start-local-web-terminal.sh blogai-pi
```

The script prints:

- URL
- temporary credentials
- PID
- expiry
- stop command

### Final LAN token mode

Recommended launch:

```bash
HOST=192.168.1.28 CLIENT_IP=192.168.1.30 PORT=48080 UPSTREAM_PORT=48081 FORBID_REUSE_IF_AUTHENTICATED=1 ./scripts/start-url-token-web-terminal.sh blogai-pi
```

The script prints:

- URL with one-shot token
- expiry
- proxy/backend PIDs
- UFW allow/delete commands

Example result:

```text
URL=http://192.168.1.28:48080/?token=...
```

## Configuration

### Required binaries

Check these first:

```bash
command -v tmux
command -v ttyd
command -v node
```

### Install on Debian / Ubuntu

```bash
sudo apt update && sudo apt install -y tmux ttyd
```

`node` must also exist for Mode C because the proxy launcher uses a bundled Node script.

### Launcher variables

#### `start-local-web-terminal.sh`

Supported variables:

- `HOST` — bind address, default `127.0.0.1`
- `PORT` — optional explicit port, otherwise random free port
- `TTL_MINUTES` — default `30`
- `BIND_SCOPE` — metadata only, usually `local` or `lan`
- `CLIENT_IP` — optional, used only to print UFW helper commands in LAN mode

#### `start-url-token-web-terminal.sh`

Supported variables:

- `HOST` — proxy bind address, default `127.0.0.1`
- `PORT` — proxy frontend port, default **`48080`**
- `UPSTREAM_PORT` — localhost ttyd backend port, default **`48081`**
- `CLIENT_IP` — optional client IP for UFW helper commands and proxy-side IP filtering
- `TTL_MINUTES` — default `30`
- `BIND_SCOPE` — metadata only, usually `local` or `lan`
- `COOKIE_SECURE` — set to `1` when serving through local HTTPS so the session cookie gets the `Secure` flag
- `EXPECTED_HOST` — strict allowed `Host` header, default `<HOST>:<PORT>`
- `EXPECTED_ORIGIN` — strict allowed websocket `Origin`, default derived from host and cookie mode
- `FORBID_REUSE_IF_AUTHENTICATED` — set to `1` to refuse startup if the tmux pane already looks authenticated
- `AUTH_GUARD_REGEX` — optional override for the pane-authentication detection regex

If `48080` or `48081` are already occupied, override them explicitly.

Example:

```bash
HOST=192.168.1.28 CLIENT_IP=192.168.1.30 PORT=49080 UPSTREAM_PORT=49081 ./scripts/start-url-token-web-terminal.sh blogai-pi
```

## How to use Mode C correctly

1. ensure the tmux session exists
2. launch the v5 URL-token terminal
3. if needed, ensure UFW allows `48080` from the user IP only
4. send the user the printed URL
5. user opens the URL and authenticates inside the terminal if needed
6. agent resumes through tmux
7. stop the proxy/backend processes when done

### Example end-to-end

```bash
HOST=192.168.1.28 CLIENT_IP=192.168.1.30 PORT=48080 UPSTREAM_PORT=48081 FORBID_REUSE_IF_AUTHENTICATED=1 ./scripts/start-url-token-web-terminal.sh blogai-pi
```

Then tell the user to open the printed URL.

After they are done, stop the services:

```bash
kill <proxy-pid>
kill <ttyd-pid>
```

## Verify handoff before continuing

Always capture the pane before assuming authentication worked:

```bash
tmux capture-pane -t blogai-pi -p | tail -80
```

Look for:

- remote hostname or prompt
- expected working directory
- absence of password prompt

If uncertain, ask one short confirmation question.

## Guardrails

- Keep exposure local-only by default.
- If LAN exposure is needed, restrict it to one trusted client IP only.
- Do not expose the terminal through a public tunnel or reverse proxy.
- Do not ask the user to paste passwords, OTP codes, or private keys into chat if the handoff can avoid it.
- Use short-lived access material for browser modes.
- Prefer one tmux session per target/task.
- Inspect pane state before sending more commands.
- Ask before destructive actions.
- Enable `FORBID_REUSE_IF_AUTHENTICATED=1` by default for normal use; disable it only when you intentionally want to reopen an already-authenticated session.
- Treat the printed URL as sensitive until expiry; do not log or repost it unnecessarily.
- Expect the proxy to reject mismatched `Host`, websocket `Origin`, or client IP when those checks are configured.

## Cleanup

To stop a temporary web-terminal process while preserving tmux, use:

```bash
./scripts/stop-local-web-terminal.sh <pid> <session-name>
```

For Mode C, prefer the printed cleanup command because it removes both processes and the temporary runtime directory:

```bash
TTYD_PID=<ttyd-pid> PROXY_PID=<proxy-pid> RUNTIME_DIR=<runtime-dir> <cleanup-script>
```

If you lose that command, killing both printed PIDs is still acceptable:

```bash
kill <proxy-pid>
kill <ttyd-pid>
```

The launcher also installs automatic TTL cleanup for proxy, ttyd, and temporary files. Leave the tmux session alive if it may be reused.

## References

Read these when needed:

- `references/examples.md` — concrete usage examples
- `references/design-notes.md` — security and design envelope
- `references/lan-restricted.md` — LAN-only restricted-IP pattern

Bundled scripts:

- `scripts/start-local-web-terminal.sh`
- `scripts/start-url-token-web-terminal.sh`
- `scripts/stop-local-web-terminal.sh`
- `scripts/url-token-proxy.js`
