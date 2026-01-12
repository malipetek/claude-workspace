# Claude Workspace Integration

You have access to a workspace management system at `~/.claude-workspace/`. This system helps manage dev processes and their logs.

## Dev Process Log Monitoring

The user runs dev processes (npm run dev, cargo watch, etc.) in separate terminal panes. Instead of running build commands to check for errors, check the dev logs first.

### Checking Dev Logs (Use This Before Running Builds!)

```bash
# Quick summary - are there errors?
~/.claude-workspace/scripts/dev-logs.sh summary

# See all errors across all dev processes
~/.claude-workspace/scripts/dev-logs.sh errors

# Recent errors only (last 100 lines per log)
~/.claude-workspace/scripts/dev-logs.sh recent

# Tail a specific log
~/.claude-workspace/scripts/dev-logs.sh tail frontend 100
```

### Workflow

1. **After making code changes**: Run `dev-logs.sh summary` to check if dev processes show errors
2. **If errors exist**: Run `dev-logs.sh errors` to see details
3. **Fix errors**: Make the necessary fixes
4. **Verify**: Check `dev-logs.sh summary` again - dev processes in watch mode will have recompiled
5. **Only run manual builds**: If dev logs are clean and you need to verify production build

### Why This Matters

- **Faster feedback**: Dev processes already have the errors, no need to run a build
- **Less noise**: No duplicate build output cluttering the conversation
- **Real-time**: Watch mode processes show errors immediately after file save

## AI Delegation (Optional)

If configured, you can delegate simple tasks to other AI models:

```bash
~/.claude-workspace/scripts/delegate-async.sh gemini "Generate TypeScript types for..." /path/to/project
```

Check status:
```bash
~/.claude-workspace/scripts/check-status.sh running
```
