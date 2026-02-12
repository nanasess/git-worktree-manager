#!/bin/bash
#
# cmd_create.sh - create サブコマンド
#

cmd_create_usage() {
    echo -e "${BOLD}worktree create${NC} - タスク用の worktree を一括作成"
    echo ""
    echo -e "${BOLD}USAGE:${NC}"
    echo "    worktree create <task-name> [OPTIONS]"
    echo ""
    echo -e "${BOLD}OPTIONS:${NC}"
    echo "    --branch-prefix <prefix>  ブランチ名にプレフィックスを付与"
    echo "    --no-install              依存関係の自動インストールをスキップ"
    echo "    -h, --help                ヘルプを表示"
    echo ""
    echo -e "${BOLD}EXAMPLES:${NC}"
    echo "    worktree create feature-login"
    echo "    worktree create fix-bug --branch-prefix nanasess/"
    echo "    worktree create test-task --no-install"
}

cmd_create() {
    local task_name=""
    local branch_prefix=""
    local no_install=false

    # オプション解析
    while [ $# -gt 0 ]; do
        case "$1" in
            --branch-prefix)
                shift
                branch_prefix="$1"
                ;;
            --no-install)
                no_install=true
                ;;
            -h|--help)
                cmd_create_usage
                return 0
                ;;
            -*)
                log_error "不明なオプション: $1"
                cmd_create_usage
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

    if [ -z "$task_name" ]; then
        log_error "タスク名を指定してください"
        cmd_create_usage
        return 1
    fi

    local project_root
    project_root="$(get_project_root)"
    local project_name
    project_name="$(get_project_name)"
    local worktrees_base
    worktrees_base="$(get_worktrees_base)"
    local task_dir
    task_dir="$(get_task_dir "$task_name")"

    echo ""
    echo "============================================"
    echo -e " ${BOLD}worktree create${NC}: ${task_name}"
    echo "============================================"
    echo ""
    log_info "プロジェクト: ${project_name} (${project_root})"
    log_info "タスクディレクトリ: ${task_dir}"

    # タスクディレクトリが既に存在する場合はエラー
    if [ -d "$task_dir" ]; then
        log_error "タスクディレクトリが既に存在します: ${task_dir}"
        return 1
    fi

    # git リポジトリを列挙
    local repos_str
    repos_str="$(list_git_repos)"
    read -ra repos <<< "$repos_str"

    if [ ${#repos[@]} -eq 0 ]; then
        log_error "git リポジトリが見つかりません: ${project_root}"
        return 1
    fi

    log_info "検出されたリポジトリ (${#repos[@]}): ${repos[*]}"
    echo ""

    # タスクディレクトリを作成
    mkdir -p "$task_dir"

    # 結果格納
    declare -A RESULTS
    local created_repos=()

    # 各リポジトリで worktree を作成
    for repo in "${repos[@]}"; do
        local repo_path="${project_root}/${repo}"
        local worktree_path="${task_dir}/${repo}"
        local branch_name="${branch_prefix}${task_name}"

        echo "------------------------------------------"
        log_info "処理中: ${repo}"

        # fetch
        log_info "  git fetch origin..."
        if ! git -C "$repo_path" fetch origin 2>&1 | head -5; then
            log_warn "  fetch に失敗しました（続行します）"
        fi

        # デフォルトブランチを検出
        local default_branch
        default_branch="$(detect_default_branch "$repo_path")" || {
            log_error "  デフォルトブランチを検出できません"
            RESULTS["$repo"]="FAIL: デフォルトブランチ検出失敗"
            continue
        }
        log_info "  ベースブランチ: origin/${default_branch}"

        # worktree add
        log_info "  worktree を作成中: ${branch_name}"
        if git -C "$repo_path" worktree add -b "$branch_name" "$worktree_path" "origin/${default_branch}" 2>&1; then
            log_success "  worktree を作成しました: ${worktree_path}"
            RESULTS["$repo"]="OK: branch=${branch_name}"
            created_repos+=("$repo")
        else
            # ブランチが既に存在する場合は、既存ブランチで worktree を作成
            if git -C "$repo_path" rev-parse --verify "$branch_name" >/dev/null 2>&1; then
                log_warn "  ブランチ ${branch_name} は既に存在します。既存ブランチを使用します。"
                if git -C "$repo_path" worktree add "$worktree_path" "$branch_name" 2>&1; then
                    log_success "  worktree を作成しました（既存ブランチ）: ${worktree_path}"
                    RESULTS["$repo"]="OK: branch=${branch_name} (existing)"
                    created_repos+=("$repo")
                else
                    log_error "  worktree の作成に失敗しました"
                    RESULTS["$repo"]="FAIL: worktree 作成失敗"
                fi
            else
                log_error "  worktree の作成に失敗しました"
                RESULTS["$repo"]="FAIL: worktree 作成失敗"
            fi
        fi
    done

    echo ""

    # 非 git アイテムをシンボリックリンクで配置
    log_info "シンボリックリンクを作成中..."
    local items_str
    items_str="$(list_non_git_items)"
    if [ -n "$items_str" ]; then
        read -ra items <<< "$items_str"
        for item in "${items[@]}"; do
            local src="${project_root}/${item}"
            local dst="${task_dir}/${item}"
            if [ ! -e "$dst" ]; then
                ln -sf "$src" "$dst"
                log_info "  ${item} → ${src}"
            fi
        done
    fi

    # .worktreerc フックを実行
    local worktreerc="${project_root}/.worktreerc"
    if [ -f "$worktreerc" ]; then
        echo ""
        log_info ".worktreerc のフックを実行中..."
        (
            export WORKTREE_TASK_NAME="$task_name"
            export WORKTREE_TASK_DIR="$task_dir"
            export WORKTREE_PROJECT_ROOT="$project_root"
            cd "$task_dir"
            # post_create 関数を読み込んで実行
            source "$worktreerc"
            if type post_create &>/dev/null; then
                post_create
                log_success "post_create フックを実行しました"
            fi
        )
    fi

    # 依存関係のインストール
    if [ "$no_install" = false ] && [ ${#created_repos[@]} -gt 0 ]; then
        echo ""
        log_info "依存関係をインストール中..."
        for repo in "${created_repos[@]}"; do
            local worktree_path="${task_dir}/${repo}"
            local deps_type
            deps_type="$(detect_deps_type "$worktree_path")"
            if [ -n "$deps_type" ]; then
                log_info "${repo} (${deps_type}):"
                install_deps "$worktree_path" || true
            fi
        done
    elif [ "$no_install" = true ]; then
        echo ""
        log_info "依存関係のインストールをスキップしました (--no-install)"
    fi

    # 結果サマリ
    print_summary RESULTS "${repos[@]}"

    log_success "タスクディレクトリ: ${task_dir}"
    echo ""
}
