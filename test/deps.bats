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

    DEPS_TMP="$(mktemp -d)"
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
