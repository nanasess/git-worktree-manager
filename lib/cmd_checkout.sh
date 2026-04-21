#!/bin/bash
#
# cmd_checkout.sh - checkout subcommand
#

cmd_checkout_usage() {
    echo -e "${BOLD}worktree checkout${NC} - Checkout a branch, or create a worktree from a GitHub URL"
    echo ""
    echo -e "${BOLD}USAGE:${NC}"
    echo "    worktree checkout [BRANCH|URL] [OPTIONS]"
    echo ""
    echo -e "${BOLD}ARGUMENTS:${NC}"
    echo "    BRANCH    Branch to checkout (default: each repo's default branch)"
    echo "    URL       GitHub issue or PR URL — creates a worktree for it"
    echo "              https://github.com/<owner>/<repo>/issues/<number>"
    echo "              https://github.com/<owner>/<repo>/pull/<number>"
    echo ""
    echo -e "${BOLD}OPTIONS:${NC}"
    echo "    --no-install  (URL mode) Skip automatic dependency installation"
    echo "    -h, --help    Show help"
    echo ""
    echo -e "${BOLD}EXAMPLES:${NC}"
    echo "    worktree checkout                                              # default branch"
    echo "    worktree checkout develop                                      # specific branch"
    echo "    worktree checkout https://github.com/owner/repo/issues/42      # issue worktree"
    echo "    worktree checkout https://github.com/owner/repo/pull/123       # PR worktree"
}

# Parse a GitHub issue or PR URL.
# Stdout on success: "<owner> <repo> <kind> <number>" (kind: issues|pull)
# Returns 1 on no match.
parse_github_url() {
    local url="$1"
    local re='^https://github\.com/([^/]+)/([^/]+)/(issues|pull)/([0-9]+)(/.*)?$'
    if [[ "$url" =~ $re ]]; then
        echo "${BASH_REMATCH[1]} ${BASH_REMATCH[2]} ${BASH_REMATCH[3]} ${BASH_REMATCH[4]}"
        return 0
    fi
    return 1
}

# Find the sub-repository in the current project whose origin URL matches
# <owner>/<repo>. Outputs the repo name ("." for single repo). Returns 1 if none.
find_repo_by_remote() {
    local owner="$1"
    local repo="$2"
    local project_root="$3"

    local repos_str
    repos_str="$(list_git_repos)"
    read -ra repos <<< "$repos_str"

    local re='github\.com[:/]+([^/]+)/([^/]+)$'
    for r in "${repos[@]}"; do
        local path="$project_root"
        [ "$r" != "." ] && path="${project_root}/${r}"
        local origin_url
        origin_url="$(git -C "$path" remote get-url origin 2>/dev/null)" || continue
        # Strip trailing slash and .git suffix before matching
        origin_url="${origin_url%/}"
        origin_url="${origin_url%.git}"
        if [[ "$origin_url" =~ $re ]]; then
            if [ "${BASH_REMATCH[1]}" = "$owner" ] && [ "${BASH_REMATCH[2]}" = "$repo" ]; then
                echo "$r"
                return 0
            fi
        fi
    done
    return 1
}

# Dispatch URL-mode checkout.
# $1: url, remaining args: passthrough options for cmd_create (e.g., --no-install)
cmd_checkout_url() {
    local url="$1"
    shift

    local parsed
    parsed="$(parse_github_url "$url")" || {
        log_error "Invalid GitHub URL: $url"
        log_error "Expected: https://github.com/<owner>/<repo>/(issues|pull)/<number>"
        return 1
    }
    local owner repo kind number
    read -r owner repo kind number <<< "$parsed"

    case "$kind" in
        issues) cmd_checkout_issue "$owner" "$repo" "$number" "$@" ;;
        pull)   cmd_checkout_pr "$owner" "$repo" "$number" "$@" ;;
    esac
}

cmd_checkout_issue() {
    local owner="$1"
    local repo="$2"
    local number="$3"
    shift 3

    if command -v gh >/dev/null 2>&1; then
        log_info "Verifying issue #${number} in ${owner}/${repo}..."
        if ! gh issue view "$number" --repo "${owner}/${repo}" --json number >/dev/null 2>&1; then
            log_warn "gh could not verify the issue (missing auth or network issue) — proceeding without verification"
        fi
    else
        log_warn "gh CLI not found — skipping issue verification"
    fi

    local task_name="issue-${number}"
    log_info "Creating worktree for issue #${number} (task: ${task_name})"
    cmd_create "$task_name" "$@"
}

