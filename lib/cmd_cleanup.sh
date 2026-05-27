#!/bin/bash
#
# cmd_cleanup.sh - cleanup subcommand
#

# Reject task names that could escape the worktrees base.
# A valid task name corresponds to a git branch name; `git check-ref-format`
# already forbids `..` and leading `.` in branch components, so this filter
# does not false-positive on legitimate worktree task names — but it does
# stop accidental (`echo .. | worktree cleanup`) and malicious (a calling
# script feeding untrusted strings) inputs from reaching `rm -rf "$task_dir"`.
#
# We avoid `realpath` because BSD realpath (macOS default) lacks `-m`
# (missing-path) support; the case-pattern approach is portable across
# WSL2 / Ubuntu / macOS without coreutils.
validate_task_name() {
    local name="$1"
    [ -z "$name" ] && return 1
    case "$name" in
        # Absolute path, anywhere containing `..`, bare `.`, leading `./`,
        # or trailing `/.` — all of these would resolve outside or onto
        # the worktrees base itself.
        /*|*..*|.|./*|*/.) return 1 ;;
    esac
    return 0
}

cmd_cleanup_usage() {
    echo -e "${BOLD}worktree cleanup${NC} - Remove worktrees"
    echo ""
    echo -e "${BOLD}USAGE:${NC}"
    echo "    worktree cleanup [task-name] [OPTIONS]"
    echo "    <task-name-source> | worktree cleanup [OPTIONS]"
    echo ""
    echo -e "${BOLD}OPTIONS:${NC}"
    echo "    --merged              Auto-detect and remove merged tasks"
    echo "    --delete-branches     Delete branches along with worktrees"
    echo "    --dry-run             Show targets without actually deleting"
    echo "    --force               Skip confirmation prompts"
    echo "    -h, --help            Show help"
    echo ""
    echo -e "${BOLD}ALIASES:${NC}"
    echo "    worktree clean, worktree rm"
    echo ""
    echo -e "${BOLD}EXAMPLES:${NC}"
    echo "    worktree cleanup feature-login --force --delete-branches"
    echo "    worktree cleanup --merged --dry-run"
    echo "    worktree cleanup --merged --force --delete-branches"
    echo "    worktree list --merged --names-only | worktree cleanup --force"
}

