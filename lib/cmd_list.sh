#!/bin/bash
#
# cmd_list.sh - list サブコマンド
#

cmd_list_usage() {
    echo -e "${BOLD}worktree list${NC} - 現在の worktree 一覧を表示"
    echo ""
    echo -e "${BOLD}USAGE:${NC}"
    echo "    worktree list [OPTIONS]"
    echo ""
    echo -e "${BOLD}OPTIONS:${NC}"
    echo "    -h, --help    ヘルプを表示"
    echo ""
    echo -e "${BOLD}ALIASES:${NC}"
    echo "    worktree ls"
}

cmd_list() {
    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help)
                cmd_list_usage
                return 0
                ;;
            *)
                log_error "不明なオプション: $1"
                cmd_list_usage
                return 1
                ;;
        esac
        shift
    done

    local project_name
    project_name="$(get_project_name)"
    local worktrees_base
    worktrees_base="$(get_worktrees_base)"

    echo ""
    echo -e "${BOLD}${project_name}${NC} の worktree 一覧"
    echo "============================================"

    if [ ! -d "$worktrees_base" ]; then
        log_info "worktree はありません"
        echo ""
        return 0
    fi

    # worktrees_base 配下から git worktree を含むタスクディレクトリを探索
    # タスク名にスラッシュが含まれる場合（例: feature/task-name）にも対応
    # 単一リポジトリの場合は .git が depth 2 にあるため mindepth 2 を使用
    local task_names=()
    while IFS= read -r git_marker; do
        # git_marker は以下のいずれか:
        #   複数リポ: <worktrees_base>/<task_name>/<repo>/.git
        #   単一リポ: <worktrees_base>/<task_name>/.git
        local repo_dir="${git_marker%/*}"
        local relative="${repo_dir#"$worktrees_base"/}"

        # 構成に応じてタスク名を抽出
        local task_name
        if is_single_repo; then
            task_name="$relative"
        else
            task_name="${relative%/*}"
        fi

        # 重複チェック
        local found=false
        for existing in "${task_names[@]}"; do
            if [ "$existing" = "$task_name" ]; then
                found=true
                break
            fi
        done
        if [ "$found" = false ]; then
            task_names+=("$task_name")
        fi
    done < <(find "$worktrees_base" -name ".git" -mindepth 2 2>/dev/null | sort)

    if [ ${#task_names[@]} -eq 0 ]; then
        log_info "worktree はありません"
    fi

    for task_name in "${task_names[@]}"; do
        local task_dir="${worktrees_base}/${task_name}"

        echo ""
        echo -e "  ${BOLD}${task_name}${NC}"
        echo "  ------------------------------------------"

        # タスクディレクトリ内のリポジトリを列挙（単一リポ・複数リポ両対応）
        local repo_dirs_str
        repo_dirs_str="$(list_task_repo_dirs "$task_dir")"
        if [ -n "$repo_dirs_str" ]; then
            read -ra repo_dirs <<< "$repo_dirs_str"
            for repo_dir in "${repo_dirs[@]}"; do
                local repo_name
                if [ "$repo_dir" = "$task_dir" ]; then
                    # 単一リポジトリ: プロジェクト名を表示
                    repo_name="$(get_project_name)"
                else
                    repo_name="$(basename "$repo_dir")"
                fi
                local branch
                branch="$(git -C "$repo_dir" branch --show-current 2>/dev/null || echo "?")"

                # 変更状態を確認
                local status_icon=""
                if ! git -C "$repo_dir" diff --quiet 2>/dev/null || ! git -C "$repo_dir" diff --cached --quiet 2>/dev/null; then
                    status_icon=" ${YELLOW}[変更あり]${NC}"
                fi

                # 未追跡ファイルがあるか確認
                local untracked
                untracked="$( (git -C "$repo_dir" ls-files --others --exclude-standard 2>/dev/null || true) | head -1)"
                if [ -n "$untracked" ]; then
                    status_icon="${status_icon} ${YELLOW}[未追跡]${NC}"
                fi

                echo -e "    ${repo_name}: ${GREEN}${branch}${NC}${status_icon}"
            done
        fi
    done

    echo ""
    return 0
}
