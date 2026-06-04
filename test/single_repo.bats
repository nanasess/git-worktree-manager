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

@test "create: CLAUDE.local.md includes Worktree Context" {
    [ -f "${WORKTREES_DIR}/test-task/CLAUDE.local.md" ]
    grep -q "Worktree Context" "${WORKTREES_DIR}/test-task/CLAUDE.local.md"
}

@test "create: original CLAUDE.md is not modified with worktree context" {
    # The worktree context goes to CLAUDE.local.md; a shipped CLAUDE.md must
    # stay free of the injected block (no diff against the source).
    if [ ! -f "${SINGLE_REPO_DIR}/CLAUDE.md" ]; then
        skip "No CLAUDE.md"
    fi
    run grep -q "Worktree Context" "${WORKTREES_DIR}/test-task/CLAUDE.md"
    assert_failure
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

@test "list --names-only: prints task names only, one per line" {
    cd "$SINGLE_REPO_DIR"
    run "$WORKTREE_CMD" list --names-only
    assert_success
    # No header, no dashes, no log_info — just the task name verbatim.
    [ "$output" = "feature/slash-test" ]
}

# switch: resolution prints the worktree path on stdout (the shell function
# installed by `shell-init` is what turns that into a real `cd`).
@test "switch: exact name resolves to worktree path" {
    cd "$SINGLE_REPO_DIR"
    run "$WORKTREE_CMD" switch feature/slash-test
    assert_success
    assert_output "${WORKTREES_DIR}/feature/slash-test"
}

@test "switch: unique substring resolves to worktree path" {
    cd "$SINGLE_REPO_DIR"
    run "$WORKTREE_CMD" switch slash
    assert_success
    assert_output "${WORKTREES_DIR}/feature/slash-test"
}

@test "switch: unknown name fails and lists available worktrees" {
    cd "$SINGLE_REPO_DIR"
    run "$WORKTREE_CMD" switch no-such-worktree
    assert_failure
    assert_output --partial "No worktree matches: 'no-such-worktree'"
    assert_output --partial "feature/slash-test"
}

@test "switch -: without shell integration fails with a hint" {
    cd "$SINGLE_REPO_DIR"
    run "$WORKTREE_CMD" switch -
    assert_failure
    assert_output --partial "requires shell integration"
}

@test "shell-init: prints a worktree shell function" {
    run "$WORKTREE_CMD" shell-init
    assert_success
    assert_output --partial "worktree()"
    assert_output --partial "command worktree"
    # The wrapper also intercepts create/checkout for auto-cd.
    assert_output --partial "create|checkout|co"
}

# Auto-cd: create records the destination worktree in _WORKTREE_CD_FILE, which
# the shell function reads to perform the cd. The binary itself never cd's.
@test "create: records cd target when _WORKTREE_CD_FILE is set" {
    cd "$SINGLE_REPO_DIR"
    local cdfile
    cdfile="$(mktemp)"
    run env _WORKTREE_CD_FILE="$cdfile" "$WORKTREE_CMD" create cd-task --no-install
    assert_success
    [ "$(cat "$cdfile")" = "${WORKTREES_DIR}/cd-task" ]
    rm -f "$cdfile"
    "$WORKTREE_CMD" cleanup cd-task --force --delete-branches
}

@test "create --no-cd: does not record cd target" {
    cd "$SINGLE_REPO_DIR"
    local cdfile
    cdfile="$(mktemp)"
    run env _WORKTREE_CD_FILE="$cdfile" "$WORKTREE_CMD" create nocd-task --no-install --no-cd
    assert_success
    [ ! -s "$cdfile" ]
    rm -f "$cdfile"
    "$WORKTREE_CMD" cleanup nocd-task --force --delete-branches
}

@test "cleanup: accepts task names piped via stdin" {
    cd "$SINGLE_REPO_DIR"
    # Use --dry-run so the slash-task is still around for the next test.
    run bash -c "printf 'feature/slash-test\n' | '$WORKTREE_CMD' cleanup --dry-run --force"
    assert_success
    assert_output --partial "Tasks to clean (1): feature/slash-test"
}

@test "cleanup: stdin with unknown task is skipped with warning" {
    cd "$SINGLE_REPO_DIR"
    run bash -c "printf 'no-such-task\n' | '$WORKTREE_CMD' cleanup --dry-run --force"
    assert_success
    assert_output --partial "Task not found, skipping: no-such-task"
    assert_output --partial "No tasks read from stdin"
}

# Security: path traversal via stdin / argument must be rejected before
# the task_dir existence check ever runs. Without validation, '.' would
# resolve to worktrees_base itself and '..' to its parent — both would
# eventually reach `rm -rf "$task_dir"` in cleanup_task.
@test "cleanup: stdin '.' is rejected as path traversal" {
    cd "$SINGLE_REPO_DIR"
    run bash -c "printf '.\n' | '$WORKTREE_CMD' cleanup --dry-run --force"
    assert_success
    assert_output --partial "Invalid task name (path traversal not allowed), skipping: ."
    refute_output --partial "Tasks to clean (1)"
}

@test "cleanup: stdin '..' is rejected as path traversal" {
    cd "$SINGLE_REPO_DIR"
    run bash -c "printf '..\n' | '$WORKTREE_CMD' cleanup --dry-run --force"
    assert_success
    assert_output --partial "Invalid task name (path traversal not allowed), skipping: .."
    refute_output --partial "Tasks to clean (1)"
}

@test "cleanup: stdin absolute path is rejected as path traversal" {
    cd "$SINGLE_REPO_DIR"
    run bash -c "printf '/tmp\n' | '$WORKTREE_CMD' cleanup --dry-run --force"
    assert_success
    assert_output --partial "Invalid task name (path traversal not allowed), skipping: /tmp"
    refute_output --partial "Tasks to clean (1)"
}

@test "cleanup: argument '..' is rejected with non-zero exit" {
    cd "$SINGLE_REPO_DIR"
    run "$WORKTREE_CMD" cleanup .. --dry-run --force
    assert_failure
    assert_output --partial "Invalid task name (path traversal not allowed): .."
}

@test "cleanup: argument '.' is rejected with non-zero exit" {
    cd "$SINGLE_REPO_DIR"
    run "$WORKTREE_CMD" cleanup . --dry-run --force
    assert_failure
    assert_output --partial "Invalid task name (path traversal not allowed): ."
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

# URL-based checkout
@test "checkout: invalid URL fails cleanly" {
    cd "$SINGLE_REPO_DIR"
    run "$WORKTREE_CMD" checkout https://gitlab.com/foo/bar/issues/1
    assert_failure
    assert_output --partial "Invalid GitHub URL"
}

@test "checkout: --branch-prefix without value fails cleanly" {
    cd "$SINGLE_REPO_DIR"
    run "$WORKTREE_CMD" checkout https://github.com/nanasess/setup-chromedriver/issues/2 --branch-prefix
    assert_failure
    assert_output --partial "--branch-prefix requires a value"
}

@test "create: --branch-prefix without value fails cleanly" {
    cd "$SINGLE_REPO_DIR"
    run "$WORKTREE_CMD" create some-task --branch-prefix
    assert_failure
    assert_output --partial "--branch-prefix requires a value"
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

# Regression: stale local branch with PR head ref name must not be reused
@test "checkout: unrelated local branch with same name falls back to pr-<N>" {
    cd "$SINGLE_REPO_DIR"
    # Pre-create a local branch named after the PR's head ref, pointing at
    # an unrelated commit (master tip, which is NOT the PR head).
    local pr_head_name="dependabot/npm_and_yarn/handlebars-4.7.9"
    git branch "$pr_head_name" master

    run "$WORKTREE_CMD" checkout https://github.com/nanasess/setup-chromedriver/pull/443 --no-install
    assert_success

    # Must have used the fallback name, not reused the stale branch
    local worktree_branch
    worktree_branch=$(git -C "${WORKTREES_DIR}/pr-443" branch --show-current)
    [ "$worktree_branch" = "pr-443" ]

    # Worktree must point at the PR head, not the stale local branch
    local worktree_sha stale_sha
    worktree_sha=$(git -C "${WORKTREES_DIR}/pr-443" rev-parse HEAD)
    stale_sha=$(git -C "$SINGLE_REPO_DIR" rev-parse master)
    [ "$worktree_sha" != "$stale_sha" ]
}

@test "cleanup: removes fallback pr-<N> worktree" {
    cd "$SINGLE_REPO_DIR"
    run "$WORKTREE_CMD" cleanup pr-443 --force --delete-branches
    assert_success
    [ ! -d "${WORKTREES_DIR}/pr-443" ]
    # Clean up the stale branch that we created for the regression test
    git -C "$SINGLE_REPO_DIR" branch -D "dependabot/npm_and_yarn/handlebars-4.7.9" 2>/dev/null || true
}

# Fork workflow: origin points at a fork, upstream points at the canonical repo.
# The URL targets the canonical repo, so the match must come from 'upstream'
# and the subsequent PR fetch must also use 'upstream'.
@test "checkout: PR URL matches a non-origin remote (upstream)" {
    cd "$SINGLE_REPO_DIR"
    git -C "$SINGLE_REPO_DIR" remote set-url origin "https://github.com/fork-owner/setup-chromedriver.git"
    git -C "$SINGLE_REPO_DIR" remote add upstream "https://github.com/nanasess/setup-chromedriver.git"

    run "$WORKTREE_CMD" checkout https://github.com/nanasess/setup-chromedriver/pull/443 --no-install
    assert_success
    assert_output --partial "remote: upstream"

    [ -d "${WORKTREES_DIR}/pr-443" ]
    [ -f "${WORKTREES_DIR}/pr-443/.git" ]
}

@test "cleanup: removes upstream-matched PR worktree and restores remotes" {
    cd "$SINGLE_REPO_DIR"
    run "$WORKTREE_CMD" cleanup pr-443 --force --delete-branches
    assert_success
    # Restore remote configuration for subsequent tests (if any)
    git -C "$SINGLE_REPO_DIR" remote remove upstream 2>/dev/null || true
    git -C "$SINGLE_REPO_DIR" remote set-url origin "https://github.com/nanasess/setup-chromedriver.git"
}

# When an 'upstream' remote exists, 'worktree create' must base the new
# worktree on upstream's default branch (fork workflow where origin diverges).
@test "create: bases worktree on upstream when upstream remote exists" {
    cd "$SINGLE_REPO_DIR"
    # Simulate fork workflow by aliasing the same canonical URL as upstream.
    # Any valid fetchable URL works; using the same URL keeps the test offline-friendly
    # relative to other tests that already clone it.
    git -C "$SINGLE_REPO_DIR" remote add upstream "https://github.com/nanasess/setup-chromedriver.git"

    run "$WORKTREE_CMD" create upstream-base-task --no-install
    assert_success
    assert_output --partial "git fetch upstream"
    assert_output --partial "Base branch: upstream/"

    [ -d "${WORKTREES_DIR}/upstream-base-task" ]
    git -C "$SINGLE_REPO_DIR" rev-parse --verify upstream-base-task

    # The new branch must point at upstream's tip, not origin's.
    # Resolve upstream/HEAD dynamically so this assertion does not depend on
    # the upstream repo's default branch name (e.g. EC-CUBE/ec-cube uses 4.4).
    local task_sha upstream_head_ref upstream_sha
    task_sha=$(git -C "$SINGLE_REPO_DIR" rev-parse upstream-base-task)
    upstream_head_ref=$(git -C "$SINGLE_REPO_DIR" symbolic-ref --short refs/remotes/upstream/HEAD)
    upstream_sha=$(git -C "$SINGLE_REPO_DIR" rev-parse "$upstream_head_ref")
    [ "$task_sha" = "$upstream_sha" ]
}

@test "cleanup: removes upstream-based worktree and restores remotes" {
    cd "$SINGLE_REPO_DIR"
    run "$WORKTREE_CMD" cleanup upstream-base-task --force --delete-branches
    assert_success
    git -C "$SINGLE_REPO_DIR" remote remove upstream 2>/dev/null || true
}
