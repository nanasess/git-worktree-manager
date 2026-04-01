#!/bin/bash
#
# deps.sh - Dependency detection and installation
#

# Install dependencies based on lock files
# Usage: install_deps <directory>
install_deps() {
    local dir="$1"

    if [ ! -d "$dir" ]; then
        return 0
    fi

    local installed=false

    if [ -f "$dir/package-lock.json" ]; then
        log_info "  Running npm install..."
        if (cd "$dir" && npm install --no-audit --no-fund 2>&1 | tail -1); then
            installed=true
        else
            log_warn "  npm install failed"
        fi
    elif [ -f "$dir/pnpm-lock.yaml" ]; then
        log_info "  Running pnpm install..."
        if (cd "$dir" && pnpm install --frozen-lockfile 2>&1 | tail -1); then
            installed=true
        else
            log_warn "  pnpm install failed"
        fi
    elif [ -f "$dir/yarn.lock" ]; then
        log_info "  Running yarn install..."
        if (cd "$dir" && yarn install --frozen-lockfile 2>&1 | tail -1); then
            installed=true
        else
            log_warn "  yarn install failed"
        fi
    elif [ -f "$dir/composer.lock" ]; then
        log_info "  Running composer install..."
        if (cd "$dir" && composer install --no-interaction 2>&1 | tail -1); then
            installed=true
        else
            log_warn "  composer install failed"
        fi
    elif compgen -G "$dir/*.sln" >/dev/null 2>&1 || compgen -G "$dir/*.csproj" >/dev/null 2>&1; then
        log_info "  Running dotnet restore..."
        if (cd "$dir" && dotnet restore 2>&1 | tail -1); then
            installed=true
        else
            log_warn "  dotnet restore failed"
        fi
    fi

    if [ "$installed" = true ]; then
        return 0
    fi
    return 1
}

# Detect dependency type from lock files in a directory
detect_deps_type() {
    local dir="$1"

    if [ -f "$dir/package-lock.json" ]; then
        echo "npm"
    elif [ -f "$dir/pnpm-lock.yaml" ]; then
        echo "pnpm"
    elif [ -f "$dir/yarn.lock" ]; then
        echo "yarn"
    elif [ -f "$dir/composer.lock" ]; then
        echo "composer"
    elif compgen -G "$dir/*.sln" >/dev/null 2>&1 || compgen -G "$dir/*.csproj" >/dev/null 2>&1; then
        echo "dotnet"
    else
        echo ""
    fi
}
