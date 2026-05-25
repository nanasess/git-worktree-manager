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
# Per-repo cache: a single `worktree list` invocation can ask about dozens
# of worktree branches across the same handful of GitHub repos. Calling
# `gh pr list` once per branch turns a sub-second listing into ~50s on a
# real multi-repo project. We cache the headRefNames of the 100 most
# recent merged PRs per `<owner>/<repo>` so subsequent lookups are local
# string matches. The 100 cap is fine for display purposes; older merged
# branches may be missed, which is acceptable for a status label.
#
# parse_github_remote_url is defined in cmd_checkout.sh; both libraries are
# sourced by the worktree entrypoint, so cross-module calls are safe.
is_branch_merged_via_gh() {
    local repo_dir="$1"
    local branch="$2"

    [ -z "$branch" ] && return 1
    command -v gh >/dev/null 2>&1 || return 1

    # Lazily declare the module-scoped cache. Bash 4.2+ supports `-gA`.
    if ! declare -p __merged_branches_cache >/dev/null 2>&1; then
        declare -gA __merged_branches_cache
    fi

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

    local cache_key="${owner}/${repo}"
    if [ -z "${__merged_branches_cache[$cache_key]+_}" ]; then
        # One network call per GitHub repo. `--head` is intentionally omitted:
        # we filter on the client side via string match, which lets the cache
        # answer every branch lookup for this repo without extra requests.
        # False positives from same-name fork PRs are possible in theory but
        # rare in practice.
        local merged_list
        merged_list="$(gh pr list --repo "$cache_key" --state merged --limit 100 \
            --json headRefName --jq '.[].headRefName' 2>/dev/null)" || merged_list=""
        # Wrap with leading/trailing spaces so the glob match below treats
        # branch names as whole words.
        __merged_branches_cache[$cache_key]=" $(echo "$merged_list" | tr '\n' ' ')"
    fi

    [[ "${__merged_branches_cache[$cache_key]}" == *" ${branch} "* ]]
}

# Return 0 if any sub-repo under <task_dir> has a merged head branch.
# Used by `--merged` (any-merged semantics): unlike `cleanup --merged` which
# requires every sub-repo to be merged, this only needs one merged sub-repo
# for the task to surface in the filtered list.
task_has_merged_subrepo() {
    local task_dir="$1"
    local repo_dirs_str
    repo_dirs_str="$(list_task_repo_dirs "$task_dir")"
    [ -z "$repo_dirs_str" ] && return 1

    local repo_dirs
    read -ra repo_dirs <<< "$repo_dirs_str"
    for repo_dir in "${repo_dirs[@]}"; do
        # Broken worktrees can't be queried for a branch.
        git -C "$repo_dir" rev-parse --git-dir >/dev/null 2>&1 || continue
        local branch
        branch="$(git -C "$repo_dir" branch --show-current 2>/dev/null || true)"
        if is_branch_merged_via_gh "$repo_dir" "$branch"; then
            return 0
        fi
    done
    return 1
}

cmd_list_usage() {
    echo -e "${BOLD}worktree list${NC} - List current worktrees"
    echo ""
    echo -e "${BOLD}USAGE:${NC}"
    echo "    worktree list [OPTIONS]"
    echo ""
    echo -e "${BOLD}OPTIONS:${NC}"
    echo "    --merged       Show only tasks with at least one merged sub-repo"
    echo "    --names-only   Print task names only (one per line, no decoration)"
    echo "    -h, --help     Show help"
    echo ""
    echo -e "${BOLD}ALIASES:${NC}"
    echo "    worktree ls"
    echo ""
    echo -e "${BOLD}EXAMPLES:${NC}"
    echo "    worktree list --merged --names-only | worktree cleanup --force"
}

cmd_list() {
    local merged_only=false
    local names_only=false

    while [ $# -gt 0 ]; do
        case "$1" in
            --merged)
                merged_only=true
                ;;
            --names-only)
                names_only=true
                ;;
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

    # --names-only is the machine-readable mode: skip headers and log_info
    # noise so the output can be piped into `worktree cleanup` cleanly.
    if [ "$names_only" = false ]; then
        echo ""
        echo -e "${BOLD}${project_name}${NC} worktrees"
        echo "============================================"
    fi

    if [ ! -d "$worktrees_base" ]; then
        if [ "$names_only" = false ]; then
            log_info "No worktrees found"
            echo ""
        fi
        return 0
    fi

    # Search for git worktrees under worktrees_base.
    # Supports slash in task names (e.g., feature/task-name).
    # Uses mindepth 2 for single repo support (.git at depth 2).
    #
    # `-maxdepth` is critical for performance: without it, find descends into
    # every worktree's working tree (node_modules, target, dist, etc.), which
    # turns a sub-second listing into several seconds on real projects.
    # The cap of 6 covers:
    #   single repo, no slash:   <base>/<task>/.git                     -> depth 2
    #   multi repo,  no slash:   <base>/<task>/<repo>/.git              -> depth 3
    #   single repo, 1-slash:    <base>/<a>/<b>/.git                    -> depth 3
    #   multi repo,  1-slash:    <base>/<a>/<b>/<repo>/.git             -> depth 4
    #   multi repo,  2-slash:    <base>/<a>/<b>/<c>/<repo>/.git         -> depth 5
    #   multi repo,  3-slash:    <base>/<a>/<b>/<c>/<d>/<repo>/.git     -> depth 6
    # `-prune` is a safety net: should a `.git` directory (e.g. legacy clone
    # or submodule layout) ever appear, we skip descending into its internals.
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
    done < <(find "$worktrees_base" -mindepth 2 -maxdepth 6 -name ".git" -prune -print 2>/dev/null | sort)

    if [ ${#task_names[@]} -eq 0 ] && [ "$names_only" = false ]; then
        log_info "No worktrees found"
    fi

    for task_name in "${task_names[@]}"; do
        local task_dir="${worktrees_base}/${task_name}"

        if [ "$merged_only" = true ]; then
            if ! task_has_merged_subrepo "$task_dir"; then
                continue
            fi
        fi

        if [ "$names_only" = true ]; then
            echo "$task_name"
            continue
        fi

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

    if [ "$names_only" = false ]; then
        echo ""
    fi
    return 0
}
