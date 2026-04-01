#!/usr/bin/env bats

load 'test_helper/common'

setup_file() {
    setup_multi_repo
    export TEST_WORK_DIR MULTI_REPO_DIR WORKTREES_DIR
}

teardown_file() {
    cleanup_test_env
}

@test "create: 複数リポジトリで worktree が作成される" {
    cd "$MULTI_REPO_DIR"
    run "$WORKTREE_CMD" create test-task --no-install
    assert_success

    [ -d "${WORKTREES_DIR}/test-task" ]
    [ -d "${WORKTREES_DIR}/test-task/EcAuth" ]
    [ -d "${WORKTREES_DIR}/test-task/ecauth-website" ]
    [ -d "${WORKTREES_DIR}/test-task/ecauth-auth-js" ]
}

@test "create: 各リポジトリにブランチが作成される" {
    git -C "${MULTI_REPO_DIR}/EcAuth" rev-parse --verify test-task
    git -C "${MULTI_REPO_DIR}/ecauth-website" rev-parse --verify test-task
    git -C "${MULTI_REPO_DIR}/ecauth-auth-js" rev-parse --verify test-task
}

@test "create: --branch-prefix でプレフィックス付きブランチが作成される" {
    cd "$MULTI_REPO_DIR"
    run "$WORKTREE_CMD" create test-task2 --branch-prefix ci/ --no-install
    assert_success

    git -C "${MULTI_REPO_DIR}/EcAuth" rev-parse --verify ci/test-task2
}

@test "create: 同名タスクの二重作成でエラー" {
    cd "$MULTI_REPO_DIR"
    run "$WORKTREE_CMD" create test-task --no-install
    assert_failure
}

@test "list: test-task と test-task2 が表示される" {
    cd "$MULTI_REPO_DIR"
    run "$WORKTREE_CMD" list
    assert_success
    assert_output --partial "test-task"
    assert_output --partial "test-task2"
}

@test "pull: exit 0" {
    cd "$MULTI_REPO_DIR"
    run "$WORKTREE_CMD" pull
    assert_success
}

@test "checkout main: exit 0" {
    cd "$MULTI_REPO_DIR"
    run "$WORKTREE_CMD" checkout main
    assert_success
}

@test "checkout デフォルトブランチ: exit 0" {
    cd "$MULTI_REPO_DIR"
    run "$WORKTREE_CMD" checkout
    assert_success
}

@test "cleanup test-task: worktree とブランチが削除される" {
    cd "$MULTI_REPO_DIR"
    run "$WORKTREE_CMD" cleanup test-task --force --delete-branches
    assert_success

    [ ! -d "${WORKTREES_DIR}/test-task" ]
    run git -C "${MULTI_REPO_DIR}/EcAuth" rev-parse --verify test-task
    assert_failure
}

@test "cleanup test-task2: worktree とブランチが削除される" {
    cd "$MULTI_REPO_DIR"
    run "$WORKTREE_CMD" cleanup test-task2 --force --delete-branches
    assert_success

    [ ! -d "${WORKTREES_DIR}/test-task2" ]
    run git -C "${MULTI_REPO_DIR}/EcAuth" rev-parse --verify ci/test-task2
    assert_failure
}

@test "list: cleanup 後に worktree はありません" {
    cd "$MULTI_REPO_DIR"
    run "$WORKTREE_CMD" list
    assert_success
    assert_output --partial "worktree はありません"
}