cmd_checkout_pr() {
    local owner="$1"
    local repo="$2"
    local pr_number="$3"
    shift 3

    # Parse passthrough options
    local no_install=false
    while [ $# -gt 0 ]; do
        case "$1" in
            --no-install) no_install=true ;;
            --branch-prefix) shift ;; # ignored for PR mode
        esac
        shift
    done

    local head_ref=""
    if command -v gh >/dev/null 2>&1; then
        log_info "Fetching PR #${pr_number} info from ${owner}/${repo}..."
        head_ref="$(gh pr view "$pr_number" --repo "${owner}/${repo}" --json headRefName --jq .headRefName 2>/dev/null || true)"
    fi
    if [ -z "$head_ref" ]; then
        head_ref="pr-${pr_number}"
        log_warn "gh unavailable or unable to query the PR — using fallback branch name '${head_ref}'"
    fi

    local project_root project_name
    project_root="$(get_project_root)"
    project_name="$(get_project_name)"

    local matching_repo
    matching_repo="$(find_repo_by_remote "$owner" "$repo" "$project_root")" || {
        log_error "No repository in ${project_root} matches ${owner}/${repo}"
        log_error "Run 'worktree checkout' from a project whose clone points at ${owner}/${repo}"
        return 1
    }

    local task_name="pr-${pr_number}"
    local task_dir
    task_dir="$(get_task_dir "$task_name")"

    local matching_repo_path="$project_root"
    [ "$matching_repo" != "." ] && matching_repo_path="${project_root}/${matching_repo}"

    local matching_repo_display="$matching_repo"
    [ "$matching_repo" = "." ] && matching_repo_display="$project_name"

    echo ""
    echo "============================================"
    echo -e " ${BOLD}worktree checkout${NC}: PR #${pr_number}"
    echo "============================================"
    echo ""
    log_info "Project: ${project_name} (${project_root})"
    log_info "PR: ${owner}/${repo}#${pr_number}"
    log_info "PR branch: ${head_ref}"
    log_info "Target repo: ${matching_repo_display}"
    log_info "Task directory: ${task_dir}"
    echo ""

    if [ -d "$task_dir" ]; then
        log_error "Task directory already exists: ${task_dir}"
        return 1
    fi

    # Fetch PR head into a local branch named after the PR branch
    if git -C "$matching_repo_path" rev-parse --verify "$head_ref" >/dev/null 2>&1; then
        log_warn "Local branch ${head_ref} already exists — reusing"
    else
        log_info "Fetching PR #${pr_number} head (${head_ref})..."
        if ! git -C "$matching_repo_path" fetch origin "pull/${pr_number}/head:${head_ref}" 2>&1; then
            log_error "Failed to fetch PR #${pr_number}"
            return 1
        fi
    fi

    # Determine worktree path
    local worktree_path
    if [ "$matching_repo" = "." ]; then
        worktree_path="$task_dir"
    else
        mkdir -p "$task_dir"
        worktree_path="${task_dir}/${matching_repo}"
    fi

    log_info "Creating worktree at ${worktree_path}..."
    if ! git -C "$matching_repo_path" worktree add "$worktree_path" "$head_ref" 2>&1; then
        log_error "Failed to create worktree"
        return 1
    fi
    log_success "Created worktree: ${worktree_path}"

    # Symlinks (multi-repo) and CLAUDE.md with worktree context
    if [ "$matching_repo" != "." ]; then
        log_info "Creating symlinks..."
        local items_str
        items_str="$(list_non_git_items)"
        if [ -n "$items_str" ]; then
            read -ra items <<< "$items_str"
            for item in "${items[@]}"; do
                local src="${project_root}/${item}"
                local dst="${task_dir}/${item}"
                [ -e "$dst" ] && continue
                if [ "$item" = "CLAUDE.md" ]; then
                    generate_worktree_claude_md "$src" "$dst" "$task_name" "$task_dir" "$project_root"
                    log_info "  ${item} -> generated (with worktree context)"
                else
                    ln -sf "$src" "$dst"
                    log_info "  ${item} -> ${src}"
                fi
            done
        fi
    else
        local claude_md_src="${project_root}/CLAUDE.md"
        if [ -f "$claude_md_src" ]; then
            local claude_md_dst="${task_dir}/CLAUDE.md"
            generate_worktree_claude_md "$claude_md_src" "$claude_md_dst" "$task_name" "$task_dir" "$project_root"
            log_info "  CLAUDE.md -> generated (with worktree context)"
        fi
    fi

    # .worktreerc hook
    local worktreerc="${project_root}/.worktreerc"
    if [ -f "$worktreerc" ]; then
        echo ""
        log_info "Executing .worktreerc hook..."
        (
            export WORKTREE_TASK_NAME="$task_name"
            export WORKTREE_TASK_DIR="$task_dir"
            export WORKTREE_PROJECT_ROOT="$project_root"
            cd "$task_dir"
            source "$worktreerc"
            if type post_create &>/dev/null; then
                post_create
                log_success "post_create hook executed"
            fi
        )
    fi

    # Dependency installation
    if [ "$no_install" = false ]; then
        local deps_type
        deps_type="$(detect_deps_type "$worktree_path")"
        if [ -n "$deps_type" ]; then
            echo ""
            log_info "Installing dependencies..."
            log_info "${matching_repo_display} (${deps_type}):"
            install_deps "$worktree_path" || true
        fi
    else
        echo ""
        log_info "Skipped dependency installation (--no-install)"
    fi

    echo ""
    log_success "PR #${pr_number} (${head_ref}) checked out at ${worktree_path}"
    echo ""
}

cmd_checkout() {
    local arg=""
    local -a passthrough=()

    # Parse options
    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help)
                cmd_checkout_usage
                return 0
                ;;
            --no-install)
                passthrough+=("$1")
                ;;
            --branch-prefix)
                shift
                passthrough+=("--branch-prefix" "$1")
                ;;
            -*)
                log_error "Unknown option: $1"
                cmd_checkout_usage
                return 1
                ;;
            *)
                if [ -z "$arg" ]; then
                    arg="$1"
                else
                    log_error "Unknown argument: $1"
                    cmd_checkout_usage
                    return 1
                fi
                ;;
        esac
        shift
    done

    # URL mode: dispatch to issue/PR handler (passthrough options go to cmd_create)
    if [[ "$arg" =~ ^https?:// ]]; then
        cmd_checkout_url "$arg" "${passthrough[@]}"
        return $?
    fi

    if [ ${#passthrough[@]} -gt 0 ]; then
        log_error "Options ${passthrough[*]} are only valid with a GitHub URL"
        cmd_checkout_usage
        return 1
    fi

    # Branch mode: existing behavior — checkout a branch on all repos
    local branch="$arg"

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
