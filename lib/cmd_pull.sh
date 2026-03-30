#!/bin/bash
#
# cmd_pull.sh - pull サブコマンド
#

cmd_pull_usage() {
    echo -e "${BOLD}worktree pull${NC} - 配下の git リポジトリを一括で pull"
    echo ""
    echo -e "${BOLD}USAGE:${NC}"
    echo "    worktree pull [OPTIONS]"
    echo ""
    echo -e "${BOLD}OPTIONS:${NC}"
    echo "    -h, --help    ヘルプを表示"
    echo ""
    echo -e "${BOLD}EXAMPLES:${NC}"
    echo "    cd ~/git-repos/EcAuth && worktree pull"
    echo "    cd ~/git-repos/EcAuth.worktrees/task-1 && worktree pull"
}

cmd_pull() {
    # オプション解析
    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help)
                cmd_pull_usage
                return 0
                ;;
            -*)
                log_error "不明なオプション: $1"
                cmd_pull_usage
                return 1
                ;;
            *)
                log_error "不明な引数: $1"
                cmd_pull_usage
                return 1
                ;;
        esac
        shift
    done

    local project_root
    project_root="$(get_project_root)"
    local project_name
    project_name="$(get_project_name)"

    # git リポジトリを列挙
    local repos_str
    repos_str="$(list_git_repos)"
    read -ra repos <<< "$repos_str"

    if [ ${#repos[@]} -eq 0 ]; then
        log_error "git リポジトリが見つかりません: ${project_root}"
        return 1
    fi

    echo ""
    echo "============================================"
    echo -e " ${BOLD}worktree pull${NC}: ${project_name}"
    echo "============================================"
    echo ""
    log_info "ディレクトリ: ${project_root}"
    log_info "対象リポジトリ (${#repos[@]}): ${repos[*]}"
    echo ""

    # 結果格納
    declare -A RESULTS

    for repo in "${repos[@]}"; do
        local repo_path="${project_root}/${repo}"

        echo "------------------------------------------"
        log_info "処理中: ${repo}"

        # 現在のブランチを表示
        local current_branch
        current_branch="$(git -C "$repo_path" branch --show-current 2>/dev/null)"
        if [ -n "$current_branch" ]; then
            log_info "  ブランチ: ${current_branch}"
        fi

        # git pull
        local pull_output
        if pull_output=$(git -C "$repo_path" pull 2>&1); then
            if echo "$pull_output" | grep -q "Already up to date"; then
                log_success "  最新です"
                RESULTS["$repo"]="OK: 最新"
            else
                log_success "  pull しました"
                RESULTS["$repo"]="OK: 更新あり"
            fi
        else
            log_error "  pull に失敗しました"
            echo "$pull_output" | sed 's/^/    /'
            RESULTS["$repo"]="FAIL: pull 失敗"
        fi
    done

    # 結果サマリ
    print_summary RESULTS "${repos[@]}"
}
