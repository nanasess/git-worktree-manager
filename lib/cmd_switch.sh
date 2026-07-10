#!/bin/bash
#
# cmd_switch.sh - switch subcommand and shell integration
#
# A child process cannot change its parent shell's working directory, so
# `worktree switch` cannot `cd` on its own. Instead it RESOLVES a worktree
# name to an absolute path and prints ONLY that path on stdout; the shell
# function installed by `worktree shell-init` captures the path and performs
# the `cd`. Everything that is not the resolved path (logs, errors, prompts,
# fzf UI) must go to stderr so it never pollutes the captured value.
#

cmd_switch_usage() {
    {
        echo -e "${BOLD}worktree switch${NC} - Change directory to a worktree"
        echo ""
        echo -e "${BOLD}USAGE:${NC}"
        echo "    worktree switch <name>     Go to the matching worktree"
        echo "    worktree switch <branch>   Go to the worktree on that branch"
        echo "    worktree switch <URL>      Go to the worktree for an issue/PR URL"
        echo "    worktree switch -          Go to the previous worktree"
        echo "    worktree switch            Pick a worktree interactively (fzf)"
        echo ""
        echo -e "${BOLD}NOTES:${NC}"
        echo "    A non-URL query is resolved in this order:"
        echo "      exact task name > exact branch > unique prefix > unique substring."
        echo ""
        echo "    A GitHub URL is resolved by number / branch (gh recommended):"
        echo "      .../pull/<N>    -> the worktree on the PR head branch,"
        echo "                         else task 'pr-<N>'"
        echo "      .../issues/<N>  -> task 'issue-<N>', else a worktree linked"
        echo "                         via a closing PR / 'gh issue develop' branch"
        echo ""
        echo "    Requires shell integration to actually change directory:"
        echo "      eval \"\$(worktree shell-init)\"   # add to ~/.zshrc or ~/.bashrc"
        echo ""
        echo -e "${BOLD}ALIASES:${NC}"
        echo "    worktree sw"
    } >&2
}

