# Secure web-terminal design notes

## Goal

Allow a user to authenticate in a browser-opened terminal without changing the OpenClaw UI, while keeping the terminal local and temporary.

## Security envelope

Default requirements:

- bind server to `127.0.0.1` only
- use a random high port
- require a temporary token or password
- use a tmux session as the actual terminal state holder
- stop the web-terminal process after the task
- never expose through a public tunnel, reverse proxy, or external host without explicit user approval

## Recommended runtime shape

A wrapper script can:

1. ensure the tmux session exists
2. generate a token
3. choose an unused port
4. launch the web terminal bound to localhost only
5. print the local URL
6. optionally record pid + metadata for cleanup

Pseudo-flow:

```text
ensure tmux session
port = choose random free localhost port
token = generate strong random token
launch terminal-web-server(host=127.0.0.1, port=port, token=token, command='tmux attach -t SESSION')
return local URL
```

## UX notes

Ideal user message:

- one URL
- one short warning: local-only, temporary
- one success criterion: stop when the remote prompt is visible

## Failure modes

### No terminal-web binary installed

Return a plain explanation and offer:

- fallback to normal tmux handoff, or
- installation with approval

### User cannot access localhost on the host machine

Do not automatically create an internet-reachable path. Ask first. Prefer local workstation access or a trusted internal-only route.

### Session state unclear

Capture pane, look for prompts, and if needed send `Ctrl-C` once before continuing.

## Candidate tools

### ttyd

Pros:

- lightweight
- common on Linux
- easy command wrapper

Questions to confirm during implementation:

- auth/token flags available on installed version
- URL and credential format
- TLS expectations when bound only to localhost

### Wetty

Pros:

- browser terminal purpose-built
- Node-friendly

Questions to confirm during implementation:

- auth support model
- command attach pattern to tmux
- install footprint

## Suggested implementation split

- `SKILL.md`: workflow + guardrails
- `scripts/start-local-web-terminal.sh` or Python launcher: deterministic setup
- `references/design-notes.md`: security and design rationale

## Non-goals

- embedding terminal directly into OpenClaw UI
- public exposure by default
- persistent shared terminal service with no expiration
