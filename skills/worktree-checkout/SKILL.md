---
name: worktree-checkout
description: Checkout a branch on all repositories in the project. Use to switch all repos to a specific branch or back to the default branch.
argument-hint: [branch]
disable-model-invocation: true
allowed-tools: Bash(worktree checkout *)
---

# Checkout a branch on all repositories

Run the following command from the project root:

```bash
worktree checkout $ARGUMENTS
```

## What this does

1. Detects all git repositories under the current project root
2. Checks out the specified branch on each repository
3. If no branch is specified, checks out each repo's default branch

## Examples

```bash
# Checkout a specific branch
worktree checkout develop

# Checkout the default branch on all repos
worktree checkout
```

## Alias

`worktree co` is a shorthand for `worktree checkout`.
