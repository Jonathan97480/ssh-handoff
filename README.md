# ssh-handoff

Secure shared terminal handoff for cases where a human must authenticate first and the agent must resume work in the same shell session afterward.

## What it does

This skill is built around a simple pattern:

1. keep terminal state inside a named `tmux` session
2. let the human complete the sensitive login step
3. let the agent continue in that exact same shell session

It supports three practical modes:

- plain `tmux` handoff
- local browser terminal via `ttyd`
- LAN-restricted browser terminal with one-shot URL token

## Included files

- `SKILL.md` — operational instructions for the agent
- `scripts/` — launchers and proxy code
- `references/` — design notes and usage examples

## Recommended use

For repeated use on a trusted LAN, the recommended mode is:

- `tmux` session per task
- `ttyd` bound on localhost
- local proxy with one-shot token
- firewall limited to the trusted client IP
- `FORBID_REUSE_IF_AUTHENTICATED=1` by default

## Requirements

- `tmux`
- `ttyd`
- `node`
- `python3`

## Safety notes

- keep it local-only by default
- if exposed on LAN, restrict access to one trusted client IP
- do not expose through a public tunnel or reverse proxy
- use short TTLs and clean up after use

## Repository scope

This repository contains only the `ssh-handoff` skill and its bundled resources.
