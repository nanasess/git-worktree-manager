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

# Detect the default branch of a repository (from origin/HEAD)
detect_default_branch() {
    local repo_path="$1"

    # Use origin/HEAD if set
    local ref
    ref=$(git -C "$repo_path" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null)
    if [ -n "$ref" ]; then
        echo "${ref#refs/remotes/origin/}"
        return
    fi

    # Try to auto-detect origin/HEAD
    if git -C "$repo_path" remote set-head origin --auto >/dev/null 2>&1; then
        ref=$(git -C "$repo_path" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null)
        if [ -n "$ref" ]; then
            echo "${ref#refs/remotes/origin/}"
            return
        fi
    fi

    # Fallback: main or master
    if git -C "$repo_path" rev-parse --verify origin/main >/dev/null 2>&1; then
        echo "main"
    elif git -C "$repo_path" rev-parse --verify origin/master >/dev/null 2>&1; then
        echo "master"
    else
        log_error "Cannot detect default branch: $repo_path"
        return 1
    fi
}
