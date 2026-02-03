# HEARTBEAT.md

## Checks (run silently, only message if action needed)

- Disk space: alert if <10% free on any mount
- Failed systemd services: `systemctl --failed`
- OpenClaw gateway health: `openclaw health`
- OpenClaw version: check `openclaw --version` vs `npm show openclaw version` — auto-update if outdated

## Rules

- Late night (23:00-08:00): HEARTBEAT_OK unless critical
- If nothing needs attention: HEARTBEAT_OK
- Don't repeat alerts already acknowledged
- Keep heartbeat token usage minimal
- Auto-update OpenClaw without asking (user approved)
