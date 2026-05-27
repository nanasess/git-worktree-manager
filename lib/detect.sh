#!/bin/bash
#
# detect.sh - Project detection and repository enumeration
#

# Check if the project root itself is a git repository
is_single_repo() {
    local project_root
    project_root="$(get_project_root)"
    [ -d "$project_root/.git" ] || [ -f "$project_root/.git" ]
}

# List git repositories under the project root.
# Single repo: returns "."
# Multi repo: returns subdirectory names
list_git_repos() {
    local project_root
    project_root="$(get_project_root)"

    # Single repo: project_root itself has .git
    if is_single_repo; then
        echo "."
        return
    fi

    # Multi repo: scan immediate subdirectories
    local repos=()
    for dir in "$project_root"/*/; do
        [ -d "$dir" ] || continue
        dir="${dir%/}"
        if [ -d "$dir/.git" ] || [ -f "$dir/.git" ]; then
            repos+=("$(basename "$dir")")
        fi
    done

    echo "${repos[@]}"
}

# List worktree repository directories within a task directory.
# Multi repo: task_dir/repo1, task_dir/repo2, ...
# Single repo: task_dir itself
list_task_repo_dirs() {
    local task_dir="$1"
    local dirs=()

    for repo_dir in "$task_dir"/*/; do
        [ -d "$repo_dir" ] || continue
        repo_dir="${repo_dir%/}"
        if [ -d "$repo_dir/.git" ] || [ -f "$repo_dir/.git" ]; then
            dirs+=("$repo_dir")
        fi
    done

    # Single repo: task_dir itself is the worktree
    if [ ${#dirs[@]} -eq 0 ]; then
        if [ -f "$task_dir/.git" ] || [ -d "$task_dir/.git" ]; then
            dirs+=("$task_dir")
        fi
    fi

    echo "${dirs[@]}"
}

# Get the main (bare) repository path for a given worktree repo directory
get_main_repo_path() {
    local repo_dir="$1"
    local task_dir="$2"
    local project_root="$3"

    if [ "$repo_dir" = "$task_dir" ]; then
        # Single repo: main repo is project_root itself
        echo "$project_root"
    else
        local repo_name
        repo_name="$(basename "$repo_dir")"
        echo "${project_root}/${repo_name}"
    fi
}

# List non-git items under project root (for symlinking).
# Returns empty for single repo (worktree contains all files).
list_non_git_items() {
    # Single repo: worktree contains all files, no symlinks needed
    if is_single_repo; then
        echo ""
        return
    fi

    local project_root
    project_root="$(get_project_root)"
    local items=()

    for item in "$project_root"/*; do
        [ -e "$item" ] || continue
        local name
        name="$(basename "$item")"

        # Skip directories that are git repositories
        if [ -d "$item" ]; then
            if [ -d "$item/.git" ] || [ -f "$item/.git" ]; then
                continue
            fi
        fi

        items+=("$name")
    done

    # Include dotfiles
    for item in "$project_root"/.*; do
        [ -e "$item" ] || continue
        local name
        name="$(basename "$item")"
        # Skip . and ..
        [ "$name" = "." ] || [ "$name" = ".." ] && continue
        # Skip .git
        [ "$name" = ".git" ] && continue
        # Skip .worktreerc (handled separately as a hook)
        [ "$name" = ".worktreerc" ] && continue
        items+=("$name")
    done

    echo "${items[@]}"
}

# Detect the default branch of a specific remote (from <remote>/HEAD).
# Stdout on success: branch name (e.g., "main").
# Returns 1 if detection fails.
detect_remote_default_branch() {
    local repo_path="$1"
    local remote="$2"

    local ref
    ref=$(git -C "$repo_path" symbolic-ref "refs/remotes/${remote}/HEAD" 2>/dev/null)
    if [ -n "$ref" ]; then
        echo "${ref#refs/remotes/${remote}/}"
        return
    fi

    if git -C "$repo_path" remote set-head "$remote" --auto >/dev/null 2>&1; then
        ref=$(git -C "$repo_path" symbolic-ref "refs/remotes/${remote}/HEAD" 2>/dev/null)
        if [ -n "$ref" ]; then
            echo "${ref#refs/remotes/${remote}/}"
            return
        fi
    fi

    if git -C "$repo_path" rev-parse --verify "${remote}/main" >/dev/null 2>&1; then
        echo "main"
    elif git -C "$repo_path" rev-parse --verify "${remote}/master" >/dev/null 2>&1; then
        echo "master"
    else
        return 1
    fi
}

# Detect the base remote and its default branch.
# Prefers 'upstream' (fork workflow) over 'origin'.
# Stdout on success: "<remote> <branch>" (e.g., "upstream master").
# Returns 1 if neither remote yields a default branch.
detect_base_remote_branch() {
    local repo_path="$1"

    if git -C "$repo_path" remote get-url upstream >/dev/null 2>&1; then
        local upstream_default
        if upstream_default="$(detect_remote_default_branch "$repo_path" upstream)"; then
            echo "upstream ${upstream_default}"
            return
        fi
    fi

    local origin_default
    if origin_default="$(detect_remote_default_branch "$repo_path" origin)"; then
        echo "origin ${origin_default}"
        return
    fi

    return 1
}

# Detect the default branch of a repository.
# Prefers upstream's default branch when an 'upstream' remote exists,
# falling back to origin (fork workflows where origin diverges from upstream).
detect_default_branch() {
    local repo_path="$1"

    local result
    if result="$(detect_base_remote_branch "$repo_path")"; then
        echo "${result#* }"
        return
    fi

    log_error "Cannot detect default branch: $repo_path"
    return 1
}
