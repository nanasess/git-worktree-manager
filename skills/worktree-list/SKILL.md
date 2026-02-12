---
name: worktree-list
description: List all worktrees for the current project. Shows task names, branch names, and change status for each repository.
disable-model-invocation: true
allowed-tools: Bash(worktree list *)
---

# List worktrees

Run the following command from the project root:

```bash
worktree list
```

## Output

Shows each task and its repositories with:
- Branch name per repository
- Change indicators (uncommitted changes, untracked files)

Use this to check what worktrees exist before creating new ones or cleaning up.
