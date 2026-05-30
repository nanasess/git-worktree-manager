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
│   │   ├── CLAUDE.md               #   symlink to the original (unchanged)
│   │   └── CLAUDE.local.md         #   worktree context (never touches CLAUDE.md)
│   └── fix-auth/
│       └── ...
```

Worktrees are placed **outside** the project directory — no search noise, no IDE confusion.

Works with **single-repo** projects too:

```
├── my-app/                         # Single git repo
│   ├── src/
│   └── CLAUDE.md
├── my-app.worktrees/
│   └── feature-login/              # Worktree (branch: feature-login)
│       ├── src/
│       ├── CLAUDE.md               #   unchanged (no diff against the source)
│       └── CLAUDE.local.md         #   worktree context (added, gitignore recommended)
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
1. `git fetch origin` on each repo (also `git fetch upstream` if the remote exists)
2. Create worktree based on the default branch — **`upstream` is preferred** over `origin` when both are configured (fork workflows where `origin` is your fork and `upstream` is the canonical repo)
3. Write the worktree context to `CLAUDE.local.md` (the original `CLAUDE.md` is left untouched)
4. Symlink non-git items (multi-repo)
5. Copy `mise.toml` / `mise.local.toml` into each worktree (even when gitignored)
6. Run `.worktreerc` `post_create()` hook
7. Auto-install dependencies

| Option | Description |
|---|---|
| `--branch-prefix <prefix>` | Prefix for branch names (e.g., `nanasess/`) |
| `--no-install` | Skip dependency installation |

### `worktree list`

```bash
worktree list                       # or: worktree ls
worktree list --merged              # only tasks with at least one merged sub-repo
worktree list --names-only          # task names only, one per line (pipe-friendly)
worktree list --merged --names-only # combine: feed directly into `worktree cleanup`
```

Shows all tasks with branch names, modification status, and untracked files.

Each repository line may carry status labels:

| Label | Meaning |
|---|---|
| `[modified]` | The working tree or index has uncommitted changes |
| `[untracked]` | One or more files are not tracked by git |
| `[merged]` | The branch corresponds to a merged GitHub PR (detected via `gh pr list --state merged`, so squash/rebase merges are caught) |

The `[merged]` label requires the [`gh` CLI](https://cli.github.com/) to be installed and authenticated against the remote; it is silently skipped when `gh` is missing, the remote is not GitHub, or the API call fails.

| Option | Description |
|---|---|
| `--merged` | Filter to tasks where **at least one** sub-repo has a merged head branch (any-merged). Stricter than `cleanup --merged`, which requires every sub-repo to be merged. |
| `--names-only` | Print task names only — no headers, colors, or status labels. Combine with `--merged` to pipe into `worktree cleanup`. |

### `worktree checkout [branch|URL]`

```bash
worktree checkout           # default branch on all repos
worktree checkout develop   # specific branch on all repos
worktree co main            # alias

# Create a worktree from a GitHub issue or PR URL
worktree checkout https://github.com/owner/repo/issues/42
worktree checkout https://github.com/owner/repo/pull/123
```

When given a branch, switches each repo's HEAD to that branch.

When given a **GitHub URL**, creates a worktree scoped to that issue/PR:

| URL type | Task dir | Branch behavior |
|---|---|---|
| `issues/<N>` | `issue-<N>` | Creates a new branch `issue-<N>` from default |
| `pull/<N>` | `pr-<N>` | Fetches the PR head and checks it out under its **original branch name** |

For PR URLs in multi-repo projects, only the repository matching the URL gets a worktree (the PR is scoped to one repo).

The [`gh` CLI](https://cli.github.com/) is optional: with `gh`, PR URLs use the PR's original head branch name; without it, a generic `pr-<N>` branch name is used.

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

# Pipe task names in (one per line) — works with `worktree list --names-only`
worktree list --merged --names-only | worktree cleanup --force
```

Aliases: `worktree clean`, `worktree rm`

| Option | Description |
|---|---|
| `--merged` | Auto-detect merged tasks (all sub-repos must be merged) |
| `--delete-branches` | Also delete branches |
| `--dry-run` | Preview without deleting |
| `--force` | Skip confirmation |

When no task name is supplied and stdin is a pipe, `cleanup` reads one task name per line from stdin. Lines that don't correspond to a known task are skipped with a warning.

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

Each package system is evaluated **independently**, so polyglot projects
(e.g. EC-CUBE with `composer.json` + `package.json`) install every applicable
manager. Within the Node.js family (npm / pnpm / yarn), the managers are
mutually exclusive and resolved with priority `npm > pnpm > yarn`.

Skip with `--no-install`.

## mise Version Inheritance

If `mise.toml` or `mise.local.toml` exists in the source (project root for single-repo, each sub-repo root for multi-repo), `worktree create` copies it into the new worktree. This keeps mise-managed tool versions consistent even when the config is gitignored.

## Testing

Uses [bats-core](https://github.com/bats-core/bats-core) (git submodules).

```bash
git submodule update --init --recursive
./test/bats/bin/bats test/*.bats
```

## License

MIT
