# Claude Workspace

A workspace manager for [Claude Code](https://claude.ai/code) that supercharges your AI-assisted development workflow.

<p align="center">
  <img src="docs/demo.gif" alt="Claude Workspace Demo" width="800">
</p>

## Features

- **Split-Pane Workspaces** — Launch Claude Code alongside your dev processes in Ghostty split panes
- **Dev Log Monitoring** — Claude can check your dev process output instead of running redundant builds
- **Auto Cleanup** — Dev processes automatically terminate when Claude exits
- **Project Registry** — Quick-switch between projects with an interactive menu
- **Multi-AI Delegation** — Optionally delegate simple tasks to Gemini or other AI models

## Quick Start

### Installation

```bash
# Clone and install
git clone https://github.com/malipetek/claude-workspace.git
cd claude-workspace
./install.sh
```
```bash
# Or one-liner
curl -fsSL https://raw.githubusercontent.com/malipetek/claude-workspace/refs/heads/main/install.sh | bash
```

### Setup

Run the interactive setup wizard:

```bash
claude-workspace setup
```

Or add a project manually:

```bash
claude-workspace add ~/Projects/my-app
```

### Usage

```bash
# Launch interactive project selector
claude-workspace

# Open specific project
claude-workspace my-app

# Open in simple mode (Claude only, no workspace)
claude-workspace --simple my-app
```

## How It Works

### Workspace Layout

When you launch a project with a `.ai-workspace.json` config, Claude Workspace creates a Ghostty split-pane layout:

```
┌─────────────────────────────┬─────────────────────────────┐
│                             │         frontend            │
│                             │         pnpm dev            │
│          Claude             ├─────────────────────────────┤
│           Code              │         backend             │
│                             │         pnpm dev            │
│                             ├─────────────────────────────┤
│                             │         database            │
│                             │      docker compose up      │
└─────────────────────────────┴─────────────────────────────┘
```

### Dev Log Capture

All dev processes are wrapped to capture their output. Claude can check for errors without running separate builds:

```bash
# Claude runs this instead of `npm run build`
~/.claude-workspace/scripts/dev-logs.sh summary

# Output:
# === Dev Process Summary: my-app ===
# ✓ frontend: OK
# ❌ backend: 3 errors
# ✓ database: OK
```

### Auto Cleanup

When you exit Claude (type `/exit` or press `Ctrl+C`), all dev processes are automatically terminated:

```
Claude exited. Cleaning up workspace...
  Stopping frontend (PID: 12345)...
  ✓ frontend stopped
  Stopping backend (PID: 12346)...
  ✓ backend stopped
✓ Cleanup complete
```

## Configuration

### Project Config (`.ai-workspace.json`)

Create this file in your project root:

```json
{
  "processes": [
    {
      "name": "frontend",
      "command": "pnpm dev",
      "cwd": "./frontend"
    },
    {
      "name": "backend",
      "command": "pnpm dev",
      "cwd": "./backend"
    },
    {
      "name": "database",
      "command": "docker compose up",
      "cwd": "."
    }
  ],
  "hooks": {
    "before_start": "docker compose up -d redis"
  }
}
```

### Process Options

| Option | Description | Default |
|--------|-------------|---------|
| `name` | Process identifier (used in logs) | Required |
| `command` | Command to run | Required |
| `cwd` | Working directory (relative to project root) | `.` |

### Hooks

| Hook | Description |
|------|-------------|
| `before_start` | Run before launching workspace (e.g., start databases) |

## Commands

### Main Commands

| Command | Description |
|---------|-------------|
| `claude-workspace` | Interactive project selector |
| `claude-workspace <project>` | Open specific project |
| `claude-workspace setup` | Run setup wizard |
| `claude-workspace add <path>` | Add project to registry |
| `claude-workspace --simple <project>` | Open without workspace (Claude only) |
| `claude-workspace --help` | Show help |

### Utility Commands

| Command | Description |
|---------|-------------|
| `cw-logs summary` | Check dev process status |
| `cw-logs errors` | Show all errors |
| `cw-logs tail <name> [n]` | Tail a specific log |
| `cw-cleanup <project>` | Manually stop all dev processes |

### Keyboard Shortcuts (Interactive Mode)

| Key | Action |
|-----|--------|
| `↑/↓` | Navigate projects |
| `Enter` | Launch (with workspace if available) |
| `w` | Force workspace mode |
| `s` | Force simple mode |
| `q` | Quit |

### Keyboard Shortcuts (Ghostty)

| Key | Action |
|-----|--------|
| `Cmd+]` | Next pane |
| `Cmd+[` | Previous pane |
| `Cmd+Alt+Arrow` | Navigate to pane |
| `Cmd+Shift+Enter` | Zoom current pane |

## Requirements

### Required

- **macOS** (uses AppleScript for Ghostty automation)
- **[Claude Code](https://claude.ai/code)** — The AI coding assistant
- **[jq](https://stedolan.github.io/jq/)** — JSON processor (`brew install jq`)

### Recommended

- **[Ghostty](https://ghostty.org/)** — Fast, native terminal with split panes
- **Accessibility Permissions** — Required for Ghostty automation

### Optional

- **[Gemini CLI](https://github.com/google/generative-ai-cli)** — For AI delegation features

## Ghostty Permissions

For split-pane workspaces, Ghostty needs Accessibility permissions:

1. Open **System Settings** → **Privacy & Security** → **Accessibility**
2. Click **+** and add **Ghostty**
3. Enable the checkbox
4. **Restart Ghostty**

Run `claude-workspace setup` and select option 5 to test permissions.

## Project Structure

```
~/.claude-workspace/
├── scripts/
│   ├── ai-project          # Main project switcher
│   ├── workspace.sh        # Workspace launcher
│   ├── dev-run.sh          # Dev process wrapper
│   ├── dev-logs.sh         # Log reader
│   ├── setup.sh            # Setup wizard
│   └── ...
├── templates/              # Example configs
├── dev-logs/               # Captured dev process logs
│   └── <project>/
│       ├── frontend.log
│       └── backend.log
├── registry.json           # Project registry
└── aliases.sh              # Shell aliases
```

## Shell Aliases

Add to your `~/.zshrc` or `~/.bashrc`:

```bash
source ~/.claude-workspace/aliases.sh
```

Available aliases:

```bash
dev <name> <cmd>     # Run dev process with logging
devlogs              # Check dev logs
deverrors            # Show all errors
workspace <path>     # Open workspace
ws <path>            # Short alias for workspace
```

## Multi-AI Delegation (Advanced)

Claude Workspace can delegate simple tasks to other AI models:

```bash
# Delegate to Gemini
~/.claude-workspace/scripts/delegate-async.sh gemini \
  "Generate TypeScript interfaces for the User API" \
  /path/to/project
```

This is useful for:
- Type generation
- Boilerplate code
- Simple tests
- Documentation

## Troubleshooting

### "osascript is not allowed to send keystrokes"

Ghostty needs Accessibility permissions. See [Ghostty Permissions](#ghostty-permissions).

### Dev processes not showing in logs

Make sure processes are started with the `dev-run.sh` wrapper. The workspace launcher does this automatically.

### Claude not finding dev logs

Claude checks logs based on the current git repository. Make sure you're in the project directory.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

MIT License — see [LICENSE](LICENSE) for details.

## Acknowledgments

- [Claude Code](https://claude.ai/code) by Anthropic
- [Ghostty](https://ghostty.org/) by Mitchell Hashimoto
