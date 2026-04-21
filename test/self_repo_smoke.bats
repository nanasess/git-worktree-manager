#!/usr/bin/env bats
#
# Smoke tests for URL-mode checkout that exercise the gh-enabled path.
#
# These tests use PRs / issues on the current repository itself. In GitHub
# Actions, the default GITHUB_TOKEN has read access to the running
# repository, so `gh pr view` succeeds and the head_ref preservation path
# can be verified. No external PAT is required.
#
# The project layout used here is deliberately multi-repo to also cover
# the "PR URL matches only one sub-repo" behaviour.

load 'test_helper/common'

SELF_REPO_URL="https://github.com/nanasess/git-worktree-manager.git"
OTHER_REPO_URL="https://github.com/nanasess/setup-chromedriver.git"
SELF_PR_NUMBER=16
SELF_PR_HEAD_REF="issue-12"
SELF_ISSUE_NUMBER=12

setup_file() {
    TEST_WORK_DIR="$(mktemp -d)"
    PROJECT_DIR="${TEST_WORK_DIR}/smoke-project"
    WORKTREES_DIR="${TEST_WORK_DIR}/smoke-project.worktrees"
    mkdir -p "$PROJECT_DIR"

    # Self-repo sub-repo: gh can query it under the default GITHUB_TOKEN scope.
    git clone --depth 1 "$SELF_REPO_URL" "${PROJECT_DIR}/git-worktree-manager" --quiet
    # External sub-repo: must NOT receive a worktree when URL targets self-repo.
    git clone --depth 1 "$OTHER_REPO_URL" "${PROJECT_DIR}/setup-chromedriver" --quiet

    export TEST_WORK_DIR PROJECT_DIR WORKTREES_DIR
}

teardown_file() {
    cleanup_test_env
}

# Skip the block if the running environment cannot query this repo via gh.
# In CI the default GITHUB_TOKEN suffices; locally it requires `gh auth login`.
require_gh_for_self_repo() {
    if ! command -v gh >/dev/null 2>&1; then
        skip "gh CLI not installed"
    fi
    if ! gh pr view "$SELF_PR_NUMBER" --repo nanasess/git-worktree-manager \
           --json number >/dev/null 2>&1; then
        skip "gh cannot query self-repo PR (no auth or network)"
    fi
}

@test "checkout: self-repo PR URL preserves head_ref (multi-repo)" {
    require_gh_for_self_repo

    cd "$PROJECT_DIR"
    run "$WORKTREE_CMD" checkout \
        "https://github.com/nanasess/git-worktree-manager/pull/${SELF_PR_NUMBER}" \
        --no-install
    assert_success

    # Worktree is created only under the matching sub-repo.
    [ -d "${WORKTREES_DIR}/pr-${SELF_PR_NUMBER}/git-worktree-manager" ]
    [ ! -d "${WORKTREES_DIR}/pr-${SELF_PR_NUMBER}/setup-chromedriver" ]

    # head_ref preservation: branch name equals the PR's original head.
    local branch
    branch=$(git -C "${WORKTREES_DIR}/pr-${SELF_PR_NUMBER}/git-worktree-manager" \
                 branch --show-current)
    [ "$branch" = "$SELF_PR_HEAD_REF" ]
}

@test "cleanup: removes self-repo PR worktree" {
    require_gh_for_self_repo

    cd "$PROJECT_DIR"
    run "$WORKTREE_CMD" cleanup "pr-${SELF_PR_NUMBER}" --force --delete-branches
    assert_success
    [ ! -d "${WORKTREES_DIR}/pr-${SELF_PR_NUMBER}" ]
}

@test "checkout: self-repo issue URL creates issue-<N> task (multi-repo)" {
    require_gh_for_self_repo

    cd "$PROJECT_DIR"
    run "$WORKTREE_CMD" checkout \
        "https://github.com/nanasess/git-worktree-manager/issues/${SELF_ISSUE_NUMBER}" \
        --no-install
    assert_success

    # Issue URL delegates to cmd_create, which creates worktrees for all sub-repos.
    [ -d "${WORKTREES_DIR}/issue-${SELF_ISSUE_NUMBER}/git-worktree-manager" ]
    [ -d "${WORKTREES_DIR}/issue-${SELF_ISSUE_NUMBER}/setup-chromedriver" ]
    git -C "${PROJECT_DIR}/git-worktree-manager" \
        rev-parse --verify "issue-${SELF_ISSUE_NUMBER}"
    git -C "${PROJECT_DIR}/setup-chromedriver" \
        rev-parse --verify "issue-${SELF_ISSUE_NUMBER}"
}

@test "cleanup: removes self-repo issue task" {
    require_gh_for_self_repo

    cd "$PROJECT_DIR"
    run "$WORKTREE_CMD" cleanup "issue-${SELF_ISSUE_NUMBER}" \
        --force --delete-branches
    assert_success
    [ ! -d "${WORKTREES_DIR}/issue-${SELF_ISSUE_NUMBER}" ]
}
