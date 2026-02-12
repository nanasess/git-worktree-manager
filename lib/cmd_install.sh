#!/bin/bash
#
# cmd_install.sh - install サブコマンド
#

cmd_install_usage() {
    echo -e "${BOLD}worktree install${NC} - Claude Code skills をインストール"
    echo ""
    echo -e "${BOLD}USAGE:${NC}"
    echo "    worktree install --skills [OPTIONS]"
    echo ""
    echo -e "${BOLD}OPTIONS:${NC}"
    echo "    --skills              Claude Code skills をプロジェクトにインストール"
    echo "    --global              ~/.claude/skills/ にインストール（全プロジェクト共通）"
    echo "    -h, --help            ヘルプを表示"
    echo ""
    echo -e "${BOLD}EXAMPLES:${NC}"
    echo "    worktree install --skills            # .claude/skills/ にインストール"
    echo "    worktree install --skills --global   # ~/.claude/skills/ にインストール"
}

cmd_install() {
    local install_skills=false
    local global=false

    while [ $# -gt 0 ]; do
        case "$1" in
            --skills)
                install_skills=true
                ;;
            --global)
                global=true
                ;;
            -h|--help)
                cmd_install_usage
                return 0
                ;;
            *)
                log_error "不明なオプション: $1"
                cmd_install_usage
                return 1
                ;;
        esac
        shift
    done

    if [ "$install_skills" = false ]; then
        log_error "--skills を指定してください"
        cmd_install_usage
        return 1
    fi

    local skills_src="$SCRIPT_DIR/skills"
    local target_dir

    if [ "$global" = true ]; then
        target_dir="$HOME/.claude/skills"
    else
        target_dir="$(pwd)/.claude/skills"
    fi

    if [ ! -d "$skills_src" ]; then
        log_error "skills ディレクトリが見つかりません: $skills_src"
        return 1
    fi

    echo ""
    echo "============================================"
    echo -e " ${BOLD}worktree install --skills${NC}"
    echo "============================================"
    echo ""
    log_info "インストール元: ${skills_src}"
    log_info "インストール先: ${target_dir}"
    echo ""

    local installed=0
    mkdir -p "$target_dir"

    for skill_dir in "$skills_src"/*/; do
        [ -d "$skill_dir" ] || continue
        local skill_name
        skill_name="$(basename "$skill_dir")"
        local dest="${target_dir}/${skill_name}"

        local msg_verb="インストールしました"
        if [ -d "$dest" ]; then
            # 既存のスキルを更新
            rm -rf "$dest"
            msg_verb="更新しました"
        fi
        cp -r "$skill_dir" "$dest"
        log_success "${skill_name}: ${msg_verb}"
        installed=$((installed + 1))
    done

    echo ""
    if [ "$installed" -gt 0 ]; then
        log_success "${installed} 個の skills をインストールしました"
        echo ""
        echo "利用可能なスキル:"
        echo "  /worktree-create <task-name>   worktree を一括作成"
        echo "  /worktree-list                 worktree 一覧を表示"
        echo "  /worktree-cleanup <task-name>  worktree を一括削除"
    else
        log_warn "インストール可能な skills がありません"
    fi
    echo ""
}
