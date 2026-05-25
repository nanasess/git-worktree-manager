#!/bin/bash
#
# cmd_list.sh - list subcommand
#

cmd_list_usage() {
    echo -e "${BOLD}worktree list${NC} - List current worktrees"
    echo ""
    echo -e "${BOLD}USAGE:${NC}"
    echo "    worktree list [OPTIONS]"
    echo ""
    echo -e "${BOLD}OPTIONS:${NC}"
    echo "    -h, --help    Show help"
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
                log_error "Unknown option: $1"
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
    echo -e "${BOLD}${project_name}${NC} worktrees"
    echo "============================================"

    if [ ! -d "$worktrees_base" ]; then
        log_info "No worktrees found"
        echo ""
        return 0
    fi

    # Search for git worktrees under worktrees_base.
    # Supports slash in task names (e.g., feature/task-name).
    # Uses mindepth 2 for single repo support (.git at depth 2).
    local task_names=()
    while IFS= read -r git_marker; do
        # git_marker is one of:
        #   Multi repo: <worktrees_base>/<task_name>/<repo>/.git
        #   Single repo: <worktrees_base>/<task_name>/.git
        local repo_dir="${git_marker%/*}"
        local relative="${repo_dir#"$worktrees_base"/}"

        # Extract task name based on repo type
        local task_name
        if is_single_repo; then
            task_name="$relative"
        else
            task_name="${relative%/*}"
        fi

        # Dedup
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
        log_info "No worktrees found"
    fi

    for task_name in "${task_names[@]}"; do
        local task_dir="${worktrees_base}/${task_name}"

        echo ""
        echo -e "  ${BOLD}${task_name}${NC}"
        echo "  ------------------------------------------"

        # List repositories in the task directory (single and multi repo)
        local repo_dirs_str
        repo_dirs_str="$(list_task_repo_dirs "$task_dir")"
        if [ -n "$repo_dirs_str" ]; then
            read -ra repo_dirs <<< "$repo_dirs_str"
            for repo_dir in "${repo_dirs[@]}"; do
                local repo_name
                if [ "$repo_dir" = "$task_dir" ]; then
                    # Single repo: show project name
                    repo_name="$(get_project_name)"
                else
                    repo_name="$(basename "$repo_dir")"
                fi

                # Detect broken worktrees (e.g., stale .git gitdir pointer)
                # to avoid misleading "?" branch / "[modified]" labels and to
                # keep `set -e` from aborting the loop later.
                if ! git -C "$repo_dir" rev-parse --git-dir >/dev/null 2>&1; then
                    echo -e "    ${repo_name}: ${RED}[broken worktree]${NC}"
                    continue
                fi

                local branch
                branch="$(git -C "$repo_dir" branch --show-current 2>/dev/null || echo "?")"

                # Check for modifications
                local status_icon=""
                if ! git -C "$repo_dir" diff --quiet 2>/dev/null || ! git -C "$repo_dir" diff --cached --quiet 2>/dev/null; then
                    status_icon=" ${YELLOW}[modified]${NC}"
                fi

                # Check for untracked files.
                # `|| ls_files_rc=$?` keeps `set -euo pipefail` from aborting
                # when git fails; PIPESTATUS is not preserved across `|| true`,
                # so we capture the rc directly. rc=141 means head -n 1 closed
                # the pipe (SIGPIPE'd git) — the captured first line is valid.
                local untracked="" ls_files_rc=0
                untracked=$(git -C "$repo_dir" ls-files --others --exclude-standard 2>/dev/null | head -n 1) || ls_files_rc=$?
                if [ "$ls_files_rc" -ne 0 ] && [ "$ls_files_rc" -ne 141 ]; then
                    untracked=""
                fi
                if [ -n "$untracked" ]; then
                    status_icon="${status_icon} ${YELLOW}[untracked]${NC}"
                fi

                echo -e "    ${repo_name}: ${GREEN}${branch}${NC}${status_icon}"
            done
        fi
    done

    echo ""
    return 0
}
