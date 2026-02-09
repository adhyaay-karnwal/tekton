# NixOS Setup for Claude Code Agents on Hetzner

> Inspired by [Michael Stapelberg's blog post](https://michael.stapelberg.ch/posts/2026-02-01-coding-agent-microvm-nix/) on running coding agents in NixOS. Uses [nixos-anywhere](https://github.com/nix-community/nixos-anywhere) for remote NixOS installation and imperative [systemd-nspawn](https://www.freedesktop.org/software/systemd/man/latest/systemd-nspawn.html) containers for lightweight, instant agent creation.

This repo sets up a Hetzner bare metal server with NixOS and nspawn containers for running Claude Code agents in isolated, ephemeral environments. Spinning up a new agent is a single command — no config files to edit, no rebuilds.

## Directory Structure

```
nixos-claude/
├── README.md
├── setup.sh                     # Automated setup script
├── initial-install/             # Used once for nixos-anywhere installation
│   ├── flake.nix
│   ├── disk-config.nix          # RAID 1 across two SSDs
│   └── configuration.nix
└── server-config/               # Copied to /etc/nixos after install
    ├── flake.nix
    ├── configuration.nix        # Host server config
    ├── agent-config.nix         # Reusable agent container config
    └── agent.sh                 # Agent lifecycle helper script
```

## Prerequisites

- Local machine with [Nix installed](https://nixos.org/download/) (flakes enabled)
- SSH key pair (`ssh-keygen` if you don't have one)
- Hetzner account

## Setup

### Step 1: Provision Hetzner Server

1. Order a dedicated server at [Hetzner Robot](https://robot.hetzner.com) (e.g., AX41-NVMe)
2. Wait for provisioning, note your server IP
3. Activate rescue mode: Server → Rescue tab → Activate Linux 64-bit
4. Reset the server: Reset tab → Hardware reset
5. Wait a minute for the server to boot into rescue mode

### Step 2: Run the Setup Script

```bash
./setup.sh
```

The script will:
1. **Prompt** for your server IP and SSH public key
2. **Auto-detect** the gateway, network interface, and prefix length by SSHing into rescue mode
3. **Install NixOS** via nixos-anywhere (takes ~5-10 minutes)
4. **Configure the server** with container support and copy the server config
5. **Run `claude login`** interactively so you can authenticate via OAuth

No manual editing of configuration files is needed - the script handles all substitutions on temporary copies and leaves the repo files untouched.

## Using Agent Containers

### Create an agent

```bash
ssh root@YOUR_SERVER_IP 'agent create myagent'
```

This instantly creates and starts a new container with its own IP, SSH access, and Claude credentials. The first run builds the container config (takes a few minutes); subsequent creates are near-instant.

### SSH into an agent

From the host:
```bash
agent ssh myagent
```

From your local machine (uses SSH jump):
```bash
ssh -J root@YOUR_SERVER_IP agent@<container-ip>
```

### Run Claude

```bash
# Regular mode
claude

# Skip all permission prompts (for automation)
claude --dangerously-skip-permissions
```

### List agents

```bash
ssh root@YOUR_SERVER_IP 'agent list'
```

### Destroy an agent

```bash
ssh root@YOUR_SERVER_IP 'agent destroy myagent'
```

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Container fails to start | Check `journalctl -u container@<name>` on host |
| SSH host key warning after container recreate | `ssh-keygen -R <container-ip>` |
| Claude "Invalid API key" in container | Re-run `claude login` on host with `CLAUDE_CONFIG_DIR=/var/secrets/claude`, fix permissions, recreate container |
| Claude permission errors | `chmod -R a+rX /var/secrets/claude` on host, then recreate container |
| systemd-networkd-wait-online timeout | Benign - ignore it |
| Claude hangs on startup | Check credentials exist: `ls /home/agent/.claude/` in container |
| Claude shows onboarding screen | Credentials not copied - check `/mnt/claude-creds/` is mounted and has files |

## Quick Reference

```bash
# Agent management (run on host as root)
agent create myagent
agent ssh myagent
agent list
agent destroy myagent

# Rebuild after config changes
cd /etc/nixos && nixos-rebuild switch

# Re-authenticate Claude (on host)
CLAUDE_CONFIG_DIR=/var/secrets/claude claude login
chmod -R a+rX /var/secrets/claude

# Verify credentials in container
agent ssh myagent
ls -la /home/agent/.claude/
echo $CLAUDE_CONFIG_DIR  # Should show /home/agent/.claude
```
