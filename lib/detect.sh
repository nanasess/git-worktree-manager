#!/bin/bash
#
# detect.sh - プロジェクト検出・リポジトリ列挙
#

# プロジェクトルート配下の git リポジトリを列挙
# 直下のサブディレクトリで .git が存在するものを返す
list_git_repos() {
    local project_root
    project_root="$(get_project_root)"
    local repos=()

    for dir in "$project_root"/*/; do
        [ -d "$dir" ] || continue
        dir="${dir%/}"
        if [ -d "$dir/.git" ] || [ -f "$dir/.git" ]; then
            repos+=("$(basename "$dir")")
        fi
    done

    echo "${repos[@]}"
}

# プロジェクトルート直下の非 git アイテム（シンボリックリンク対象）を列挙
# .git ディレクトリを持たないファイル・ディレクトリ
list_non_git_items() {
    local project_root
    project_root="$(get_project_root)"
    local items=()

    for item in "$project_root"/*; do
        [ -e "$item" ] || continue
        local name
        name="$(basename "$item")"

        # ディレクトリの場合、.git を持つものはスキップ（git リポジトリ）
        if [ -d "$item" ]; then
            if [ -d "$item/.git" ] || [ -f "$item/.git" ]; then
                continue
            fi
        fi

        items+=("$name")
    done

    # dotfile も対象にする
    for item in "$project_root"/.*; do
        [ -e "$item" ] || continue
        local name
        name="$(basename "$item")"
        # . と .. はスキップ
        [ "$name" = "." ] || [ "$name" = ".." ] && continue
        # .git はスキップ
        [ "$name" = ".git" ] && continue
        # .worktreerc はスキップ（フックとして別途処理）
        [ "$name" = ".worktreerc" ] && continue
        items+=("$name")
    done

    echo "${items[@]}"
}

# リポジトリのデフォルトブランチを検出（origin/HEAD から取得）
detect_default_branch() {
    local repo_path="$1"

    # origin/HEAD が設定されている場合
    local ref
    ref=$(git -C "$repo_path" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null)
    if [ -n "$ref" ]; then
        echo "${ref#refs/remotes/origin/}"
        return
    fi

    # origin/HEAD が未設定の場合、リモートの HEAD を取得して設定
    if git -C "$repo_path" remote set-head origin --auto >/dev/null 2>&1; then
        ref=$(git -C "$repo_path" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null)
        if [ -n "$ref" ]; then
            echo "${ref#refs/remotes/origin/}"
            return
        fi
    fi

    # フォールバック: main or master
    if git -C "$repo_path" rev-parse --verify origin/main >/dev/null 2>&1; then
        echo "main"
    elif git -C "$repo_path" rev-parse --verify origin/master >/dev/null 2>&1; then
        echo "master"
    else
        log_error "デフォルトブランチを検出できません: $repo_path"
        return 1
    fi
}
