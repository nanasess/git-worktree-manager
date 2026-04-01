---
name: worktree-pull
description: Pull all repositories in the project. Runs git pull --ff-only on each repository and shows a summary.
disable-model-invocation: true
allowed-tools: Bash(worktree pull *)
---

# Pull all repositories

Run the following command from the project root:

```bash
worktree pull
```

## What this does

1. Detects all git repositories under the current project root
2. Runs `git pull --ff-only` on each repository
3. Shows a summary of results (up to date, updated, or failed)

## Notes

- Uses `--ff-only` to avoid merge commits. If a fast-forward is not possible, the pull will fail for that repository.
- Can be run from inside a `.worktrees/` directory — it will pull the original project's repositories.
