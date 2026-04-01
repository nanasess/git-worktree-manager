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
