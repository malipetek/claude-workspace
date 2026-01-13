## Workspace Dev Processes

This project runs with **live dev processes in watch mode**. All terminals are captured and logs are available for you to read.

### Key Points

1. **No manual builds needed** - All processes run in watch mode and auto-reload on file changes
2. **Logs are captured** - All terminal output is saved to `~/.claude-workspace/dev-logs/<project>/`
3. **Check logs after changes** - After editing files, check the logs to verify changes compiled/reloaded correctly

### Checking Dev Process Logs

**Quick summary of all processes:**
```bash
~/.claude-workspace/scripts/dev-logs.sh summary
```

**Check specific process logs:**
```bash
# Last 50 lines from a process
~/.claude-workspace/scripts/dev-logs.sh tail <process_name>

# Last 100 lines
~/.claude-workspace/scripts/dev-logs.sh tail <process_name> 100

# Only error lines
~/.claude-workspace/scripts/dev-logs.sh errors <process_name>

# Recent errors across all processes
~/.claude-workspace/scripts/dev-logs.sh recent
```

**List available processes:**
```bash
~/.claude-workspace/scripts/dev-logs.sh list
```

### After Making Code Changes

1. **Wait 1-2 seconds** for hot reload to trigger
2. **Check the logs** to verify the change compiled successfully:
   ```bash
   ~/.claude-workspace/scripts/dev-logs.sh summary
   ```
3. **If errors appear**, check details:
   ```bash
   ~/.claude-workspace/scripts/dev-logs.sh errors
   ```

### Common Process Names

Typical process names in this workspace:
- `frontend` - Frontend dev server (Next.js, Vite, etc.)
- `backend` - Backend API server
- `database` - Database or Docker services
- `types` - TypeScript compiler in watch mode
- `worker` - Background job processor

### DO NOT

- Run `npm run build` or `npm run dev` - processes are already running
- Ask the user to check terminal output - read the logs yourself
- Assume builds need to be triggered - watch mode handles this

### Log File Location

Direct log file paths:
```
~/.claude-workspace/dev-logs/<project>/<process>.log
```

You can also read these directly:
```bash
tail -100 ~/.claude-workspace/dev-logs/<project>/<process>.log
```
