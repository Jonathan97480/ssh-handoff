# SSH handoff examples

## Example 1: BlogAi Pi verification

Goal: user logs into the Raspberry Pi manually, then the agent compares the repo state with GitHub.

Suggested flow:

1. Create session `blogai-pi`
2. Ask user to attach: `tmux attach -t blogai-pi`
3. User runs SSH login inside tmux
4. Agent captures pane and checks for remote prompt
5. Agent sends:

```bash
cd /home/admin-rpi/projects/BlogAi
git branch --show-current
git rev-parse --short HEAD
git status --short
```

## Example 2: Temporary sudo handoff

Goal: user enters sudo password once, then agent performs a few read-only admin checks.

Suggested flow:

1. Create session `server-admin`
2. User attaches
3. User runs `sudo -s` or a single `sudo` command
4. Agent resumes from the same authenticated shell
5. Agent captures output after every command

## Example 3: Recovery when session state is unclear

If output suggests nested SSH, vim, less, or a hung prompt:

1. capture pane first
2. if needed send `Ctrl-C`
3. capture again
4. only then continue
