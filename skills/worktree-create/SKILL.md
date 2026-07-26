---
name: worktree-create
description: Create git worktrees for a task across all repositories in the project. Use when starting parallel work, creating isolated workspaces for subagents, or branching all repos at once.
argument-hint: <task-name> [--branch-prefix <prefix>] [--no-install] [--no-cd]
disable-model-invocation: true
allowed-tools: Bash(worktree create *)
---

# Create worktrees for a task

Run the following command from the project root:

```bash
worktree create $ARGUMENTS
```

## What this does

1. Detects git repositories (single repo or multiple sub-repos)
2. Runs `git fetch origin` on each repository
3. Creates a worktree for each repository based on origin/HEAD (default branch)
4. Writes the worktree context (task name, working directory, project root) to CLAUDE.local.md, leaving the original CLAUDE.md untouched
5. Symlinks non-git items into the task directory (multi-repo only)
6. Copies `mise.toml` / `mise.local.toml` into each worktree (inherits mise version pinning even when gitignored)
7. Executes `.worktreerc` `post_create()` hook if present
8. Auto-installs dependencies based on lock files (unless `--no-install`). When a mise config applies to the worktree it is passed to `mise trust` and the install runs through `mise exec --`, so mise-managed toolchains resolve; `WORKTREE_NO_MISE=1` disables this

## Worktree layout

Worktrees are placed outside the project to avoid polluting code search:

### Multi-repo project

```
~/git-repos/
├── my-project/                  # Original project (you are here)
├── my-project.worktrees/        # Created by this command
│   └── <task-name>/
│       ├── CLAUDE.md            # Symlink to the original (unchanged)
│       ├── CLAUDE.local.md      # Worktree context (added)
│       ├── repo-a/  (branch: <task-name>)
│       └── repo-b/  (branch: <task-name>)
```

### Single-repo project

```
~/git-repos/
├── my-project/                  # Original project (you are here)
├── my-project.worktrees/
│   └── <task-name>/             # Worktree (branch: <task-name>)
│       ├── CLAUDE.md            # Unchanged (no diff against the source)
│       ├── CLAUDE.local.md      # Worktree context (added)
│       └── src/
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
| `--no-cd` | Do not auto-cd into the new worktree (interactive shells with `worktree shell-init` only) |

> **Note (subagents):** Auto-cd only happens in an interactive shell that has
> `eval "$(worktree shell-init)"` installed. From a subagent's `Bash` call there
> is no directory change (each `Bash` call has its own working directory), so
> `--no-cd` has no effect here. Use the task directory printed at the end and
> pass it to subagents via `--add-dir`.
