## TLDR Code Analysis (Preferred)

This project has TLDR indexes for efficient code exploration. **ALWAYS prefer TLDR tools over reading raw files** when understanding code structure.

### Available MCP Tools

| Tool | Use Case | Example |
|------|----------|---------|
| `tldr_context` | Understand a function/class | `tldr context MyClass --project .` |
| `tldr_semantic` | Search by behavior/concept | `tldr semantic "error handling" .` |
| `tldr_impact` | Find callers before refactoring | `tldr impact processPayment .` |

### Recommended Workflow

1. **Exploring unfamiliar code?** Start with `tldr semantic "what you're looking for"`
2. **Understanding a specific symbol?** Use `tldr context function_name`
3. **Before modifying a function?** Check `tldr impact function_name` for callers
4. **Need exact implementation?** Only then read raw files

### Why Use TLDR?

- **95% fewer tokens** than reading raw source files
- **Semantic understanding** - finds code by behavior, not just text
- **Cross-file awareness** - understands dependencies and call graphs
- **Faster responses** - pre-indexed for instant queries

### Refreshing Indexes

If code has changed significantly, refresh indexes with:
```bash
tldr warm .
```
