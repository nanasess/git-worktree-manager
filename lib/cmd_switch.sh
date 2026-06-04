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
        echo "    worktree switch <name>   Go to the matching worktree"
        echo "    worktree switch -        Go to the previous worktree"
        echo "    worktree switch          Pick a worktree interactively (fzf)"
        echo ""
        echo -e "${BOLD}NOTES:${NC}"
        echo "    <name> is matched against worktree task names:"
        echo "      exact match > unique prefix > unique substring."
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

    local target_name
    target_name="$(resolve_task_name "$query" "$names")" || return 1

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
