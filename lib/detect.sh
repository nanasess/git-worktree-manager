#!/bin/bash
#
# detect.sh - プロジェクト検出・リポジトリ列挙
#

# プロジェクトルート自体が git リポジトリかどうかを判定
is_single_repo() {
    local project_root
    project_root="$(get_project_root)"
    [ -d "$project_root/.git" ] || [ -f "$project_root/.git" ]
}

# プロジェクトルート配下の git リポジトリを列挙
# 単一リポジトリの場合は "." を返す
# 複数リポジトリの場合は直下のサブディレクトリ名を返す
list_git_repos() {
    local project_root
    project_root="$(get_project_root)"

    # 単一リポジトリ: project_root 自体が .git を持つ
    if is_single_repo; then
        echo "."
        return
    fi

    # 複数リポジトリ: 直下のサブディレクトリを走査
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

# タスクディレクトリ内の worktree リポジトリディレクトリを列挙
# 複数リポ: task_dir/repo1, task_dir/repo2, ...
# 単一リポ: task_dir 自体
list_task_repo_dirs() {
    local task_dir="$1"
    local dirs=()

    for repo_dir in "$task_dir"/*/; do
        [ -d "$repo_dir" ] || continue
        repo_dir="${repo_dir%/}"
        if [ -d "$repo_dir/.git" ] || [ -f "$repo_dir/.git" ]; then
            dirs+=("$repo_dir")
        fi
    done

    # 単一リポジトリ: task_dir 自体が worktree
    if [ ${#dirs[@]} -eq 0 ]; then
        if [ -f "$task_dir/.git" ] || [ -d "$task_dir/.git" ]; then
            dirs+=("$task_dir")
        fi
    fi

    echo "${dirs[@]}"
}

# worktree の repo_dir から元リポジトリのパスを算出
get_main_repo_path() {
    local repo_dir="$1"
    local task_dir="$2"
    local project_root="$3"

    if [ "$repo_dir" = "$task_dir" ]; then
        # 単一リポジトリ: 元リポは project_root 自体
        echo "$project_root"
    else
        local repo_name
        repo_name="$(basename "$repo_dir")"
        echo "${project_root}/${repo_name}"
    fi
}

# プロジェクトルート直下の非 git アイテム（シンボリックリンク対象）を列挙
# .git ディレクトリを持たないファイル・ディレクトリ
# 単一リポジトリの場合は空を返す（worktree に全ファイルが含まれるため）
list_non_git_items() {
    # 単一リポジトリ: worktree が全ファイルを含むのでシンボリックリンク不要
    if is_single_repo; then
        echo ""
        return
    fi

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
