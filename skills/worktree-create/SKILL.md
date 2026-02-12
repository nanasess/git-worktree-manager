---
name: worktree-create
description: Create git worktrees for a task across all repositories in the project. Use when starting parallel work, creating isolated workspaces for subagents, or branching all repos at once.
argument-hint: <task-name> [--branch-prefix <prefix>] [--no-install]
disable-model-invocation: true
allowed-tools: Bash(worktree create *)
---

# Create worktrees for a task

Run the following command from the project root:

```bash
worktree create $ARGUMENTS
```

## What this does

1. Detects all git repositories under the current project root
2. Runs `git fetch origin` on each repository
3. Creates a worktree for each repository based on origin/HEAD (default branch)
4. Symlinks non-git items (CLAUDE.md, etc.) into the task directory
5. Executes `.worktreerc` `post_create()` hook if present
6. Auto-installs dependencies based on lock files (unless `--no-install`)

## Worktree layout

Worktrees are placed outside the project to avoid polluting code search:

```
~/git-repos/
├── my-project/                  # Original project (you are here)
├── my-project.worktrees/        # Created by this command
│   └── <task-name>/
│       ├── CLAUDE.md → symlink
│       ├── repo-a/  (branch: <task-name>)
│       └── repo-b/  (branch: <task-name>)
```

## After creation

The task directory path is printed at the end. Use it to:
- Point subagents to the isolated workspace with `--add-dir`
- Run builds or tests in the worktree without affecting the main checkout
- Work on multiple tasks in parallel without branch conflicts

## Options

| Option | Description |
|---|---|
| `--branch-prefix <prefix>` | Add a prefix to branch names (e.g. `nanasess/`) |
| `--no-install` | Skip automatic dependency installation |
