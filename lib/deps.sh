#!/bin/bash
#
# deps.sh - Dependency detection and installation
#

# Detect dependency types from lock files in a directory.
# Emits each detected package manager on its own line.
# Node.js managers (npm/pnpm/yarn) are mutually exclusive within a single
# directory and resolved with priority npm > pnpm > yarn. Composer and
# dotnet are detected independently so polyglot projects (e.g. EC-CUBE with
# composer.json + package.json) report every applicable manager.
detect_deps_types() {
    local dir="$1"

    if [ -f "$dir/package-lock.json" ]; then
        echo "npm"
    elif [ -f "$dir/pnpm-lock.yaml" ]; then
        echo "pnpm"
    elif [ -f "$dir/yarn.lock" ]; then
        echo "yarn"
    fi

    if [ -f "$dir/composer.lock" ]; then
        echo "composer"
    fi

    if compgen -G "$dir/*.sln" >/dev/null 2>&1 || compgen -G "$dir/*.csproj" >/dev/null 2>&1; then
        echo "dotnet"
    fi
}

# File names mise recognises as config files, looked up in every candidate
# directory when deciding whether package managers should run through mise.
MISE_CONFIG_NAMES=(
    mise.toml
    mise.local.toml
    .mise.toml
    .mise.local.toml
    mise/config.toml
    .mise/config.toml
    .config/mise.toml
    .config/mise/config.toml
    .tool-versions
)

# True when mise integration is available and not disabled.
# Set WORKTREE_NO_MISE=1 to always run package managers straight from PATH.
mise_enabled() {
    if [ "${WORKTREE_NO_MISE:-0}" = "1" ]; then
        return 1
    fi
    command -v mise >/dev/null 2>&1
}

# Emit the mise config files that apply to <dir>, walking up from <dir> to
# <boundary> (inclusive). <boundary> defaults to <dir> and is ignored when it
# is not an ancestor of <dir>; the walk always stops at "/".
# The boundary keeps the search inside the worktree: in a multi-repo layout the
# config often lives in the task directory (symlinked from the project root)
# rather than in the sub-repo that is being installed.
# Usage: find_mise_configs <dir> [boundary]
find_mise_configs() {
    local dir boundary
    dir="$(cd "$1" 2>/dev/null && pwd)" || return 0

    boundary="$dir"
    if [ -n "${2:-}" ]; then
        local candidate
        if candidate="$(cd "$2" 2>/dev/null && pwd)"; then
            case "${dir}/" in
                "${candidate}"/*) boundary="$candidate" ;;
            esac
        fi
    fi

    local current="$dir"
    while :; do
        local name
        for name in "${MISE_CONFIG_NAMES[@]}"; do
            if [ -f "${current}/${name}" ]; then
                echo "${current}/${name}"
            fi
        done
        if [ "$current" = "$boundary" ] || [ "$current" = "/" ]; then
            break
        fi
        current="$(dirname "$current")"
    done

    return 0
}

# Mark mise config files as trusted so `mise exec` can parse the ones that may
# execute code (templates, [env], tool options). A worktree is a brand new
# absolute path, so configs trusted in the project root are untrusted here and
# mise would abort instead of prompting in this non-interactive context.
# `.tool-versions` carries no executable content and needs no trust.
# Usage: trust_mise_configs <config-file>...
trust_mise_configs() {
    local config
    for config in "$@"; do
        case "$config" in
            *.toml) ;;
            *) continue ;;
        esac
        if ! mise trust "$config" >/dev/null 2>&1; then
            log_warn "  mise trust failed for ${config} (continuing)"
        fi
    done
}

# Run a package manager inside <dir>, keeping only the last line of its output.
# The entrypoint runs under `set -o pipefail`, so the reported status is the
# package manager's, not tail's.
# Usage: run_deps_cmd <dir> <command> [args...]
run_deps_cmd() {
    local dir="$1"
    shift
    (cd "$dir" && "$@" 2>&1 | tail -1)
}

# Install dependencies for every detected package manager.
# Returns 0 if at least one install succeeded, 1 otherwise (including no
# managers detected). Callers typically swallow the failure with `|| true`.
# When a mise config applies to the worktree, commands run through
# `mise exec --` so mise-managed toolchains (dotnet, node, php, ...) are on
# PATH: the shell hook that normally sets them up never fires for a directory
# created by another process, which otherwise fails with "command not found".
# <config-root> bounds the upward search for mise configs (see
# find_mise_configs); pass the task directory.
# Usage: install_deps <directory> [config-root]
install_deps() {
    local dir="$1"
    local config_root="${2:-$1}"

    if [ ! -d "$dir" ]; then
        return 0
    fi

    local types=()
    while IFS= read -r line; do
        [ -n "$line" ] && types+=("$line")
    done < <(detect_deps_types "$dir")

    if [ ${#types[@]} -eq 0 ]; then
        return 1
    fi

    # Resolve the command prefix: `mise exec --` when mise governs this
    # worktree, empty otherwise.
    local runner=()
    if mise_enabled; then
        local mise_configs=()
        while IFS= read -r line; do
            [ -n "$line" ] && mise_configs+=("$line")
        done < <(find_mise_configs "$dir" "$config_root")

        if [ ${#mise_configs[@]} -gt 0 ]; then
            trust_mise_configs "${mise_configs[@]}"
            runner=(mise exec --)
            log_info "  Using mise (${mise_configs[0]})"
        fi
    fi

    local installed=false
    local type
    for type in "${types[@]}"; do
        case "$type" in
            npm)
                log_info "  Running npm install..."
                if run_deps_cmd "$dir" ${runner[@]+"${runner[@]}"} npm install --no-audit --no-fund; then
                    installed=true
                else
                    log_warn "  npm install failed"
                fi
                ;;
            pnpm)
                log_info "  Running pnpm install..."
                if run_deps_cmd "$dir" ${runner[@]+"${runner[@]}"} pnpm install --frozen-lockfile; then
                    installed=true
                else
                    log_warn "  pnpm install failed"
                fi
                ;;
            yarn)
                log_info "  Running yarn install..."
                if run_deps_cmd "$dir" ${runner[@]+"${runner[@]}"} yarn install --frozen-lockfile; then
                    installed=true
                else
                    log_warn "  yarn install failed"
                fi
                ;;
            composer)
                log_info "  Running composer install..."
                if run_deps_cmd "$dir" ${runner[@]+"${runner[@]}"} composer install --no-interaction; then
                    installed=true
                else
                    log_warn "  composer install failed"
                fi
                ;;
            dotnet)
                log_info "  Running dotnet restore..."
                if run_deps_cmd "$dir" ${runner[@]+"${runner[@]}"} dotnet restore; then
                    installed=true
                else
                    log_warn "  dotnet restore failed"
                fi
                ;;
        esac
    done

    if [ "$installed" = true ]; then
        return 0
    fi
    return 1
}
