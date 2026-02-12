#!/bin/bash
#
# cmd_cleanup.sh - cleanup サブコマンド
#

cmd_cleanup_usage() {
    echo -e "${BOLD}worktree cleanup${NC} - worktree を一括削除"
    echo ""
    echo -e "${BOLD}USAGE:${NC}"
    echo "    worktree cleanup [task-name] [OPTIONS]"
    echo ""
    echo -e "${BOLD}OPTIONS:${NC}"
    echo "    --merged              マージ済みタスクを自動検出して削除"
    echo "    --delete-branches     worktree と共にブランチも削除"
    echo "    --dry-run             実際の削除は行わず対象を表示"
    echo "    --force               確認プロンプトなしで削除"
    echo "    -h, --help            ヘルプを表示"
    echo ""
    echo -e "${BOLD}ALIASES:${NC}"
    echo "    worktree clean, worktree rm"
    echo ""
    echo -e "${BOLD}EXAMPLES:${NC}"
    echo "    worktree cleanup feature-login --force --delete-branches"
    echo "    worktree cleanup --merged --dry-run"
    echo "    worktree cleanup --merged --force --delete-branches"
}

cmd_cleanup() {
    local task_name=""
    local merged_only=false
    local delete_branches=false
    local dry_run=false
    local force=false

    # オプション解析
    while [ $# -gt 0 ]; do
        case "$1" in
            --merged)
                merged_only=true
                ;;
            --delete-branches)
                delete_branches=true
                ;;
            --dry-run)
                dry_run=true
                ;;
            --force)
                force=true
                ;;
            -h|--help)
                cmd_cleanup_usage
                return 0
                ;;
            -*)
                log_error "不明なオプション: $1"
                cmd_cleanup_usage
                return 1
                ;;
            *)
                if [ -z "$task_name" ]; then
                    task_name="$1"
                else
                    log_error "タスク名が複数指定されています"
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
    local worktrees_base
    worktrees_base="$(get_worktrees_base)"

    if [ ! -d "$worktrees_base" ]; then
        log_info "worktree はありません"
        return 0
    fi

    # 削除対象のタスクを決定
    local tasks_to_clean=()

    if [ -n "$task_name" ]; then
        # タスク名が指定された場合
        local task_dir="${worktrees_base}/${task_name}"
        if [ ! -d "$task_dir" ]; then
            log_error "タスクが見つかりません: ${task_name}"
            return 1
        fi
        tasks_to_clean+=("$task_name")
    elif [ "$merged_only" = true ]; then
        # マージ済みタスクを自動検出
        for task_dir in "$worktrees_base"/*/; do
            [ -d "$task_dir" ] || continue
            task_dir="${task_dir%/}"
            local tn
            tn="$(basename "$task_dir")"

            if is_task_merged "$task_dir" "$project_root"; then
                tasks_to_clean+=("$tn")
            fi
        done

        if [ ${#tasks_to_clean[@]} -eq 0 ]; then
            log_info "マージ済みのタスクはありません"
            return 0
        fi
    else
        log_error "タスク名または --merged を指定してください"
        cmd_cleanup_usage
        return 1
    fi

    echo ""
    echo "============================================"
    echo -e " ${BOLD}worktree cleanup${NC}"
    echo "============================================"
    echo ""

    if [ "$dry_run" = true ]; then
        log_warn "ドライランモード: 実際の削除は行いません"
        echo ""
    fi

    log_info "削除対象タスク (${#tasks_to_clean[@]}): ${tasks_to_clean[*]}"
    echo ""

    # 各タスクを処理
    for tn in "${tasks_to_clean[@]}"; do
        cleanup_task "$tn" "$project_root" "$worktrees_base" "$delete_branches" "$dry_run" "$force"
    done
}

# タスクがマージ済みかどうかを判定
# タスク内の全リポジトリのブランチがデフォルトブランチにマージされていれば true
is_task_merged() {
    local task_dir="$1"
    local project_root="$2"

    for repo_dir in "$task_dir"/*/; do
        [ -d "$repo_dir" ] || continue
        repo_dir="${repo_dir%/}"

        # git リポジトリかどうか確認
        if [ ! -d "$repo_dir/.git" ] && [ ! -f "$repo_dir/.git" ]; then
            continue
        fi

        local repo_name
        repo_name="$(basename "$repo_dir")"
        local main_repo="${project_root}/${repo_name}"

        if [ ! -d "$main_repo" ]; then
            continue
        fi

        local branch
        branch="$(git -C "$repo_dir" branch --show-current 2>/dev/null)"
        if [ -z "$branch" ]; then
            continue
        fi

        local default_branch
        default_branch="$(detect_default_branch "$main_repo" 2>/dev/null)" || continue

        # ブランチがデフォルトブランチにマージされているか確認
        if ! git -C "$main_repo" branch --merged "origin/${default_branch}" 2>/dev/null | grep -qw "$branch"; then
            return 1
        fi
    done

    return 0
}

