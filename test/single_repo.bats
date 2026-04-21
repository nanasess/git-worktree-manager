#!/usr/bin/env bats

load 'test_helper/common'

setup_file() {
    setup_single_repo
    export TEST_WORK_DIR SINGLE_REPO_DIR WORKTREES_DIR
}

teardown_file() {
    cleanup_test_env
}

@test "create: worktree is created for single repo" {
    cd "$SINGLE_REPO_DIR"
    run "$WORKTREE_CMD" create test-task --no-install
    assert_success

    [ -d "${WORKTREES_DIR}/test-task" ]
    [ -f "${WORKTREES_DIR}/test-task/.git" ]
    git -C "$SINGLE_REPO_DIR" rev-parse --verify test-task
}

@test "create: CLAUDE.md includes Worktree Context" {
    if [ ! -f "${SINGLE_REPO_DIR}/CLAUDE.md" ]; then
        skip "No CLAUDE.md"
    fi
    [ -f "${WORKTREES_DIR}/test-task/CLAUDE.md" ]
    grep -q "Worktree Context" "${WORKTREES_DIR}/test-task/CLAUDE.md"
}

@test "create: duplicate task name fails" {
    cd "$SINGLE_REPO_DIR"
    run "$WORKTREE_CMD" create test-task --no-install
    assert_failure
}

@test "list: shows test-task" {
    cd "$SINGLE_REPO_DIR"
    run "$WORKTREE_CMD" list
    assert_success
    assert_output --partial "test-task"
}

@test "pull: exits 0" {
    cd "$SINGLE_REPO_DIR"
    run "$WORKTREE_CMD" pull
    assert_success
}

@test "checkout main: exits 0" {
    cd "$SINGLE_REPO_DIR"
    run "$WORKTREE_CMD" checkout main
    assert_success
}

@test "checkout default branch: exits 0" {
    cd "$SINGLE_REPO_DIR"
    run "$WORKTREE_CMD" checkout
    assert_success
}

@test "cleanup: removes worktree and branch" {
    cd "$SINGLE_REPO_DIR"
    run "$WORKTREE_CMD" cleanup test-task --force --delete-branches
    assert_success

    [ ! -d "${WORKTREES_DIR}/test-task" ]
    run git -C "$SINGLE_REPO_DIR" rev-parse --verify test-task
    assert_failure
}

@test "list: shows no worktrees after cleanup" {
    cd "$SINGLE_REPO_DIR"
    run "$WORKTREE_CMD" list
    assert_success
    assert_output --partial "No worktrees found"
}

# Slash in task name
@test "create: works with slash in task name" {
    cd "$SINGLE_REPO_DIR"
    run "$WORKTREE_CMD" create feature/slash-test --no-install
    assert_success

    [ -d "${WORKTREES_DIR}/feature/slash-test" ]
    [ -f "${WORKTREES_DIR}/feature/slash-test/.git" ]
}

@test "list: correctly displays slash task name" {
    cd "$SINGLE_REPO_DIR"
    run "$WORKTREE_CMD" list
    assert_success
    assert_output --partial "feature/slash-test"
}

@test "cleanup: removes slash task name" {
    cd "$SINGLE_REPO_DIR"
    run "$WORKTREE_CMD" cleanup feature/slash-test --force --delete-branches
    assert_success

    [ ! -d "${WORKTREES_DIR}/feature/slash-test" ]
}

# URL-based checkout
@test "checkout: invalid URL fails cleanly" {
    cd "$SINGLE_REPO_DIR"
    run "$WORKTREE_CMD" checkout https://gitlab.com/foo/bar/issues/1
    assert_failure
    assert_output --partial "Invalid GitHub URL"
}

@test "checkout: issue URL creates issue-<N> worktree" {
    cd "$SINGLE_REPO_DIR"
    run "$WORKTREE_CMD" checkout https://github.com/nanasess/setup-chromedriver/issues/2 --no-install
    assert_success

    [ -d "${WORKTREES_DIR}/issue-2" ]
    [ -f "${WORKTREES_DIR}/issue-2/.git" ]
    git -C "$SINGLE_REPO_DIR" rev-parse --verify issue-2
}

@test "cleanup: removes issue-<N> worktree" {
    cd "$SINGLE_REPO_DIR"
    run "$WORKTREE_CMD" cleanup issue-2 --force --delete-branches
    assert_success

    [ ! -d "${WORKTREES_DIR}/issue-2" ]
}

@test "checkout: PR URL creates pr-<N> worktree on PR branch" {
    cd "$SINGLE_REPO_DIR"
    run "$WORKTREE_CMD" checkout https://github.com/nanasess/setup-chromedriver/pull/443 --no-install
    assert_success

    [ -d "${WORKTREES_DIR}/pr-443" ]
    [ -f "${WORKTREES_DIR}/pr-443/.git" ]
    # Worktree must be on a named branch (not detached HEAD).
    # Branch name depends on gh availability:
    #   - With gh auth: the PR's original head ref (e.g., dependabot/...)
    #   - Without gh (or gh unable to query): fallback "pr-443"
    local worktree_branch
    worktree_branch=$(git -C "${WORKTREES_DIR}/pr-443" branch --show-current)
    [ -n "$worktree_branch" ]
}

@test "checkout: PR URL with non-matching repo fails" {
    cd "$SINGLE_REPO_DIR"
    run "$WORKTREE_CMD" checkout https://github.com/some/other-repo/pull/1 --no-install
    assert_failure
}

@test "cleanup: removes pr-<N> worktree" {
    cd "$SINGLE_REPO_DIR"
    run "$WORKTREE_CMD" cleanup pr-443 --force --delete-branches
    assert_success

    [ ! -d "${WORKTREES_DIR}/pr-443" ]
}
