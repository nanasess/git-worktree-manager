#!/bin/bash
#
# deps.sh - 依存関係検出・インストール
#

# lock ファイルに基づいて依存関係をインストール
# Usage: install_deps <directory>
install_deps() {
    local dir="$1"

    if [ ! -d "$dir" ]; then
        return 0
    fi

    local installed=false

    if [ -f "$dir/package-lock.json" ]; then
        log_info "  npm install を実行中..."
        if (cd "$dir" && npm install --no-audit --no-fund 2>&1 | tail -1); then
            installed=true
        else
            log_warn "  npm install が失敗しました"
        fi
    elif [ -f "$dir/pnpm-lock.yaml" ]; then
        log_info "  pnpm install を実行中..."
        if (cd "$dir" && pnpm install --frozen-lockfile 2>&1 | tail -1); then
            installed=true
        else
            log_warn "  pnpm install が失敗しました"
        fi
    elif [ -f "$dir/yarn.lock" ]; then
        log_info "  yarn install を実行中..."
        if (cd "$dir" && yarn install --frozen-lockfile 2>&1 | tail -1); then
            installed=true
        else
            log_warn "  yarn install が失敗しました"
        fi
    elif [ -f "$dir/composer.lock" ]; then
        log_info "  composer install を実行中..."
        if (cd "$dir" && composer install --no-interaction 2>&1 | tail -1); then
            installed=true
        else
            log_warn "  composer install が失敗しました"
        fi
    elif compgen -G "$dir/*.sln" >/dev/null 2>&1 || compgen -G "$dir/*.csproj" >/dev/null 2>&1; then
        log_info "  dotnet restore を実行中..."
        if (cd "$dir" && dotnet restore 2>&1 | tail -1); then
            installed=true
        else
            log_warn "  dotnet restore が失敗しました"
        fi
    fi

    if [ "$installed" = true ]; then
        return 0
    fi
    return 1
}

# ディレクトリ内の依存関係ファイルの種類を検出
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