# 個別タスクの削除処理
cleanup_task() {
    local task_name="$1"
    local project_root="$2"
    local worktrees_base="$3"
    local delete_branches="$4"
    local dry_run="$5"
    local force="$6"
    local task_dir="${worktrees_base}/${task_name}"

    echo "------------------------------------------"
    log_info "タスク: ${task_name}"

    # 未コミット変更の確認
    local has_changes=false
    for repo_dir in "$task_dir"/*/; do
        [ -d "$repo_dir" ] || continue
        repo_dir="${repo_dir%/}"
        if [ ! -d "$repo_dir/.git" ] && [ ! -f "$repo_dir/.git" ]; then
            continue
        fi
        if ! git -C "$repo_dir" diff --quiet 2>/dev/null || ! git -C "$repo_dir" diff --cached --quiet 2>/dev/null; then
            has_changes=true
            local rn
            rn="$(basename "$repo_dir")"
            log_warn "  ${rn}: 未コミットの変更があります"
        fi
    done

    if [ "$has_changes" = true ] && [ "$force" = false ]; then
        log_warn "未コミット変更があります。--force で強制削除できます。"
        return 1
    fi

    # 確認プロンプト
    if [ "$force" = false ] && [ "$dry_run" = false ]; then
        echo ""
        read -rp "タスク '${task_name}' を削除しますか？ [y/N] " answer
        if [[ ! "$answer" =~ ^[yY]$ ]]; then
            log_info "スキップしました"
            return 0
        fi
    fi

    # 結果格納
    declare -A RESULTS
    local repo_names=()

    # 各リポジトリの worktree を削除
    for repo_dir in "$task_dir"/*/; do
        [ -d "$repo_dir" ] || continue
        repo_dir="${repo_dir%/}"

        # git リポジトリかどうか確認
        if [ ! -d "$repo_dir/.git" ] && [ ! -f "$repo_dir/.git" ]; then
            continue
        fi

        local repo_name
        repo_name="$(basename "$repo_dir")"
        local main_repo="${project_root}/${repo_name}"
        repo_names+=("$repo_name")

        local branch
        branch="$(git -C "$repo_dir" branch --show-current 2>/dev/null)"

        if [ "$dry_run" = true ]; then
            log_info "  [DRY RUN] worktree 削除: ${repo_name} (branch: ${branch})"
            if [ "$delete_branches" = true ]; then
                log_info "  [DRY RUN] ブランチ削除: ${branch}"
            fi
            RESULTS["$repo_name"]="OK: dry-run"
            continue
        fi

        # worktree を削除
        if [ -d "$main_repo" ]; then
            if git -C "$main_repo" worktree remove "$repo_dir" --force 2>&1; then
                log_success "  worktree を削除しました: ${repo_name}"
                RESULTS["$repo_name"]="OK: worktree removed"
            else
                log_error "  worktree の削除に失敗しました: ${repo_name}"
                RESULTS["$repo_name"]="FAIL: worktree 削除失敗"
                continue
            fi

            # ブランチを削除
            if [ "$delete_branches" = true ] && [ -n "$branch" ]; then
                if git -C "$main_repo" branch -D "$branch" 2>&1; then
                    log_success "  ブランチを削除しました: ${branch}"
                    RESULTS["$repo_name"]="OK: worktree + branch removed"
                else
                    log_warn "  ブランチの削除に失敗しました: ${branch}"
                    RESULTS["$repo_name"]="OK: worktree removed (branch 削除失敗)"
                fi
            fi
        fi
    done

    # タスクディレクトリを削除
    if [ "$dry_run" = false ]; then
        rm -rf "$task_dir"
        log_success "タスクディレクトリを削除しました: ${task_dir}"

        # ベースディレクトリが空なら削除
        if [ -d "$worktrees_base" ] && [ -z "$(ls -A "$worktrees_base")" ]; then
            rmdir "$worktrees_base"
            log_info "空の worktrees ディレクトリを削除しました: ${worktrees_base}"
        fi
    else
        log_info "[DRY RUN] タスクディレクトリ削除: ${task_dir}"
    fi

    if [ ${#repo_names[@]} -gt 0 ]; then
        print_summary RESULTS "${repo_names[@]}"
    fi
}
