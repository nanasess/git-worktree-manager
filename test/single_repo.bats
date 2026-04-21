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

# mise config inheritance
@test "create: inherits untracked mise.toml and mise.local.toml" {
    cd "$SINGLE_REPO_DIR"
    printf '[tools]\nnode = "20"\n' > "${SINGLE_REPO_DIR}/mise.toml"
    printf '[tools]\nphp = "8.3"\n' > "${SINGLE_REPO_DIR}/mise.local.toml"

    run "$WORKTREE_CMD" create mise-task --no-install
    assert_success

    [ -f "${WORKTREES_DIR}/mise-task/mise.toml" ]
    [ -f "${WORKTREES_DIR}/mise-task/mise.local.toml" ]
    diff "${SINGLE_REPO_DIR}/mise.toml" "${WORKTREES_DIR}/mise-task/mise.toml"
    diff "${SINGLE_REPO_DIR}/mise.local.toml" "${WORKTREES_DIR}/mise-task/mise.local.toml"
}

@test "cleanup: removes mise-task" {
    cd "$SINGLE_REPO_DIR"
    run "$WORKTREE_CMD" cleanup mise-task --force --delete-branches
    assert_success

    [ ! -d "${WORKTREES_DIR}/mise-task" ]
    rm -f "${SINGLE_REPO_DIR}/mise.toml" "${SINGLE_REPO_DIR}/mise.local.toml"
}
