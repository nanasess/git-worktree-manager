#!/bin/bash
#
# cmd_checkout.sh - checkout subcommand
#

cmd_checkout_usage() {
    echo -e "${BOLD}worktree checkout${NC} - Checkout a branch on all repositories"
    echo ""
    echo -e "${BOLD}USAGE:${NC}"
    echo "    worktree checkout [BRANCH] [OPTIONS]"
    echo ""
    echo -e "${BOLD}ARGUMENTS:${NC}"
    echo "    BRANCH    Branch to checkout (default: each repo's default branch)"
    echo ""
    echo -e "${BOLD}OPTIONS:${NC}"
    echo "    -h, --help    Show help"
    echo ""
    echo -e "${BOLD}EXAMPLES:${NC}"
    echo "    cd ~/git-repos/EcAuth && worktree checkout"
    echo "    cd ~/git-repos/EcAuth && worktree checkout main"
    echo "    cd ~/git-repos/EcAuth && worktree checkout develop"
}

cmd_checkout() {
    local branch=""

    # Parse options
    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help)
                cmd_checkout_usage
                return 0
                ;;
            -*)
                log_error "Unknown option: $1"
                cmd_checkout_usage
                return 1
                ;;
            *)
                if [ -z "$branch" ]; then
                    branch="$1"
                else
                    log_error "Unknown argument: $1"
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

    # List git repositories
    local repos_str
    repos_str="$(list_git_repos)"
    read -ra repos <<< "$repos_str"

    if [ ${#repos[@]} -eq 0 ]; then
        log_error "No git repositories found: ${project_root}"
        return 1
    fi

    local target_desc
    if [ -n "$branch" ]; then
        target_desc="$branch"
    else
        target_desc="default branch"
    fi

    echo ""
    echo "============================================"
    echo -e " ${BOLD}worktree checkout${NC}: ${project_name}"
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
    log_info "Checkout target: ${target_desc}"
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

        # Determine target branch
        local target_branch
        if [ -n "$branch" ]; then
            target_branch="$branch"
        else
            target_branch="$(detect_default_branch "$repo_path")" || {
                log_error "  Failed to detect default branch"
                RESULTS["$display_name"]="FAIL: branch detection failed"
                continue
            }
        fi

        # Show current branch
        local current_branch
        current_branch="$(git -C "$repo_path" branch --show-current 2>/dev/null)"
        if [ -n "$current_branch" ]; then
            if [ "$current_branch" = "$target_branch" ]; then
                log_success "  Already on ${target_branch}"
                RESULTS["$display_name"]="OK: no change"
                continue
            fi
            log_info "  ${current_branch} -> ${target_branch}"
        fi

        # git checkout
        local checkout_output
        if checkout_output=$(LC_ALL=C git -C "$repo_path" checkout "$target_branch" 2>&1); then
            log_success "  Checked out ${target_branch}"
            RESULTS["$display_name"]="OK: ${target_branch}"
        else
            log_error "  Checkout failed"
            echo "$checkout_output" | sed 's/^/    /'
            RESULTS["$display_name"]="FAIL: checkout failed"
        fi
    done

    # Result summary
    print_summary RESULTS "${display_repos[@]}"
}
