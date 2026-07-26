#!/usr/bin/env bats
#
# deps.bats - Unit tests for detect_deps_types / install_deps in lib/deps.sh.
# These tests source the library directly so they don't need a real worktree
# tree or network access — they only need a temp dir with fixture files.

load 'test_helper/common'

setup() {
    LIB_DIR="$(cd "$(dirname "${BATS_TEST_DIRNAME}")/lib" && pwd)"
    # deps.sh references log_info / log_warn from common.sh.
    # shellcheck source=/dev/null
    source "${LIB_DIR}/common.sh"
    # shellcheck source=/dev/null
    source "${LIB_DIR}/deps.sh"

    # The real entrypoint runs under `set -euo pipefail`. Mirror pipefail so
    # the pipe-to-`tail` exit status reflects the real package manager status.
    set -o pipefail

    # Normalise the path the same way find_mise_configs does (`cd` + `pwd`), so
    # comparisons hold on macOS where mktemp -d returns a symlinked path.
    DEPS_TMP="$(cd "$(mktemp -d)" && pwd)"
}

teardown() {
    if [ -n "${DEPS_TMP:-}" ] && [ -d "$DEPS_TMP" ]; then
        rm -rf "$DEPS_TMP"
    fi
    # Restore PATH if a test mutated it
    if [ -n "${SAVED_PATH:-}" ]; then
        PATH="$SAVED_PATH"
        unset SAVED_PATH
    fi
    unset WORKTREE_NO_MISE
}

# ---------------------------------------------------------------------------
# detect_deps_types
# ---------------------------------------------------------------------------

@test "detect_deps_types: empty dir emits nothing" {
    run detect_deps_types "$DEPS_TMP"
    assert_success
    [ -z "$output" ]
}

@test "detect_deps_types: package-lock.json only emits npm" {
    touch "${DEPS_TMP}/package-lock.json"
    run detect_deps_types "$DEPS_TMP"
    assert_success
    [ "$output" = "npm" ]
}

@test "detect_deps_types: composer.lock only emits composer" {
    touch "${DEPS_TMP}/composer.lock"
    run detect_deps_types "$DEPS_TMP"
    assert_success
    [ "$output" = "composer" ]
}

# Regression: the bug being fixed. composer+npm coexistence (e.g. EC-CUBE)
# previously only emitted "npm" because of an if/elif chain.
@test "detect_deps_types: composer.lock + package-lock.json emits both (npm first)" {
    touch "${DEPS_TMP}/package-lock.json"
    touch "${DEPS_TMP}/composer.lock"
    run detect_deps_types "$DEPS_TMP"
    assert_success
    [ "${lines[0]}" = "npm" ]
    [ "${lines[1]}" = "composer" ]
    [ "${#lines[@]}" -eq 2 ]
}

@test "detect_deps_types: Node.js family stays mutually exclusive (npm beats pnpm)" {
    touch "${DEPS_TMP}/package-lock.json"
    touch "${DEPS_TMP}/pnpm-lock.yaml"
    run detect_deps_types "$DEPS_TMP"
    assert_success
    [ "$output" = "npm" ]
}

@test "detect_deps_types: Node.js family stays mutually exclusive (pnpm beats yarn)" {
    touch "${DEPS_TMP}/pnpm-lock.yaml"
    touch "${DEPS_TMP}/yarn.lock"
    run detect_deps_types "$DEPS_TMP"
    assert_success
    [ "$output" = "pnpm" ]
}

@test "detect_deps_types: yarn + composer emits both" {
    touch "${DEPS_TMP}/yarn.lock"
    touch "${DEPS_TMP}/composer.lock"
    run detect_deps_types "$DEPS_TMP"
    assert_success
    [ "${lines[0]}" = "yarn" ]
    [ "${lines[1]}" = "composer" ]
    [ "${#lines[@]}" -eq 2 ]
}

@test "detect_deps_types: dotnet detected from .csproj" {
    touch "${DEPS_TMP}/App.csproj"
    run detect_deps_types "$DEPS_TMP"
    assert_success
    [ "$output" = "dotnet" ]
}

@test "detect_deps_types: composer + dotnet emits both, independent of Node" {
    touch "${DEPS_TMP}/composer.lock"
    touch "${DEPS_TMP}/App.sln"
    run detect_deps_types "$DEPS_TMP"
    assert_success
    [ "${lines[0]}" = "composer" ]
    [ "${lines[1]}" = "dotnet" ]
    [ "${#lines[@]}" -eq 2 ]
}