cmd_cleanup() {
    local task_name=""
    local merged_only=false
    local delete_branches=false
    local dry_run=false
    local force=false

    # Parse options
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
                log_error "Unknown option: $1"
                cmd_cleanup_usage
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

    local project_root
    project_root="$(get_project_root)"
    local project_name
    project_name="$(get_project_name)"
    local worktrees_base
    worktrees_base="$(get_worktrees_base)"

    if [ ! -d "$worktrees_base" ]; then
        log_info "No worktrees found"
        return 0
    fi

    # Determine tasks to clean
    local tasks_to_clean=()

    if [ -n "$task_name" ]; then
        if ! validate_task_name "$task_name"; then
            log_error "Invalid task name (path traversal not allowed): ${task_name}"
            return 1
        fi
        local task_dir="${worktrees_base}/${task_name}"
        if [ ! -d "$task_dir" ]; then
            log_error "Task not found: ${task_name}"
            return 1
        fi
        tasks_to_clean+=("$task_name")
    elif [ "$merged_only" = true ]; then
        # Auto-detect merged tasks
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
            log_info "No merged tasks found"
            return 0
        fi
    elif [ ! -t 0 ]; then
        # No task name and stdin is a pipe / redirect: read task names from it.
        # This enables `worktree list --merged --names-only | worktree cleanup`.
        # Slash-containing names (e.g. feature/login) are supported because
        # `read -r` preserves the line verbatim.
        local line
        while IFS= read -r line; do
            [ -z "$line" ] && continue
            if ! validate_task_name "$line"; then
                log_warn "Invalid task name (path traversal not allowed), skipping: ${line}"
                continue
            fi
            local task_dir_check="${worktrees_base}/${line}"
            if [ ! -d "$task_dir_check" ]; then
                log_warn "Task not found, skipping: ${line}"
                continue
            fi
            tasks_to_clean+=("$line")
        done

        if [ ${#tasks_to_clean[@]} -eq 0 ]; then
            log_info "No tasks read from stdin"
            return 0
        fi
    else
        log_error "Specify a task name, --merged, or pipe task names via stdin"
        cmd_cleanup_usage
        return 1
    fi

    echo ""
    echo "============================================"
    echo -e " ${BOLD}worktree cleanup${NC}"
    echo "============================================"
    echo ""

    if [ "$dry_run" = true ]; then
        log_warn "Dry run mode: no actual deletions"
        echo ""
    fi

    log_info "Tasks to clean (${#tasks_to_clean[@]}): ${tasks_to_clean[*]}"
    echo ""

    # Process each task
    for tn in "${tasks_to_clean[@]}"; do
        cleanup_task "$tn" "$project_root" "$worktrees_base" "$delete_branches" "$dry_run" "$force"
    done
}

# Check if all branches in a task are merged into the default branch
is_task_merged() {
    local task_dir="$1"
    local project_root="$2"

    local repo_dirs_str
    repo_dirs_str="$(list_task_repo_dirs "$task_dir")"
    [ -z "$repo_dirs_str" ] && return 0

    local repo_dirs
    read -ra repo_dirs <<< "$repo_dirs_str"

    for repo_dir in "${repo_dirs[@]}"; do
        local main_repo
        main_repo="$(get_main_repo_path "$repo_dir" "$task_dir" "$project_root")"

        if [ ! -d "$main_repo" ]; then
            continue
        fi

        local branch
        branch="$(git -C "$repo_dir" branch --show-current 2>/dev/null)"
        if [ -z "$branch" ]; then
            continue
        fi

        local base_info base_remote default_branch
        base_info="$(detect_base_remote_branch "$main_repo" 2>/dev/null)" || continue
        read -r base_remote default_branch <<< "$base_info"

        # Check if branch is merged into the base remote's default branch.
        # In fork workflows we compare against upstream so merges that landed
        # upstream (but haven't been synced to origin yet) are recognized.
        if ! git -C "$main_repo" branch --merged "${base_remote}/${default_branch}" 2>/dev/null | grep -Fqw "$branch"; then
            return 1
        fi
    done

    return 0
}

# Clean up a single task
cleanup_task() {
    local task_name="$1"
    local project_root="$2"
    local worktrees_base="$3"
    local delete_branches="$4"
    local dry_run="$5"
    local force="$6"
    local task_dir="${worktrees_base}/${task_name}"

    echo "------------------------------------------"
    log_info "Task: ${task_name}"

    # Check for uncommitted changes
    local has_changes=false
    local repo_dirs_str
    repo_dirs_str="$(list_task_repo_dirs "$task_dir")"
    local repo_dirs_arr=()
    if [ -n "$repo_dirs_str" ]; then
        read -ra repo_dirs_arr <<< "$repo_dirs_str"
    fi

    for repo_dir in "${repo_dirs_arr[@]}"; do
        # Skip dirty-check for broken worktrees: git diff exits non-zero
        # because the gitdir pointer is stale, which would otherwise be
        # misreported as uncommitted changes.
        if ! git -C "$repo_dir" rev-parse --git-dir >/dev/null 2>&1; then
            continue
        fi
        if ! git -C "$repo_dir" diff --quiet 2>/dev/null || ! git -C "$repo_dir" diff --cached --quiet 2>/dev/null; then
            has_changes=true
            local rn
            if [ "$repo_dir" = "$task_dir" ]; then
                rn="$(get_project_name)"
            else
                rn="$(basename "$repo_dir")"
            fi
            log_warn "  ${rn}: has uncommitted changes"
        fi
    done

    if [ "$has_changes" = true ] && [ "$force" = false ]; then
        log_warn "Uncommitted changes found. Use --force to force delete."
        return 1
    fi

    # Confirmation prompt
    if [ "$force" = false ] && [ "$dry_run" = false ]; then
        echo ""
        read -rp "Delete task '${task_name}'? [y/N] " answer
        if [[ ! "$answer" =~ ^[yY]$ ]]; then
            log_info "Skipped"
            return 0
        fi
    fi

    # Store results
    declare -A RESULTS
    local repo_names=()

    # Remove worktrees
    for repo_dir in "${repo_dirs_arr[@]}"; do
        local repo_name
        if [ "$repo_dir" = "$task_dir" ]; then
            repo_name="$(get_project_name)"
        else
            repo_name="$(basename "$repo_dir")"
        fi
        local main_repo
        main_repo="$(get_main_repo_path "$repo_dir" "$task_dir" "$project_root")"
        repo_names+=("$repo_name")

        # `|| true` keeps `set -e` from aborting when the worktree is broken
        # (stale gitdir pointer makes `git branch --show-current` exit 128).
        # The branch name is then empty and the broken-worktree path below
        # falls back to direct filesystem removal.
        local branch=""
        branch="$(git -C "$repo_dir" branch --show-current 2>/dev/null || true)"

        # A worktree is "broken" when its `.git` pointer no longer resolves
        # (e.g., the main repo moved or the per-worktree gitdir was deleted
        # manually). `git worktree remove` cannot help in that state, so
        # remove the directory directly and best-effort prune the registry.
        local is_broken=false
        if ! git -C "$repo_dir" rev-parse --git-dir >/dev/null 2>&1; then
            is_broken=true
        fi

        if [ "$dry_run" = true ]; then
            log_info "  [DRY RUN] Remove worktree: ${repo_name} (branch: ${branch:-?})"
            if [ "$delete_branches" = true ] && [ -n "$branch" ]; then
                log_info "  [DRY RUN] Delete branch: ${branch}"
            fi
            RESULTS["$repo_name"]="OK: dry-run"
            continue
        fi

        if [ "$is_broken" = true ]; then
            log_warn "  ${repo_name}: broken worktree — removing directly"
            rm -rf "$repo_dir"
            if [ -d "$main_repo" ]; then
                git -C "$main_repo" worktree prune 2>/dev/null || true
            fi
            log_success "  Removed broken worktree: ${repo_name}"
            RESULTS["$repo_name"]="OK: broken worktree removed"
            continue
        fi

        # Remove worktree
        if [ -d "$main_repo" ]; then
            if git -C "$main_repo" worktree remove "$repo_dir" --force 2>&1; then
                log_success "  Removed worktree: ${repo_name}"
                RESULTS["$repo_name"]="OK: worktree removed"
            else
                log_error "  Failed to remove worktree: ${repo_name}"
                RESULTS["$repo_name"]="FAIL: worktree removal failed"
                continue
            fi

            # Delete branch
            if [ "$delete_branches" = true ] && [ -n "$branch" ]; then
                if git -C "$main_repo" branch -D "$branch" 2>&1; then
                    log_success "  Deleted branch: ${branch}"
                    RESULTS["$repo_name"]="OK: worktree + branch removed"
                else
                    log_warn "  Failed to delete branch: ${branch}"
                    RESULTS["$repo_name"]="OK: worktree removed (branch deletion failed)"
                fi
            fi
        else
            # Main repo is gone — there is nothing to register-prune against,
            # so just delete the orphan worktree directory.
            log_warn "  ${repo_name}: main repo missing at ${main_repo} — removing directory only"
            rm -rf "$repo_dir"
            RESULTS["$repo_name"]="OK: orphan worktree removed"
        fi
    done

    # Remove task directory (only if all worktree removals succeeded)
    if [ "$dry_run" = false ]; then
        local has_failure=false
        for rn in "${repo_names[@]}"; do
            if [[ "${RESULTS[$rn]:-}" == FAIL:* ]]; then
                has_failure=true
                break
            fi
        done

        if [ "$has_failure" = true ]; then
            log_warn "Skipped task directory removal due to worktree removal failures"
        else
            rm -rf "$task_dir"
            log_success "Removed task directory: ${task_dir}"

            # Remove empty worktrees base directory
            if [ -d "$worktrees_base" ] && [ -z "$(ls -A "$worktrees_base")" ]; then
                rmdir "$worktrees_base"
                log_info "Removed empty worktrees directory: ${worktrees_base}"
            fi
        fi
    else
        log_info "[DRY RUN] Remove task directory: ${task_dir}"
    fi

    if [ ${#repo_names[@]} -gt 0 ]; then
        print_summary RESULTS "${repo_names[@]}"
    fi
}
