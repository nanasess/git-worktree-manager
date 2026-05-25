#!/usr/bin/env bats

load 'test_helper/common'

setup_file() {
    setup_multi_repo
    export TEST_WORK_DIR MULTI_REPO_DIR WORKTREES_DIR
}

teardown_file() {
    cleanup_test_env
}

@test "create: worktrees are created for multiple repos" {
    cd "$MULTI_REPO_DIR"
    run "$WORKTREE_CMD" create test-task --no-install
    assert_success

    [ -d "${WORKTREES_DIR}/test-task" ]
    [ -d "${WORKTREES_DIR}/test-task/EcAuth" ]
    [ -d "${WORKTREES_DIR}/test-task/ecauth-website" ]
    [ -d "${WORKTREES_DIR}/test-task/ecauth-auth-js" ]
}

@test "create: branches are created in each repo" {
    git -C "${MULTI_REPO_DIR}/EcAuth" rev-parse --verify test-task
    git -C "${MULTI_REPO_DIR}/ecauth-website" rev-parse --verify test-task
    git -C "${MULTI_REPO_DIR}/ecauth-auth-js" rev-parse --verify test-task
}

@test "create: --branch-prefix creates prefixed branches" {
    cd "$MULTI_REPO_DIR"
    run "$WORKTREE_CMD" create test-task2 --branch-prefix ci/ --no-install
    assert_success

    git -C "${MULTI_REPO_DIR}/EcAuth" rev-parse --verify ci/test-task2
}

@test "create: duplicate task name fails" {
    cd "$MULTI_REPO_DIR"
    run "$WORKTREE_CMD" create test-task --no-install
    assert_failure
}

@test "list: shows test-task and test-task2" {
    cd "$MULTI_REPO_DIR"
    run "$WORKTREE_CMD" list
    assert_success
    assert_output --partial "test-task"
    assert_output --partial "test-task2"
}

@test "pull: exits 0" {
    cd "$MULTI_REPO_DIR"
    run "$WORKTREE_CMD" pull
    assert_success
}

@test "checkout main: exits 0" {
    cd "$MULTI_REPO_DIR"
    run "$WORKTREE_CMD" checkout main
    assert_success
}

@test "checkout default branch: exits 0" {
    cd "$MULTI_REPO_DIR"
    run "$WORKTREE_CMD" checkout
    assert_success
}

@test "cleanup test-task: removes worktree and branch" {
    cd "$MULTI_REPO_DIR"
    run "$WORKTREE_CMD" cleanup test-task --force --delete-branches
    assert_success

    [ ! -d "${WORKTREES_DIR}/test-task" ]
    run git -C "${MULTI_REPO_DIR}/EcAuth" rev-parse --verify test-task
    assert_failure
}

@test "cleanup test-task2: removes worktree and branch" {
    cd "$MULTI_REPO_DIR"
    run "$WORKTREE_CMD" cleanup test-task2 --force --delete-branches
    assert_success

    [ ! -d "${WORKTREES_DIR}/test-task2" ]
    run git -C "${MULTI_REPO_DIR}/EcAuth" rev-parse --verify ci/test-task2
    assert_failure
}

@test "list: shows no worktrees after cleanup" {
    cd "$MULTI_REPO_DIR"
    run "$WORKTREE_CMD" list
    assert_success
    assert_output --partial "No worktrees found"
}

# mise config inheritance per sub-repo.
# Use mise.local.toml (conventionally gitignored) to avoid clashing with any
# mise.toml that may already be tracked in upstream sub-repos.
@test "create: inherits untracked mise.local.toml per sub-repo" {
    cd "$MULTI_REPO_DIR"
    for repo in EcAuth ecauth-website ecauth-auth-js; do
        printf '[tools]\nphp = "8.3"\n' > "${MULTI_REPO_DIR}/${repo}/mise.local.toml"
    done

    run "$WORKTREE_CMD" create mise-task --no-install
    assert_success

    for repo in EcAuth ecauth-website ecauth-auth-js; do
        [ -f "${WORKTREES_DIR}/mise-task/${repo}/mise.local.toml" ]
        diff "${MULTI_REPO_DIR}/${repo}/mise.local.toml" "${WORKTREES_DIR}/mise-task/${repo}/mise.local.toml"
    done
}

@test "cleanup: removes mise-task" {
    cd "$MULTI_REPO_DIR"
    run "$WORKTREE_CMD" cleanup mise-task --force --delete-branches
    assert_success

    [ ! -d "${WORKTREES_DIR}/mise-task" ]
    for repo in EcAuth ecauth-website ecauth-auth-js; do
        rm -f "${MULTI_REPO_DIR}/${repo}/mise.local.toml"
    done
}

