#!/bin/bash
#
# cmd_checkout.sh - checkout サブコマンド
#

cmd_checkout_usage() {
    echo -e "${BOLD}worktree checkout${NC} - 配下の git リポジトリを一括でチェックアウト"
    echo ""
    echo -e "${BOLD}USAGE:${NC}"
    echo "    worktree checkout [BRANCH] [OPTIONS]"
    echo ""
    echo -e "${BOLD}ARGUMENTS:${NC}"
    echo "    BRANCH    チェックアウトするブランチ名（省略時: 各リポジトリのデフォルトブランチ）"
    echo ""
    echo -e "${BOLD}OPTIONS:${NC}"
    echo "    -h, --help    ヘルプを表示"
    echo ""
    echo -e "${BOLD}EXAMPLES:${NC}"
    echo "    cd ~/git-repos/EcAuth && worktree checkout"
    echo "    cd ~/git-repos/EcAuth && worktree checkout main"
    echo "    cd ~/git-repos/EcAuth && worktree checkout develop"
}

cmd_checkout() {
    local branch=""

    # オプション解析
    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help)
                cmd_checkout_usage
                return 0
                ;;
            -*)
                log_error "不明なオプション: $1"
                cmd_checkout_usage
                return 1
                ;;
            *)
                if [ -z "$branch" ]; then
                    branch="$1"
                else
                    log_error "不明な引数: $1"
                    cmd_checkout_usage
                    return 1
                fi
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

    local target_desc
    if [ -n "$branch" ]; then
        target_desc="$branch"
    else
        target_desc="デフォルトブランチ"
    fi

    echo ""
    echo "============================================"
    echo -e " ${BOLD}worktree checkout${NC}: ${project_name}"
    echo "============================================"
    echo ""
    log_info "ディレクトリ: ${project_root}"
    log_info "対象リポジトリ (${#repos[@]}): ${repos[*]}"
    log_info "チェックアウト先: ${target_desc}"
    echo ""

    # 結果格納
    declare -A RESULTS

    for repo in "${repos[@]}"; do
        local repo_path="${project_root}/${repo}"

        echo "------------------------------------------"
        log_info "処理中: ${repo}"

        # チェックアウト先ブランチを決定
        local target_branch
        if [ -n "$branch" ]; then
            target_branch="$branch"
        else
            target_branch="$(detect_default_branch "$repo_path")" || {
                log_error "  デフォルトブランチの検出に失敗しました"
                RESULTS["$repo"]="FAIL: ブランチ検出失敗"
                continue
            }
        fi

        # 現在のブランチを表示
        local current_branch
        current_branch="$(git -C "$repo_path" branch --show-current 2>/dev/null)"
        if [ -n "$current_branch" ]; then
            if [ "$current_branch" = "$target_branch" ]; then
                log_success "  既に ${target_branch} です"
                RESULTS["$repo"]="OK: 変更なし"
                continue
            fi
            log_info "  ${current_branch} → ${target_branch}"
        fi

        # git checkout
        local checkout_output
        if checkout_output=$(LC_ALL=C git -C "$repo_path" checkout "$target_branch" 2>&1); then
            log_success "  ${target_branch} にチェックアウトしました"
            RESULTS["$repo"]="OK: ${target_branch}"
        else
            log_error "  チェックアウトに失敗しました"
            echo "$checkout_output" | sed 's/^/    /'
            RESULTS["$repo"]="FAIL: checkout 失敗"
        fi
    done

    # 結果サマリ
    print_summary RESULTS "${repos[@]}"
}
