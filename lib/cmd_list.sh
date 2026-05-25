#!/bin/bash
#
# cmd_list.sh - list subcommand
#

# Detect whether <branch> in <repo_dir> corresponds to a merged GitHub PR.
# Uses `gh pr list --state merged` so squash/rebase merges are caught too.
# Returns 0 if merged, 1 otherwise (incl. gh unavailable, non-GitHub remote,
# auth/network errors, or no matching PR). All failures are silent so the
# list output stays clean.
#
# parse_github_remote_url is defined in cmd_checkout.sh; both libraries are
# sourced by the worktree entrypoint, so cross-module calls are safe.
is_branch_merged_via_gh() {
    local repo_dir="$1"
    local branch="$2"

    [ -z "$branch" ] && return 1
    command -v gh >/dev/null 2>&1 || return 1

    local remotes
    remotes="$(git -C "$repo_dir" remote 2>/dev/null)" || return 1
    [ -z "$remotes" ] && return 1

    # Prefer origin, then fall back to other remotes (fork/upstream setups).
    local ordered_remotes=""
    if echo "$remotes" | grep -qx "origin"; then
        ordered_remotes+=$'origin\n'
    fi
    ordered_remotes+="$(echo "$remotes" | grep -vx "origin" || true)"

    local owner="" repo=""
    while IFS= read -r remote_name; do
        [ -z "$remote_name" ] && continue
        local url
        url="$(git -C "$repo_dir" remote get-url "$remote_name" 2>/dev/null)" || continue
        local parsed
        parsed="$(parse_github_remote_url "$url" 2>/dev/null)" || continue
        read -r owner repo <<< "$parsed"
        break
    done <<< "$ordered_remotes"

    [ -z "$owner" ] || [ -z "$repo" ] && return 1

    # `gh pr list --head` does not support "<owner>:<branch>" syntax, so we
    # match by branch name alone. False positives from same-name fork PRs are
    # possible in theory but rare in practice.
    local count
    count="$(gh pr list --repo "${owner}/${repo}" --state merged \
        --head "$branch" --json number --jq 'length' --limit 1 2>/dev/null)" || return 1
    [ -n "$count" ] && [ "$count" -gt 0 ] 2>/dev/null
}

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

                # PR-based merged check: catches squash/rebase merges too.
                # Silently no-ops when gh is missing or the remote is not GitHub.
                if is_branch_merged_via_gh "$repo_dir" "$branch"; then
                    status_icon="${status_icon} ${GREEN}[merged]${NC}"
                fi

                echo -e "    ${repo_name}: ${GREEN}${branch}${NC}${status_icon}"
            done
        fi
    done

    echo ""
    return 0
}