# URL-based checkout (PR scoped to one repo)
@test "checkout: PR URL creates worktree only for matching repo" {
    cd "$MULTI_REPO_DIR"
    run "$WORKTREE_CMD" checkout https://github.com/EcAuth/EcAuth/pull/1 --no-install
    assert_success

    [ -d "${WORKTREES_DIR}/pr-1" ]
    [ -d "${WORKTREES_DIR}/pr-1/EcAuth" ]
    [ -f "${WORKTREES_DIR}/pr-1/EcAuth/.git" ]
    # Non-matching repos should NOT have a worktree under pr-1/
    [ ! -d "${WORKTREES_DIR}/pr-1/ecauth-website" ]
    [ ! -d "${WORKTREES_DIR}/pr-1/ecauth-auth-js" ]
}

@test "checkout: PR URL with no matching repo fails" {
    cd "$MULTI_REPO_DIR"
    run "$WORKTREE_CMD" checkout https://github.com/some/unrelated/pull/1 --no-install
    assert_failure
}

@test "cleanup: removes PR worktree" {
    cd "$MULTI_REPO_DIR"
    run "$WORKTREE_CMD" cleanup pr-1 --force --delete-branches
    assert_success

    [ ! -d "${WORKTREES_DIR}/pr-1" ]
}

# Regression: a worktree sub-repo whose `.git` pointer is stale (gitdir
# references a path that no longer exists) must not cause `worktree list`
# to silently abort under `set -euo pipefail`. The bad repo should be
# labeled `[broken worktree]` and remaining repos must still be listed.
@test "list: broken sub-repo is reported and does not abort listing" {
    cd "$MULTI_REPO_DIR"
    run "$WORKTREE_CMD" create broken-task --no-install
    assert_success

    # Point EcAuth's .git at a non-existent gitdir to simulate a stale worktree.
    echo "gitdir: /nonexistent/path/that/does/not/exist" \
        > "${WORKTREES_DIR}/broken-task/EcAuth/.git"

    run "$WORKTREE_CMD" list
    assert_success
    assert_output --partial "broken-task"
    assert_output --partial "EcAuth"
    assert_output --partial "[broken worktree]"
    # Other repos in the same task must still be enumerated.
    assert_output --partial "ecauth-website"
    assert_output --partial "ecauth-auth-js"

    # Cleanup: restore the .git pointer so worktree cleanup can run.
    rm -rf "${WORKTREES_DIR}/broken-task"
    git -C "${MULTI_REPO_DIR}/EcAuth" worktree prune
    git -C "${MULTI_REPO_DIR}/ecauth-website" worktree remove --force "${WORKTREES_DIR}/broken-task/ecauth-website" 2>/dev/null || true
    git -C "${MULTI_REPO_DIR}/ecauth-auth-js" worktree remove --force "${WORKTREES_DIR}/broken-task/ecauth-auth-js" 2>/dev/null || true
    git -C "${MULTI_REPO_DIR}/ecauth-website" worktree prune
    git -C "${MULTI_REPO_DIR}/ecauth-auth-js" worktree prune
    git -C "${MULTI_REPO_DIR}/EcAuth" branch -D broken-task 2>/dev/null || true
    git -C "${MULTI_REPO_DIR}/ecauth-website" branch -D broken-task 2>/dev/null || true
    git -C "${MULTI_REPO_DIR}/ecauth-auth-js" branch -D broken-task 2>/dev/null || true
}

# Regression: a task containing a broken sub-repo must still be removable
# under `cleanup --force`. Without the fix the broken sub-repo causes
# `set -euo pipefail` to abort cleanup_task before reaching the other repos.
@test "cleanup --force: removes task with a broken sub-repo" {
    cd "$MULTI_REPO_DIR"
    run "$WORKTREE_CMD" create broken-cleanup --no-install
    assert_success

    # Stale gitdir pointer (the main repo path is fine; only the per-worktree
    # gitdir entry is missing) — mirrors `git worktree remove` being
    # impossible without falling back to direct removal.
    echo "gitdir: /nonexistent/per-worktree/gitdir" \
        > "${WORKTREES_DIR}/broken-cleanup/EcAuth/.git"

    run "$WORKTREE_CMD" cleanup broken-cleanup --force --delete-branches
    assert_success
    assert_output --partial "broken worktree"
    [ ! -d "${WORKTREES_DIR}/broken-cleanup" ]

    # Tidy: registries on the other repos still reference the removed paths.
    git -C "${MULTI_REPO_DIR}/EcAuth" worktree prune
    git -C "${MULTI_REPO_DIR}/EcAuth" branch -D broken-cleanup 2>/dev/null || true
}
