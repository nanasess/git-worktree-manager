#!/bin/bash
#
# common.bash - bats テスト用共通ヘルパー
#

WORKTREE_CMD="$(cd "$(dirname "${BATS_TEST_DIRNAME}")" && pwd)/worktree"

load "${BATS_TEST_DIRNAME}/test_helper/bats-support/load"
load "${BATS_TEST_DIRNAME}/test_helper/bats-assert/load"

# 単一リポジトリのセットアップ
setup_single_repo() {
    TEST_WORK_DIR="$(mktemp -d)"
    SINGLE_REPO_DIR="${TEST_WORK_DIR}/git-worktree-manager"
    WORKTREES_DIR="${TEST_WORK_DIR}/git-worktree-manager.worktrees"
    git clone --no-hardlinks "${GITHUB_WORKSPACE:-$(cd "$(dirname "${BATS_TEST_DIRNAME}")" && pwd)}" "$SINGLE_REPO_DIR" --quiet
    git -C "$SINGLE_REPO_DIR" remote set-head origin --auto 2>/dev/null || \
        git -C "$SINGLE_REPO_DIR" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main 2>/dev/null || true
}

# 複数リポジトリのセットアップ
setup_multi_repo() {
    TEST_WORK_DIR="$(mktemp -d)"
    MULTI_REPO_DIR="${TEST_WORK_DIR}/test-multi-project"
    WORKTREES_DIR="${TEST_WORK_DIR}/test-multi-project.worktrees"
    mkdir -p "$MULTI_REPO_DIR"

    local repos=(
        "https://github.com/EcAuth/EcAuth.git"
        "https://github.com/EcAuth/ecauth-website.git"
        "https://github.com/EcAuth/ecauth-auth-js.git"
    )
    for repo_url in "${repos[@]}"; do
        local repo_name
        repo_name="$(basename "$repo_url" .git)"
        git clone --depth 1 "$repo_url" "${MULTI_REPO_DIR}/${repo_name}" --quiet
    done
}

# テスト環境のクリーンアップ
cleanup_test_env() {
    if [ -n "${TEST_WORK_DIR:-}" ] && [ -d "$TEST_WORK_DIR" ]; then
        rm -rf "$TEST_WORK_DIR"
    fi
}
