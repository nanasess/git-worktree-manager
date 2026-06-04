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
    echo "    --no-cd                   Do not cd into the new worktree (shell integration)"
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
    local no_cd=false

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
            --no-cd)
                no_cd=true
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
        # Capture PIPESTATUS into a local variable before any other command runs;
        # the next `[` would otherwise overwrite PIPESTATUS with its own status,
        # making the SIGPIPE (141) check evaluate the wrong exit code.
        local fetch_status="${PIPESTATUS[0]}"
        if [ "$fetch_status" -ne 0 ] && [ "$fetch_status" -ne 141 ]; then
            log_warn "  Fetch failed (continuing)"
        fi

        # In fork workflows, also fetch upstream so its default branch is up to date
        if git -C "$repo_path" remote get-url upstream >/dev/null 2>&1; then
            log_info "  git fetch upstream..."
            git -C "$repo_path" fetch upstream 2>&1 | head -n 5
            local upstream_fetch_status="${PIPESTATUS[0]}"
            if [ "$upstream_fetch_status" -ne 0 ] && [ "$upstream_fetch_status" -ne 141 ]; then
                log_warn "  Fetch upstream failed (continuing)"
            fi
        fi

        # Detect base remote (prefers upstream when present) and default branch
        local base_info base_remote default_branch
        base_info="$(detect_base_remote_branch "$repo_path")" || {
            log_error "  Cannot detect default branch"
            RESULTS["$display_name"]="FAIL: default branch detection failed"
            continue
        }
        read -r base_remote default_branch <<< "$base_info"
        log_info "  Base branch: ${base_remote}/${default_branch}"

        # Create worktree
        log_info "  Creating worktree: ${branch_name}"
        if git -C "$repo_path" worktree add -b "$branch_name" "$worktree_path" "${base_remote}/${default_branch}" 2>&1; then
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
                if [ "$item" = "CLAUDE.local.md" ]; then
                    # Copy (not symlink) so the worktree context can be appended
                    # without writing through to the project-root original.
                    cp "$src" "$dst"
                    log_info "  ${item} -> copied (from ${src})"
                else
                    ln -sf "$src" "$dst"
                    log_info "  ${item} -> ${src}"
                fi
            fi
        done
    fi

    # Append worktree context to CLAUDE.local.md (single and multi repo).
    # CLAUDE.md itself is left untouched (tracked copy / symlink to the original).
    local claude_local_dst="${task_dir}/CLAUDE.local.md"
    if ! write_worktree_context "$claude_local_dst" "$task_name" "$task_dir" "$project_root"; then
        log_error "Failed to write worktree context to ${claude_local_dst}"
        return 1
    fi
    log_info "  CLAUDE.local.md -> worktree context written"

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
            local deps_types_csv
            deps_types_csv="$(detect_deps_types "$worktree_path" | paste -sd, -)"
            if [ -n "$deps_types_csv" ]; then
                log_info "${repo} (${deps_types_csv}):"
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

    # Tell the shell-integration wrapper to cd into the new worktree (unless
    # --no-cd). Only when at least one worktree was actually created.
    if [ "$no_cd" = false ] && [ ${#created_repos[@]} -gt 0 ]; then
        write_cd_target "$task_dir"
    fi
    echo ""
}
