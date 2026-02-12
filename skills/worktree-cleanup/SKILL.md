---
name: worktree-cleanup
description: Remove worktrees and optionally delete branches for a completed task. Use after finishing parallel work or when a task branch has been merged.
argument-hint: <task-name> [--force] [--delete-branches] | --merged [--dry-run]
disable-model-invocation: true
allowed-tools: Bash(worktree cleanup *)
---

# Cleanup worktrees

## Remove a specific task

```bash
worktree cleanup $ARGUMENTS
```

Common usage:

```bash
# Remove worktrees and branches for a completed task
worktree cleanup <task-name> --force --delete-branches
```

## Remove all merged tasks

```bash
# Preview what would be removed
worktree cleanup --merged --dry-run

# Remove all merged tasks and their branches
worktree cleanup --merged --force --delete-branches
```

## Options

| Option | Description |
|---|---|
| `--merged` | Auto-detect tasks whose branches are merged into the default branch |
| `--delete-branches` | Delete local branches along with worktrees |
| `--dry-run` | Show targets without actually deleting |
| `--force` | Skip confirmation prompts and ignore uncommitted changes |

## Safety

- Warns about uncommitted changes unless `--force` is used
- Asks for confirmation unless `--force` is used
- Removes the empty `.worktrees/` directory when the last task is cleaned up