# ---------------------------------------------------------------------------
# install_deps with stubbed package managers
#
# We shadow npm/composer/etc. with fake scripts that log invocations and
# exit 0, then confirm every detected manager actually got called.
# ---------------------------------------------------------------------------

# Place fake CLIs that record invocations to $DEPS_TMP/calls.log.
setup_stub_clis() {
    SAVED_PATH="$PATH"
    STUB_BIN="${DEPS_TMP}/stub-bin"
    mkdir -p "$STUB_BIN"
    for cli in npm pnpm yarn composer dotnet; do
        cat > "${STUB_BIN}/${cli}" <<EOF
#!/bin/bash
echo "${cli} \$*" >> "${DEPS_TMP}/calls.log"
exit 0
EOF
        chmod +x "${STUB_BIN}/${cli}"
    done
    PATH="${STUB_BIN}:${PATH}"
}

# Shadow mise with a fake that records invocations. `mise exec -- <cmd>` runs
# <cmd> so the stubbed package managers still report success, mirroring the
# real behaviour of putting mise-managed tools on PATH.
# Must be called after setup_stub_clis (it reuses $STUB_BIN / $PATH).
setup_stub_mise() {
    cat > "${STUB_BIN}/mise" <<EOF
#!/bin/bash
echo "mise \$*" >> "${DEPS_TMP}/calls.log"
if [ "\$1" = "exec" ]; then
    shift
    [ "\$1" = "--" ] && shift
    exec "\$@"
fi
exit 0
EOF
    chmod +x "${STUB_BIN}/mise"
}

@test "install_deps: composer + npm coexistence runs both" {
    setup_stub_clis
    touch "${DEPS_TMP}/package-lock.json"
    touch "${DEPS_TMP}/composer.lock"

    run install_deps "$DEPS_TMP"
    assert_success

    assert_output --partial "Running npm install"
    assert_output --partial "Running composer install"

    # Both stubs must have been invoked
    grep -q '^npm install' "${DEPS_TMP}/calls.log"
    grep -q '^composer install' "${DEPS_TMP}/calls.log"
}

@test "install_deps: composer-only project still runs composer" {
    setup_stub_clis
    touch "${DEPS_TMP}/composer.lock"

    run install_deps "$DEPS_TMP"
    assert_success

    assert_output --partial "Running composer install"
    grep -q '^composer install' "${DEPS_TMP}/calls.log"
    # No npm call should have happened
    ! grep -q '^npm' "${DEPS_TMP}/calls.log"
}

@test "install_deps: returns 1 when nothing detected" {
    run install_deps "$DEPS_TMP"
    assert_failure
}

@test "install_deps: partial failure (npm fails, composer ok) still returns 0" {
    SAVED_PATH="$PATH"
    STUB_BIN="${DEPS_TMP}/stub-bin"
    mkdir -p "$STUB_BIN"
    # npm exits non-zero, composer succeeds
    cat > "${STUB_BIN}/npm" <<'EOF'
#!/bin/bash
exit 1
EOF
    cat > "${STUB_BIN}/composer" <<EOF
#!/bin/bash
echo "composer \$*" >> "${DEPS_TMP}/calls.log"
exit 0
EOF
    chmod +x "${STUB_BIN}/npm" "${STUB_BIN}/composer"
    PATH="${STUB_BIN}:${PATH}"

    touch "${DEPS_TMP}/package-lock.json"
    touch "${DEPS_TMP}/composer.lock"

    run install_deps "$DEPS_TMP"
    assert_success
    assert_output --partial "npm install failed"
    grep -q '^composer install' "${DEPS_TMP}/calls.log"
}

# ---------------------------------------------------------------------------
# find_mise_configs
# ---------------------------------------------------------------------------

@test "find_mise_configs: no config emits nothing" {
    run find_mise_configs "$DEPS_TMP"
    assert_success
    [ -z "$output" ]
}

@test "find_mise_configs: finds mise.toml in the directory itself" {
    touch "${DEPS_TMP}/mise.toml"
    run find_mise_configs "$DEPS_TMP"
    assert_success
    [ "$output" = "${DEPS_TMP}/mise.toml" ]
}

@test "find_mise_configs: finds mise.local.toml and .tool-versions" {
    touch "${DEPS_TMP}/mise.local.toml" "${DEPS_TMP}/.tool-versions"
    run find_mise_configs "$DEPS_TMP"
    assert_success
    assert_output --partial "${DEPS_TMP}/mise.local.toml"
    assert_output --partial "${DEPS_TMP}/.tool-versions"
}

