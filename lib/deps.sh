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

# Install dependencies for every detected package manager.
# Returns 0 if at least one install succeeded, 1 otherwise (including no
# managers detected). Callers typically swallow the failure with `|| true`.
# Usage: install_deps <directory>
install_deps() {
    local dir="$1"

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

    local installed=false
    local type
    for type in "${types[@]}"; do
        case "$type" in
            npm)
                log_info "  Running npm install..."
                if (cd "$dir" && npm install --no-audit --no-fund 2>&1 | tail -1); then
                    installed=true
                else
                    log_warn "  npm install failed"
                fi
                ;;
            pnpm)
                log_info "  Running pnpm install..."
                if (cd "$dir" && pnpm install --frozen-lockfile 2>&1 | tail -1); then
                    installed=true
                else
                    log_warn "  pnpm install failed"
                fi
                ;;
            yarn)
                log_info "  Running yarn install..."
                if (cd "$dir" && yarn install --frozen-lockfile 2>&1 | tail -1); then
                    installed=true
                else
                    log_warn "  yarn install failed"
                fi
                ;;
            composer)
                log_info "  Running composer install..."
                if (cd "$dir" && composer install --no-interaction 2>&1 | tail -1); then
                    installed=true
                else
                    log_warn "  composer install failed"
                fi
                ;;
            dotnet)
                log_info "  Running dotnet restore..."
                if (cd "$dir" && dotnet restore 2>&1 | tail -1); then
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
