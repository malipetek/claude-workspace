# Claude Workspace Aliases
# Add to your .bashrc or .zshrc:
#   source ~/.claude-workspace/aliases.sh

# Main command
alias claude-workspace='~/.claude-workspace/scripts/ai-project'
alias cw='~/.claude-workspace/scripts/ai-project'

# Dev process runner (wraps commands with logging)
alias dev='~/.claude-workspace/scripts/dev-run.sh'

# Dev logs shortcuts
alias devlogs='~/.claude-workspace/scripts/dev-logs.sh'
alias deverrors='~/.claude-workspace/scripts/dev-logs.sh errors'
alias devsummary='~/.claude-workspace/scripts/dev-logs.sh summary'

# Workspace commands
alias workspace='~/.claude-workspace/scripts/workspace.sh'
alias ws='~/.claude-workspace/scripts/workspace.sh'

# Cleanup
alias cw-cleanup='~/.claude-workspace/scripts/workspace-cleanup.sh'
alias cw-logs='~/.claude-workspace/scripts/dev-logs.sh'

# Settings
alias cw-settings='~/.claude-workspace/scripts/settings.sh'

# AI delegation (optional)
alias delegate='~/.claude-workspace/scripts/delegate.sh'
alias delegate-async='~/.claude-workspace/scripts/delegate-async.sh'
alias ai-status='~/.claude-workspace/scripts/check-status.sh'

# Quick dev process helpers
alias dev-frontend='~/.claude-workspace/scripts/dev-run.sh frontend'
alias dev-backend='~/.claude-workspace/scripts/dev-run.sh backend'
