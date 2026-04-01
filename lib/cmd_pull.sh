#!/bin/bash
#
# cmd_pull.sh - pull subcommand
#

cmd_pull_usage() {
    echo -e "${BOLD}worktree pull${NC} - Pull all repositories"
    echo ""
    echo -e "${BOLD}USAGE:${NC}"
    echo "    worktree pull [OPTIONS]"
    echo ""
    echo -e "${BOLD}OPTIONS:${NC}"
    echo "    -h, --help    Show help"
    echo ""
    echo -e "${BOLD}EXAMPLES:${NC}"
    echo "    cd ~/git-repos/EcAuth && worktree pull"
    echo "    cd ~/git-repos/EcAuth.worktrees/task-1 && worktree pull"
}

cmd_pull() {
    # Parse options
    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help)
                cmd_pull_usage
                return 0
                ;;
            -*)
                log_error "Unknown option: $1"
                cmd_pull_usage
                return 1
                ;;
            *)
                log_error "Unknown argument: $1"
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

    # List git repositories
    local repos_str
    repos_str="$(list_git_repos)"
    read -ra repos <<< "$repos_str"

    if [ ${#repos[@]} -eq 0 ]; then
        log_error "No git repositories found: ${project_root}"
        return 1
    fi

    echo ""
    echo "============================================"
    echo -e " ${BOLD}worktree pull${NC}: ${project_name}"
    echo "============================================"
    echo ""
    # Display names
    local display_repos=()
    for repo in "${repos[@]}"; do
        if [ "$repo" = "." ]; then
            display_repos+=("$project_name")
        else
            display_repos+=("$repo")
        fi
    done

    log_info "Directory: ${project_root}"
    log_info "Repositories (${#repos[@]}): ${display_repos[*]}"
    echo ""

    # Store results
    declare -A RESULTS

    local i=0
    for repo in "${repos[@]}"; do
        local repo_path="${project_root}/${repo}"
        local display_name="${display_repos[$i]}"
        i=$((i + 1))

        echo "------------------------------------------"
        log_info "Processing: ${display_name}"

        # Show current branch
        local current_branch
        current_branch="$(git -C "$repo_path" branch --show-current 2>/dev/null)"
        if [ -n "$current_branch" ]; then
            log_info "  Branch: ${current_branch}"
        fi

        # git pull
        local pull_output
        if pull_output=$(LC_ALL=C git -C "$repo_path" pull --ff-only 2>&1); then
            if echo "$pull_output" | grep -q "Already up to date"; then
                log_success "  Already up to date"
                RESULTS["$display_name"]="OK: up to date"
            else
                log_success "  Pulled successfully"
                RESULTS["$display_name"]="OK: updated"
            fi
        else
            log_error "  Pull failed"
            echo "$pull_output" | sed 's/^/    /'
            RESULTS["$display_name"]="FAIL: pull failed"
        fi
    done

    # Result summary
    print_summary RESULTS "${display_repos[@]}"
}