# Multi-repo layout: the config sits in the task directory (symlinked from the
# project root) while installs run in a sub-repo below it.
@test "find_mise_configs: walks up to the boundary" {
    mkdir -p "${DEPS_TMP}/task/sub"
    touch "${DEPS_TMP}/task/mise.toml"
    run find_mise_configs "${DEPS_TMP}/task/sub" "${DEPS_TMP}/task"
    assert_success
    [ "$output" = "${DEPS_TMP}/task/mise.toml" ]
}

@test "find_mise_configs: without a boundary only the directory itself is searched" {
    mkdir -p "${DEPS_TMP}/task/sub"
    touch "${DEPS_TMP}/task/mise.toml"
    run find_mise_configs "${DEPS_TMP}/task/sub"
    assert_success
    [ -z "$output" ]
}

@test "find_mise_configs: boundary that is not an ancestor is ignored" {
    mkdir -p "${DEPS_TMP}/task/sub"
    touch "${DEPS_TMP}/task/mise.toml"
    run find_mise_configs "${DEPS_TMP}/task/sub" "/etc"
    assert_success
    [ -z "$output" ]
}

@test "find_mise_configs: trailing '.' path component is normalised" {
    touch "${DEPS_TMP}/mise.toml"
    run find_mise_configs "${DEPS_TMP}/." "$DEPS_TMP"
    assert_success
    [ "$output" = "${DEPS_TMP}/mise.toml" ]
}

# ---------------------------------------------------------------------------
# install_deps + mise
#
# Regression: mise-managed toolchains (dotnet, node, ...) are not on PATH in a
# freshly created worktree because the shell hook never fires there, so the
# install used to die with "command not found".
# ---------------------------------------------------------------------------

@test "install_deps: runs through mise exec and trusts the config when mise.toml exists" {
    setup_stub_clis
    setup_stub_mise
    touch "${DEPS_TMP}/mise.toml"
    touch "${DEPS_TMP}/App.csproj"

    run install_deps "$DEPS_TMP"
    assert_success
    assert_output --partial "Using mise"

    grep -q "^mise trust ${DEPS_TMP}/mise.toml\$" "${DEPS_TMP}/calls.log"
    grep -q '^mise exec -- dotnet restore$' "${DEPS_TMP}/calls.log"
    # The tool itself still ran, through mise
    grep -q '^dotnet restore$' "${DEPS_TMP}/calls.log"
}

@test "install_deps: uses the mise config found at the boundary" {
    setup_stub_clis
    setup_stub_mise
    mkdir -p "${DEPS_TMP}/task/sub"
    touch "${DEPS_TMP}/task/mise.toml"
    touch "${DEPS_TMP}/task/sub/package-lock.json"

    run install_deps "${DEPS_TMP}/task/sub" "${DEPS_TMP}/task"
    assert_success

    grep -q "^mise trust ${DEPS_TMP}/task/mise.toml\$" "${DEPS_TMP}/calls.log"
    grep -q '^mise exec -- npm install' "${DEPS_TMP}/calls.log"
}

@test "install_deps: .tool-versions enables mise but is not trusted" {
    setup_stub_clis
    setup_stub_mise
    touch "${DEPS_TMP}/.tool-versions"
    touch "${DEPS_TMP}/package-lock.json"

    run install_deps "$DEPS_TMP"
    assert_success

    grep -q '^mise exec -- npm install' "${DEPS_TMP}/calls.log"
    ! grep -q '^mise trust' "${DEPS_TMP}/calls.log"
}

@test "install_deps: no mise config runs the package manager directly" {
    setup_stub_clis
    setup_stub_mise
    touch "${DEPS_TMP}/package-lock.json"

    run install_deps "$DEPS_TMP"
    assert_success
    refute_output --partial "Using mise"

    grep -q '^npm install' "${DEPS_TMP}/calls.log"
    ! grep -q '^mise' "${DEPS_TMP}/calls.log"
}

@test "install_deps: WORKTREE_NO_MISE=1 bypasses mise entirely" {
    setup_stub_clis
    setup_stub_mise
    touch "${DEPS_TMP}/mise.toml"
    touch "${DEPS_TMP}/package-lock.json"

    export WORKTREE_NO_MISE=1
    run install_deps "$DEPS_TMP"
    assert_success
    refute_output --partial "Using mise"

    grep -q '^npm install' "${DEPS_TMP}/calls.log"
    ! grep -q '^mise' "${DEPS_TMP}/calls.log"
}
