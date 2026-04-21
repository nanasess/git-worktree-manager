#!/bin/bash
#
# cmd_create.sh - create subcommand
#

cmd_create_usage() {
    echo -e "${BOLD}worktree create${NC} - Create worktrees for a task"
    echo ""
    echo -e "${BOLD}USAGE:${NC}"
    echo "    worktree create <task-name> [OPTIONS]"
    echo ""
    echo -e "${BOLD}OPTIONS:${NC}"
    echo "    --branch-prefix <prefix>  Add a prefix to branch names"
    echo "    --no-install              Skip automatic dependency installation"
    echo "    -h, --help                Show help"
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

    # Parse options
    while [ $# -gt 0 ]; do
        case "$1" in
            --branch-prefix)
                if [ $# -lt 2 ]; then
                    log_error "--branch-prefix requires a value"
                    cmd_create_usage
                    return 1
                fi
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
                log_error "Unknown option: $1"
                cmd_create_usage
                return 1
                ;;
            *)
                if [ -z "$task_name" ]; then
                    task_name="$1"
                else
                    log_error "Multiple task names specified"
                    return 1
                fi
                ;;
        esac
        shift
    done

    if [ -z "$task_name" ]; then
        log_error "Task name is required"
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
    log_info "Project: ${project_name} (${project_root})"
    log_info "Task directory: ${task_dir}"

    # Error if task directory already exists
    if [ -d "$task_dir" ]; then
        log_error "Task directory already exists: ${task_dir}"
        return 1
    fi

    # List git repositories
    local repos_str
    repos_str="$(list_git_repos)"
    read -ra repos <<< "$repos_str"

    if [ ${#repos[@]} -eq 0 ]; then
        log_error "No git repositories found: ${project_root}"
        return 1
    fi

    # Display names ("." replaced with project name)
    local display_repos=()
    for repo in "${repos[@]}"; do
        if [ "$repo" = "." ]; then
            display_repos+=("$project_name")
        else
            display_repos+=("$repo")
        fi
    done
    log_info "Repositories (${#repos[@]}): ${display_repos[*]}"
    echo ""

    # Create task directory (skip for single repo — git worktree add creates it)
    if ! is_single_repo; then
        mkdir -p "$task_dir"
    fi

    # Store results
    declare -A RESULTS
    local created_repos=()

    # Create worktree for each repository
    for repo in "${repos[@]}"; do
        local repo_path="${project_root}/${repo}"
        local worktree_path
        if [ "$repo" = "." ]; then
            worktree_path="$task_dir"
        else
            worktree_path="${task_dir}/${repo}"
        fi
        local branch_name="${branch_prefix}${task_name}"
        local display_name="$repo"
        [ "$repo" = "." ] && display_name="$project_name"

        echo "------------------------------------------"
        log_info "Processing: ${display_name}"

        # Fetch
        log_info "  git fetch origin..."
        git -C "$repo_path" fetch origin 2>&1 | head -n 5
        if [ "${PIPESTATUS[0]}" -ne 0 ] && [ "${PIPESTATUS[0]}" -ne 141 ]; then
            log_warn "  Fetch failed (continuing)"
        fi

        # Detect default branch
        local default_branch
        default_branch="$(detect_default_branch "$repo_path")" || {
            log_error "  Cannot detect default branch"
            RESULTS["$display_name"]="FAIL: default branch detection failed"
            continue
        }
        log_info "  Base branch: origin/${default_branch}"

        # Create worktree
        log_info "  Creating worktree: ${branch_name}"
        if git -C "$repo_path" worktree add -b "$branch_name" "$worktree_path" "origin/${default_branch}" 2>&1; then
            log_success "  Created worktree: ${worktree_path}"
            RESULTS["$display_name"]="OK: branch=${branch_name}"
            created_repos+=("$repo")
        else
            # If branch already exists, use existing branch
            if git -C "$repo_path" rev-parse --verify "$branch_name" >/dev/null 2>&1; then
                log_warn "  Branch ${branch_name} already exists. Using existing branch."
                if git -C "$repo_path" worktree add "$worktree_path" "$branch_name" 2>&1; then
                    log_success "  Created worktree (existing branch): ${worktree_path}"
                    RESULTS["$display_name"]="OK: branch=${branch_name} (existing)"
                    created_repos+=("$repo")
                else
                    log_error "  Failed to create worktree"
                    RESULTS["$display_name"]="FAIL: worktree creation failed"
                fi
            else
                log_error "  Failed to create worktree"
                RESULTS["$display_name"]="FAIL: worktree creation failed"
            fi
        fi
    done

    echo ""

    # Create symlinks for non-git items
    log_info "Creating symlinks..."
    local items_str
    items_str="$(list_non_git_items)"
    if [ -n "$items_str" ]; then
        read -ra items <<< "$items_str"
        for item in "${items[@]}"; do
            local src="${project_root}/${item}"
            local dst="${task_dir}/${item}"
            if [ ! -e "$dst" ]; then
                if [ "$item" = "CLAUDE.md" ]; then
                    # Generate CLAUDE.md with worktree context
                    generate_worktree_claude_md "$src" "$dst" "$task_name" "$task_dir" "$project_root"
                    log_info "  ${item} -> generated (with worktree context)"
                else
                    ln -sf "$src" "$dst"
                    log_info "  ${item} -> ${src}"
                fi
            fi
        done
    fi

    # Single repo: add worktree context to CLAUDE.md
    if is_single_repo; then
        local claude_md_src="${project_root}/CLAUDE.md"
        if [ -f "$claude_md_src" ]; then
            local claude_md_dst="${task_dir}/CLAUDE.md"
            generate_worktree_claude_md "$claude_md_src" "$claude_md_dst" "$task_name" "$task_dir" "$project_root"
            log_info "  CLAUDE.md -> generated (with worktree context)"
        fi
    fi

    # Copy mise config files (mise.toml, mise.local.toml) for each created worktree.
    # This inherits mise version pinning even when the config is gitignored.
    if [ ${#created_repos[@]} -gt 0 ]; then
        log_info "Copying mise config files..."
        for repo in "${created_repos[@]}"; do
            local repo_src repo_dst
            if [ "$repo" = "." ]; then
                repo_src="$project_root"
                repo_dst="$task_dir"
            else
                repo_src="${project_root}/${repo}"
                repo_dst="${task_dir}/${repo}"
            fi
            copy_mise_configs "$repo_src" "$repo_dst"
        done
    fi

    # Execute .worktreerc hook
    local worktreerc="${project_root}/.worktreerc"
    if [ -f "$worktreerc" ]; then
        echo ""
        log_info "Executing .worktreerc hook..."
        (
            export WORKTREE_TASK_NAME="$task_name"
            export WORKTREE_TASK_DIR="$task_dir"
            export WORKTREE_PROJECT_ROOT="$project_root"
            cd "$task_dir"
            # Load and execute post_create function
            source "$worktreerc"
            if type post_create &>/dev/null; then
                post_create
                log_success "post_create hook executed"
            fi
        )
    fi

    # Install dependencies
    if [ "$no_install" = false ] && [ ${#created_repos[@]} -gt 0 ]; then
        echo ""
        log_info "Installing dependencies..."
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
        log_info "Skipped dependency installation (--no-install)"
    fi

    # Result summary
    print_summary RESULTS "${display_repos[@]}"

    log_success "Task directory: ${task_dir}"
    echo ""
}
