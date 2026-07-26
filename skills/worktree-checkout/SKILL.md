---
name: worktree-checkout
description: Checkout a branch on all repositories, or create a worktree from a GitHub issue/PR URL.
argument-hint: [branch|URL]
disable-model-invocation: true
allowed-tools: Bash(worktree checkout *)
---

# Checkout a branch or create a worktree from a GitHub URL

Run the following command from the project root:

```bash
worktree checkout $ARGUMENTS
```

## What this does

### Branch mode

1. Detects all git repositories under the current project root
2. Checks out the specified branch on each repository
3. If no branch is specified, checks out each repo's default branch

### URL mode (GitHub issue or PR URL)

When the argument is a GitHub URL:

- **Issue URL** (`.../issues/<N>`): Creates a worktree under `<project>.worktrees/issue-<N>/` with a new branch `issue-<N>` based on the default branch.
- **PR URL** (`.../pull/<N>`): Fetches the PR head, creates a worktree under `<project>.worktrees/pr-<N>/`, and checks out the PR's original branch name as a local branch. In multi-repo projects, only the repository matching the URL gets a worktree.

`gh` CLI is optional: without it, issue verification is skipped and the PR's local branch is named `pr-<N>` instead of the original head ref.

## Examples

```bash
# Branch mode
worktree checkout develop
worktree checkout           # default branch

# URL mode
worktree checkout https://github.com/owner/repo/issues/42
worktree checkout https://github.com/owner/repo/pull/123
worktree checkout https://github.com/owner/repo/pull/123 --no-install
worktree checkout https://github.com/owner/repo/pull/123 --no-cd
```

## Options (URL mode)

| Option | Description |
|---|---|
| `--no-install` | Skip automatic dependency installation |
| `--no-cd` | Do not auto-cd into the new worktree (interactive shells with `worktree shell-init` only) |

> **Note (mise):** When a mise config applies to the new worktree, the dependency
> install runs through `mise exec --` (after `mise trust`) so mise-managed
> toolchains are on `PATH`. This trusts the config as checked out on the PR
> branch; use `WORKTREE_NO_MISE=1` or `--no-install` for untrusted PRs.

> **Note (subagents):** In URL mode, `checkout` auto-cds into the new worktree
> only in an interactive shell that has `eval "$(worktree shell-init)"` installed.
> From a subagent's `Bash` call there is no directory change, so `--no-cd` has no
> effect here. Branch mode never changes directory.

## Alias

`worktree co` is a shorthand for `worktree checkout`.
