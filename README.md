# git-worktree-manager

Bulk worktree management tool for projects with multiple git repositories.

## Motivation

- Placing worktrees inside repositories pollutes Claude Code's code search with noise
- Managing worktree lifecycles across multiple repositories and tasks is cumbersome
- Dependency installation (npm, pnpm, yarn, composer, dotnet) must be done manually each time

## Installation

```bash
git clone https://github.com/nanasess/git-worktree-manager.git ~/git-repos/git-worktree-manager
ln -sf ~/git-repos/git-worktree-manager/worktree ~/.local/bin/worktree
```

## Usage

All commands can be run from the project root or from inside a `.worktrees/` directory.

### Create worktrees

```bash
cd ~/git-repos/my-project
worktree create feature-login
```

For every git repository under the project root:
1. Runs `git fetch origin` to update
2. Creates a worktree based on origin/HEAD (default branch)
3. Generates a CLAUDE.md with worktree context (task name, working directory, project root)
4. Symlinks non-git items into the task directory
5. Executes `post_create()` hook from `.worktreerc` if present
6. Auto-installs dependencies based on lock files

#### Options

| Option | Description |
|---|---|
| `--branch-prefix <prefix>` | Add a prefix to branch names |
| `--no-install` | Skip automatic dependency installation |

### List worktrees

```bash
worktree list
```

### Checkout branches

```bash
# Checkout default branch on all repositories
worktree checkout

# Checkout a specific branch
worktree checkout develop
```

Alias: `worktree co`

### Pull repositories

```bash
worktree pull
```

Runs `git pull --ff-only` on each repository and shows a summary of results.

### Cleanup worktrees

```bash
# Remove a specific task
worktree cleanup feature-login --force --delete-branches

# Auto-detect and remove merged tasks
worktree cleanup --merged --force --delete-branches

# Dry run (show targets without deleting)
worktree cleanup --merged --dry-run
```

#### Options

| Option | Description |
|---|---|
| `--merged` | Auto-detect tasks merged into the default branch |
| `--delete-branches` | Delete branches along with worktrees |
| `--dry-run` | Show targets without actually deleting |
| `--force` | Skip confirmation prompts |

### Install Claude Code skills

```bash
# Install to current project (.claude/skills/)
worktree install --skills

# Install globally (~/.claude/skills/)
worktree install --skills --global
```

Installs slash command skills for Claude Code:
- `/worktree-create <task-name>` - Create worktrees
- `/worktree-list` - List worktrees
- `/worktree-cleanup <task-name>` - Cleanup worktrees

## Worktree Layout

Worktrees are placed outside the project directory to avoid search noise:

```
~/git-repos/
├── my-project/                            # Original project
│   ├── CLAUDE.md
│   ├── frontend/
│   └── backend/
├── my-project.worktrees/                  # Worktrees (outside repo)
│   └── task-A/
│       ├── CLAUDE.md → symlink to original CLAUDE.md
│       ├── frontend/   (git worktree, branch: task-A)
│       └── backend/    (git worktree, branch: task-A)
```

## .worktreerc Hook

Place a `.worktreerc` file in the project root. The `post_create()` function runs inside the task directory after worktree creation.

```bash
# .worktreerc example
post_create() {
    ln -sf shared-docs/claude-repository-guide.md CLAUDE.md
    ln -sf shared-docs/setup.sh setup.sh
}
```

Environment variables available in hooks:

| Variable | Description |
|---|---|
| `WORKTREE_TASK_NAME` | Task name |
| `WORKTREE_TASK_DIR` | Full path to the task directory |
| `WORKTREE_PROJECT_ROOT` | Full path to the original project root |

## Automatic Dependency Installation

| Detected File | Command |
|---|---|
| `package-lock.json` | `npm install` |
| `pnpm-lock.yaml` | `pnpm install` |
| `yarn.lock` | `yarn install` |
| `composer.lock` | `composer install` |
| `*.sln` or `*.csproj` | `dotnet restore` |

Use `--no-install` to skip.

## License

MIT