# Resolve a user query to a single task name from a newline-separated list.
# Prints the resolved task name on stdout and returns 0 on success.
# On no-match or ambiguous-match, prints diagnostics to stderr and returns 1.
#
# Matching precedence: exact > unique prefix > unique substring.
resolve_task_name() {
    local query="$1"
    local names="$2"

    # 1. Exact match
    local n
    while IFS= read -r n; do
        [ -z "$n" ] && continue
        if [ "$n" = "$query" ]; then
            printf '%s\n' "$n"
            return 0
        fi
    done <<< "$names"

    # 2. Unique prefix match
    local prefix_matches=()
    while IFS= read -r n; do
        [ -z "$n" ] && continue
        case "$n" in
            "$query"*) prefix_matches+=("$n") ;;
        esac
    done <<< "$names"
    if [ ${#prefix_matches[@]} -eq 1 ]; then
        printf '%s\n' "${prefix_matches[0]}"
        return 0
    fi

    # 3. Unique substring match
    local substr_matches=()
    while IFS= read -r n; do
        [ -z "$n" ] && continue
        case "$n" in
            *"$query"*) substr_matches+=("$n") ;;
        esac
    done <<< "$names"
    if [ ${#substr_matches[@]} -eq 1 ]; then
        printf '%s\n' "${substr_matches[0]}"
        return 0
    fi

    # No unique match: report candidates (if any) or the full list.
    if [ ${#prefix_matches[@]} -gt 1 ]; then
        log_error "Ambiguous worktree name: '${query}'" >&2
        echo "Candidates:" >&2
        printf '%s\n' "${prefix_matches[@]}" | sed 's/^/  /' >&2
    elif [ ${#substr_matches[@]} -gt 1 ]; then
        log_error "Ambiguous worktree name: '${query}'" >&2
        echo "Candidates:" >&2
        printf '%s\n' "${substr_matches[@]}" | sed 's/^/  /' >&2
    else
        log_error "No worktree matches: '${query}'" >&2
        echo "Available worktrees:" >&2
        printf '%s\n' "$names" | sed 's/^/  /' >&2
    fi
    return 1
}

# Return 0 if <name> is present verbatim in the newline-separated <names> list.
task_name_exists() {
    local target="$1"
    local names="$2"
    local n
    while IFS= read -r n; do
        [ "$n" = "$target" ] && return 0
    done <<< "$names"
    return 1
}

# Print the task names whose checked-out branch (in any sub-repo) equals
# <branch>, one per line, deduped. Returns 1 when none match.
#
# This is what lets `switch` accept a branch name (or a PR head branch) even
# when the task directory is not named after the branch — e.g. a worktree made
# with `--branch-prefix` (task "fix-bug", branch "nanasess/fix-bug") or a PR
# checkout (task "pr-<N>", branch = the PR head ref). Uses only local git reads
# (no network), so it is cheap to run across many worktrees.
find_tasks_by_branch() {
    local branch="$1"
    [ -z "$branch" ] && return 1

    local worktrees_base
    worktrees_base="$(get_worktrees_base)"

    local matches=() task_name
    while IFS= read -r task_name; do
        [ -z "$task_name" ] && continue
        local task_dir="${worktrees_base}/${task_name}"
        local repo_dirs_str
        repo_dirs_str="$(list_task_repo_dirs "$task_dir")"
        [ -z "$repo_dirs_str" ] && continue
        local repo_dirs
        read -ra repo_dirs <<< "$repo_dirs_str"
        local repo_dir
        for repo_dir in "${repo_dirs[@]}"; do
            # Skip broken worktrees; they cannot report a branch.
            git -C "$repo_dir" rev-parse --git-dir >/dev/null 2>&1 || continue
            local b
            b="$(git -C "$repo_dir" branch --show-current 2>/dev/null || true)"
            if [ "$b" = "$branch" ]; then
                matches+=("$task_name")
                break
            fi
        done
    done < <(list_all_task_names)

    [ ${#matches[@]} -eq 0 ] && return 1
    printf '%s\n' "${matches[@]}"
    return 0
}

# Print task names linked to GitHub issue #<number> in <owner>/<repo>, one per
# line, deduped. Requires gh; returns 1 when gh is unavailable or nothing links
# back to a local worktree.
#
# "Linked" is resolved two ways, both via gh:
#   - PRs that would close the issue (a closing keyword like "closes #N"), read
#     from the issue's closedByPullRequestsReferences. Each such PR's head
#     branch is matched against checked-out worktree branches, and its "pr-<N>"
#     checkout task directory is accepted if present.
#   - Branches created from the issue via `gh issue develop`.
# This is what lets `switch <issue URL>` reach the feature/PR worktree even
# though the worktree is not named after the issue.
find_tasks_for_issue() {
    local owner="$1"
    local repo="$2"
    local number="$3"
    command -v gh >/dev/null 2>&1 || return 1

    local branches=()
    local pr_numbers=()

    # PRs whose merge would close this issue (closing-keyword references).
    local gql
    gql="$(gh api graphql \
        -f query='query($owner:String!,$repo:String!,$number:Int!){repository(owner:$owner,name:$repo){issue(number:$number){closedByPullRequestsReferences(first:30,includeClosedPrs:true){nodes{number headRefName}}}}}' \
        -F owner="$owner" -F repo="$repo" -F number="$number" \
        --jq '.data.repository.issue.closedByPullRequestsReferences.nodes[] | "\(.number) \(.headRefName)"' 2>/dev/null || true)"
    local pnum pbranch
    while IFS=' ' read -r pnum pbranch; do
        [ -z "$pnum" ] && continue
        pr_numbers+=("$pnum")
        [ -n "$pbranch" ] && branches+=("$pbranch")
    done <<< "$gql"

    # Branches linked to the issue via `gh issue develop`.
    local dev dbranch
    dev="$(gh issue develop --list "$number" --repo "${owner}/${repo}" 2>/dev/null | awk 'NF{print $1}' || true)"
    while IFS= read -r dbranch; do
        [ -z "$dbranch" ] && continue
        branches+=("$dbranch")
    done <<< "$dev"

    # Resolve candidate branches / PR numbers to worktree task names.
    local worktrees_base
    worktrees_base="$(get_worktrees_base)"
    local tasks=()
    local seen=" "
    local b t p
    if [ ${#branches[@]} -gt 0 ]; then
        for b in "${branches[@]}"; do
            while IFS= read -r t; do
                [ -z "$t" ] && continue
                case "$seen" in *" $t "*) ;; *) tasks+=("$t"); seen+="$t " ;; esac
            done < <(find_tasks_by_branch "$b" || true)
        done
    fi
    if [ ${#pr_numbers[@]} -gt 0 ]; then
        for p in "${pr_numbers[@]}"; do
            t="pr-${p}"
            if [ -d "${worktrees_base}/${t}" ]; then
                case "$seen" in *" $t "*) ;; *) tasks+=("$t"); seen+="$t " ;; esac
            fi
        done
    fi

    [ ${#tasks[@]} -eq 0 ] && return 1
    printf '%s\n' "${tasks[@]}"
    return 0
}

# Resolve a GitHub issue/PR URL to a single task name.
# Prints the task name on stdout (return 0); diagnostics go to stderr (return 1).
#
#   issue URL -> task "issue-<N>"  (the `checkout` naming convention)
#   PR URL    -> the worktree checked out on the PR's head branch, if any
#                (covers both a `checkout <PR URL>` worktree and a `create`d
#                 feature worktree a PR was later opened from); otherwise falls
#                 back to task "pr-<N>".
resolve_url_to_task() {
    local url="$1"
    local names="$2"

    local parsed
    parsed="$(parse_github_url "$url")" || {
        log_error "Invalid GitHub URL: ${url}" >&2
        log_error "Expected: https://github.com/<owner>/<repo>/(issues|pull)/<number>" >&2
        return 1
    }
    local owner repo kind number
    read -r owner repo kind number <<< "$parsed"

    if [ "$kind" = "pull" ]; then
        # Ask GitHub for the PR head branch, then map it back to a worktree.
        local head_ref=""
        if command -v gh >/dev/null 2>&1; then
            head_ref="$(gh pr view "$number" --repo "${owner}/${repo}" \
                --json headRefName --jq .headRefName 2>/dev/null || true)"
        fi
        if [ -n "$head_ref" ]; then
            local btasks
            if btasks="$(find_tasks_by_branch "$head_ref")"; then
                if [ "$(printf '%s\n' "$btasks" | grep -c .)" -eq 1 ]; then
                    printf '%s\n' "$btasks"
                    return 0
                fi
                log_error "Multiple worktrees hold PR #${number}'s branch '${head_ref}':" >&2
                printf '%s\n' "$btasks" | sed 's/^/  /' >&2
                return 1
            fi
        fi
        # Fall back to the `checkout <PR URL>` naming convention.
        local fallback="pr-${number}"
        if task_name_exists "$fallback" "$names"; then
            printf '%s\n' "$fallback"
            return 0
        fi
        {
            log_error "No worktree found for PR #${number} (${owner}/${repo})"
            if [ -n "$head_ref" ]; then
                log_error "  PR head branch '${head_ref}' is not checked out in any worktree"
            elif ! command -v gh >/dev/null 2>&1; then
                log_error "  (gh CLI not found — could not look up the PR head branch)"
            fi
            log_error "  Task name '${fallback}' does not exist either"
            echo "Available worktrees:"
            printf '%s\n' "$names" | sed 's/^/  /'
        } >&2
        return 1
    fi

    # issue URL: the `checkout <issue URL>` naming convention first, then fall
    # back to any worktree linked via a closing PR / `gh issue develop` branch.
    local issue_task="issue-${number}"
    if task_name_exists "$issue_task" "$names"; then
        printf '%s\n' "$issue_task"
        return 0
    fi
    local itasks
    if itasks="$(find_tasks_for_issue "$owner" "$repo" "$number")"; then
        if [ "$(printf '%s\n' "$itasks" | grep -c .)" -eq 1 ]; then
            printf '%s\n' "$itasks"
            return 0
        fi
        # Several linked worktrees: we cannot pick for the user, so list the
        # exact commands to run.
        log_error "Issue #${number} links to multiple worktrees — pick one:" >&2
        printf '%s\n' "$itasks" | sed 's/^/  worktree switch /' >&2
        return 1
    fi
    {
        log_error "No worktree found for issue #${number} (task: ${issue_task})"
        if ! command -v gh >/dev/null 2>&1; then
            log_error "  (install gh to resolve via linked PRs / branches)"
        else
            log_error "  (no linked PR or 'gh issue develop' branch points at a worktree)"
        fi
        echo "Available worktrees:"
        printf '%s\n' "$names" | sed 's/^/  /'
    } >&2
    return 1
}

# Resolve a non-URL query to a single task name.
# Precedence: exact task name > exact branch match > unique prefix > unique
# substring. Prints the task name (return 0); diagnostics to stderr (return 1).
resolve_switch_target() {
    local query="$1"
    local names="$2"

    # 1. Exact task name — the primary identifier, kept as the fast path.
    if task_name_exists "$query" "$names"; then
        printf '%s\n' "$query"
        return 0
    fi

    # 2. Exact branch match — a worktree checked out on this branch, for the
    #    "task name != branch name" cases (--branch-prefix, PR checkouts).
    local btasks
    if btasks="$(find_tasks_by_branch "$query")"; then
        if [ "$(printf '%s\n' "$btasks" | grep -c .)" -eq 1 ]; then
            printf '%s\n' "$btasks"
            return 0
        fi
        log_error "Ambiguous branch '${query}' — multiple worktrees:" >&2
        printf '%s\n' "$btasks" | sed 's/^/  /' >&2
        return 1
    fi

    # 3. Fuzzy task-name match (unique prefix > unique substring) plus the
    #    shared no-match / ambiguous diagnostics.
    resolve_task_name "$query" "$names"
}

cmd_switch() {
    case "${1:-}" in
        -h|--help)
            cmd_switch_usage
            return 0
            ;;
        -)
            # `switch -` (previous worktree) is handled entirely by the shell
            # function, which knows the prior directory. Reaching here means the
            # shell integration is not active.
            log_error "'worktree switch -' requires shell integration." >&2
            echo "Add to your shell rc: eval \"\$(worktree shell-init)\"" >&2
            return 1
            ;;
    esac

    local names
    names="$(list_all_task_names)"
    if [ -z "$names" ]; then
        log_error "No worktrees found" >&2
        return 1
    fi

    local query="${1:-}"

    # No argument: interactive picker (fzf) when a terminal is available,
    # otherwise just list the names so the user can re-run with one.
    if [ -z "$query" ]; then
        if command -v fzf >/dev/null 2>&1 && [ -t 2 ]; then
            local selected
            selected="$(printf '%s\n' "$names" | fzf --prompt='worktree> ' --height=40% --reverse)" || return 0
            [ -z "$selected" ] && return 0
            get_task_dir "$selected"
            return 0
        fi
        {
            echo "Available worktrees:"
            printf '%s\n' "$names" | sed 's/^/  /'
            echo ""
            echo "Usage: worktree switch <name>"
        } >&2
        return 0
    fi

    # A GitHub issue/PR URL is resolved via its number / PR head branch; any
    # other query is matched against task names and worktree branches.
    local target_name
    if [[ "$query" =~ ^https?:// ]]; then
        target_name="$(resolve_url_to_task "$query" "$names")" || return 1
    else
        target_name="$(resolve_switch_target "$query" "$names")" || return 1
    fi

    local target_dir
    target_dir="$(get_task_dir "$target_name")"
    if [ ! -d "$target_dir" ]; then
        log_error "Resolved worktree directory does not exist: ${target_dir}" >&2
        return 1
    fi

    # Hint when invoked directly (not through the shell function): the printed
    # path goes to the terminal but no `cd` happens without shell integration.
    if [ -z "${_WORKTREE_SHELL_WRAPPED:-}" ] && [ -t 1 ]; then
        echo "Tip: enable shell integration to cd automatically:" >&2
        echo "  eval \"\$(worktree shell-init)\"" >&2
    fi

    printf '%s\n' "$target_dir"
}

# Print the shell function that turns `worktree switch` into a real `cd`.
# Works in both bash and zsh. Install with:
#   eval "$(worktree shell-init)"
cmd_shell_init() {
    cat <<'SHELL_INIT'
# git-worktree-manager shell integration
# Installed via: eval "$(worktree shell-init)"
#
# Wraps `worktree` so directory-changing subcommands affect the current shell:
#   - switch / sw     cd into the selected worktree
#   - create          cd into the newly created worktree (unless --no-cd)
#   - checkout / co    cd into the worktree created from a GitHub URL (unless --no-cd)
# All other subcommands are delegated unchanged to the real `worktree` binary.
worktree() {
    case "${1:-}" in
        switch|sw)
            shift
            local _wt_target _wt_cur
            if [ "${1:-}" = "-" ]; then
                _wt_target="${_WORKTREE_PREV:-}"
                if [ -z "$_wt_target" ] || [ ! -d "$_wt_target" ]; then
                    echo "worktree: no previous worktree to switch to" >&2
                    return 1
                fi
            else
                _wt_target="$(_WORKTREE_SHELL_WRAPPED=1 command worktree switch "$@")" || return $?
            fi
            [ -n "$_wt_target" ] || return 0
            _wt_cur="$PWD"
            cd "$_wt_target" || return $?
            _WORKTREE_PREV="$_wt_cur"
            ;;
        create|checkout|co)
            # Let create/checkout print their progress normally, but capture the
            # destination worktree via a temp file so we can cd into it on success.
            local _wt_cdfile _wt_rc _wt_dest
            _wt_cdfile="$(command mktemp 2>/dev/null)" || _wt_cdfile=""
            if [ -z "$_wt_cdfile" ]; then
                command worktree "$@"
                return $?
            fi
            _WORKTREE_CD_FILE="$_wt_cdfile" command worktree "$@"
            _wt_rc=$?
            if [ -s "$_wt_cdfile" ]; then
                _wt_dest="$(cat "$_wt_cdfile")"
                if [ -n "$_wt_dest" ] && [ -d "$_wt_dest" ]; then
                    _WORKTREE_PREV="$PWD"
                    cd "$_wt_dest"
                fi
            fi
            command rm -f "$_wt_cdfile"
            return $_wt_rc
            ;;
        *)
            command worktree "$@"
            ;;
    esac
}
SHELL_INIT
}
