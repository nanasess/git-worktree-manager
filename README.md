# git-worktree-manager

> Manage git worktrees across single or multiple repositories with a single command.
> Pure Bash — no dependencies beyond `git` and `bash`.

[![CI](https://github.com/nanasess/git-worktree-manager/actions/workflows/ci.yml/badge.svg)](https://github.com/nanasess/git-worktree-manager/actions/workflows/ci.yml)

## Why?

Git worktrees are great for parallel development — but managing them is painful:

- **Search noise** — worktrees inside repos pollute code search (especially with AI coding tools)
- **Multi-repo overhead** — creating/cleaning worktrees across 3+ repos is tedious
- **Forgotten setup** — dependency installation, hooks, and config must be repeated each time

`worktree` solves this with one command: create isolated workspaces, run hooks, install deps, and clean up — across all repos at once.

## Quick Start

```bash
# Install
git clone https://github.com/nanasess/git-worktree-manager.git ~/git-repos/git-worktree-manager
ln -sf ~/git-repos/git-worktree-manager/worktree ~/.local/bin/worktree

# Create worktrees for a task
cd ~/git-repos/my-project
worktree create feature-login

# List, pull, checkout, cleanup
worktree list
worktree pull
worktree checkout main
worktree cleanup feature-login --force --delete-branches
```

## How It Works

```
~/git-repos/
├── my-project/                     # Your project (single or multi-repo)
│   ├── frontend/                   #   git repo
│   ├── backend/                    #   git repo
│   └── CLAUDE.md
│
├── my-project.worktrees/           # Worktrees live OUTSIDE the project
│   ├── feature-login/
│   │   ├── frontend/               #   branch: feature-login
│   │   ├── backend/                #   branch: feature-login
│   │   └── CLAUDE.md               #   generated with worktree context
│   └── fix-auth/
│       └── ...
```

Worktrees are placed **outside** the project directory — no search noise, no IDE confusion.

Works with **single-repo** projects too:

```
├── my-app/                         # Single git repo
├── my-app.worktrees/
│   └── feature-login/              # Worktree (branch: feature-login)
│       ├── src/
│       └── CLAUDE.md
```

## Commands

All commands work from the project root or from inside a `.worktrees/` directory.

### `worktree create <task-name>`

Creates a worktree (and branch) for each repository.

```bash
worktree create feature-login
worktree create fix-bug --branch-prefix nanasess/
worktree create quick-test --no-install
```

What happens:
1. `git fetch origin` on each repo
2. Create worktree based on the default branch
3. Generate `CLAUDE.md` with worktree context
4. Symlink non-git items (multi-repo)
5. Run `.worktreerc` `post_create()` hook
6. Auto-install dependencies

| Option | Description |
|---|---|
| `--branch-prefix <prefix>` | Prefix for branch names (e.g., `nanasess/`) |
| `--no-install` | Skip dependency installation |

### `worktree list`

```bash
worktree list    # or: worktree ls
```

Shows all tasks with branch names, modification status, and untracked files.

### `worktree checkout [branch]`

```bash
worktree checkout           # default branch
worktree checkout develop   # specific branch
worktree co main            # alias
```

### `worktree pull`

```bash
worktree pull
```

Runs `git pull --ff-only` on each repo with a summary of results.

### `worktree cleanup [task-name]`

```bash
worktree cleanup feature-login --force --delete-branches
worktree cleanup --merged --force --delete-branches
worktree cleanup --merged --dry-run
```

| Option | Description |
|---|---|
| `--merged` | Auto-detect merged tasks |
| `--delete-branches` | Also delete branches |
| `--dry-run` | Preview without deleting |
| `--force` | Skip confirmation |

### `worktree install --skills`

```bash
worktree install --skills            # project-local
worktree install --skills --global   # all projects
```

Installs Claude Code slash commands: `/worktree-create`, `/worktree-list`, `/worktree-cleanup`, `/worktree-checkout`, `/worktree-pull`.

## `.worktreerc` Hook

Place in the project root. `post_create()` runs in the task directory after creation.

```bash
post_create() {
    ln -sf shared-docs/claude-repository-guide.md CLAUDE.md
    ln -sf shared-docs/setup.sh setup.sh
}
```

| Variable | Description |
|---|---|
| `WORKTREE_TASK_NAME` | Task name |
| `WORKTREE_TASK_DIR` | Task directory path |
| `WORKTREE_PROJECT_ROOT` | Original project root |

## Auto Dependency Installation

Detected automatically during `worktree create`:

| Lock File | Command |
|---|---|
| `package-lock.json` | `npm install` |
| `pnpm-lock.yaml` | `pnpm install` |
| `yarn.lock` | `yarn install` |
| `composer.lock` | `composer install` |
| `*.sln` / `*.csproj` | `dotnet restore` |

Skip with `--no-install`.

## Testing

Uses [bats-core](https://github.com/bats-core/bats-core) (git submodules).

```bash
git submodule update --init --recursive
./test/bats/bin/bats test/*.bats
```

## License

MIT
