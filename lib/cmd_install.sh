#!/bin/bash
#
# cmd_install.sh - install subcommand
#

cmd_install_usage() {
    echo -e "${BOLD}worktree install${NC} - Install Claude Code skills"
    echo ""
    echo -e "${BOLD}USAGE:${NC}"
    echo "    worktree install --skills [OPTIONS]"
    echo ""
    echo -e "${BOLD}OPTIONS:${NC}"
    echo "    --skills              Install Claude Code skills to project"
    echo "    --global              Install to ~/.claude/skills/ (all projects)"
    echo "    -h, --help            Show help"
    echo ""
    echo -e "${BOLD}EXAMPLES:${NC}"
    echo "    worktree install --skills            # Install to .claude/skills/"
    echo "    worktree install --skills --global   # Install to ~/.claude/skills/"
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
                log_error "Unknown option: $1"
                cmd_install_usage
                return 1
                ;;
        esac
        shift
    done

    if [ "$install_skills" = false ]; then
        log_error "--skills is required"
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
        log_error "Skills directory not found: $skills_src"
        return 1
    fi

    echo ""
    echo "============================================"
    echo -e " ${BOLD}worktree install --skills${NC}"
    echo "============================================"
    echo ""
    log_info "Source: ${skills_src}"
    log_info "Target: ${target_dir}"
    echo ""

    local installed=0
    mkdir -p "$target_dir"

    for skill_dir in "$skills_src"/*/; do
        [ -d "$skill_dir" ] || continue
        local skill_name
        skill_name="$(basename "$skill_dir")"
        local dest="${target_dir}/${skill_name}"

        local msg_verb="installed"
        if [ -d "$dest" ]; then
            rm -rf "$dest"
            msg_verb="updated"
        fi
        cp -r "$skill_dir" "$dest"
        log_success "${skill_name}: ${msg_verb}"
        installed=$((installed + 1))
    done

    echo ""
    if [ "$installed" -gt 0 ]; then
        log_success "${installed} skill(s) installed"
        echo ""
        echo "Available skills:"
        echo "  /worktree-create <task-name>      Create worktrees"
        echo "  /worktree-list                    List worktrees"
        echo "  /worktree-cleanup <task-name>     Cleanup worktrees"
        echo "  /worktree-checkout [branch|URL]   Checkout a branch or create worktree from GitHub URL"
        echo "  /worktree-pull                    Pull all repos"
    else
        log_warn "No skills available to install"
    fi
    echo ""
}
