#!/bin/bash
#
# cmd_completion.sh - completion subcommand (bash / zsh completion scripts)
#
# Like `shell-init`, this prints a script for the user's shell to evaluate;
# stdout carries the script and nothing else, so every diagnostic goes to
# stderr. The bash and zsh scripts are kept here (rather than as checked-in
# files) so the completion always ships with the binary that defines the
# commands it completes.
#
# Task names come from `worktree list --names-only`, which is the same
# discovery path `list` and `switch` use (list_all_task_names) — no gh, no
# per-repo git calls, so it stays fast enough for interactive completion.
#

cmd_completion_usage() {
    {
        echo -e "${BOLD}worktree completion${NC} - Print a shell completion script"
        echo ""
        echo -e "${BOLD}USAGE:${NC}"
        echo "    worktree completion bash    Print the bash completion script"
        echo "    worktree completion zsh     Print the zsh completion script"
        echo ""
        echo -e "${BOLD}SETUP:${NC}"
        echo "    bash — add to ~/.bashrc:"
        echo "      eval \"\$(worktree completion bash)\""
        echo ""
        echo "    zsh — add to ~/.zshrc, after compinit:"
        echo "      eval \"\$(worktree completion zsh)\""
        echo ""
        echo "    zsh (fpath install, no startup cost):"
        echo "      worktree completion zsh > \"\${fpath[1]}/_worktree\""
        echo ""
        echo -e "${BOLD}NOTES:${NC}"
        echo "    Completes subcommands, options, task names (cleanup/switch)"
        echo "    and local branches (checkout)."
    } >&2
}

# bash completion script.
#
# Deliberately free of bash 4+ syntax and of any bash-completion helper
# (_init_completion et al): an interactive macOS /bin/bash 3.2 without
# bash-completion installed must still be able to source this.
completion_bash() {
    cat <<'BASH_COMPLETION'
# git-worktree-manager bash completion
# Installed via: eval "$(worktree completion bash)"

# Worktree task names for the current project (empty outside a project).
_worktree_task_names() {
    command worktree list --names-only 2>/dev/null
}

# Local branches: the project root itself when it is a git repo (single repo),
# plus every immediate sub-repo (multi repo). Matches what `checkout <branch>`
# actually operates on.
_worktree_branches() {
    local dir
    git for-each-ref --format='%(refname:short)' refs/heads 2>/dev/null
    for dir in */; do
        [ -e "${dir}.git" ] || continue
        git -C "$dir" for-each-ref --format='%(refname:short)' refs/heads 2>/dev/null
    done
}

_worktree() {
    local cur prev cmd i
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    # --branch-prefix takes a free-form value; there is nothing to suggest.
    if [ "$prev" = "--branch-prefix" ]; then
        return 0
    fi

    # The subcommand is the first non-option word after the binary name.
    cmd=""
    for ((i = 1; i < COMP_CWORD; i++)); do
        case "${COMP_WORDS[i]}" in
            -*) ;;
            *) cmd="${COMP_WORDS[i]}"; break ;;
        esac
    done

    if [ -z "$cmd" ]; then
        COMPREPLY=($(compgen -W "create list ls cleanup clean rm checkout co switch sw pull install shell-init completion help version -h --help -v --version" -- "$cur"))
        return 0
    fi

    case "$cmd" in
        create)
            # The task name is new by definition — only options are completable.
            case "$cur" in
                -*) COMPREPLY=($(compgen -W "--branch-prefix --no-install --no-cd -h --help" -- "$cur")) ;;
            esac
            ;;
        list|ls)
            COMPREPLY=($(compgen -W "--merged --names-only -h --help" -- "$cur"))
            ;;
        cleanup|clean|rm)
            case "$cur" in
                -*) COMPREPLY=($(compgen -W "--merged --delete-branches --dry-run --force -h --help" -- "$cur")) ;;
                *) COMPREPLY=($(compgen -W "$(_worktree_task_names)" -- "$cur")) ;;
            esac
            ;;
        checkout|co)
            case "$cur" in
                -*) COMPREPLY=($(compgen -W "--no-install --no-cd --branch-prefix -h --help" -- "$cur")) ;;
                *) COMPREPLY=($(compgen -W "$(_worktree_branches)" -- "$cur")) ;;
            esac
            ;;
        switch|sw)
            case "$cur" in
                # `-` (previous worktree) is offered alongside the help flags.
                -*) COMPREPLY=($(compgen -W "- -h --help" -- "$cur")) ;;
                *) COMPREPLY=($(compgen -W "$(_worktree_task_names)" -- "$cur")) ;;
            esac
            ;;
        pull)
            COMPREPLY=($(compgen -W "-h --help" -- "$cur"))
            ;;
        install)
            COMPREPLY=($(compgen -W "--skills --global -h --help" -- "$cur"))
            ;;
        completion)
            COMPREPLY=($(compgen -W "bash zsh -h --help" -- "$cur"))
            ;;
    esac
    return 0
}

complete -F _worktree worktree
BASH_COMPLETION
}

# zsh completion script.
#
# Written to work both ways: `eval "$(worktree completion zsh)"` (the trailing
# guard runs compdef) and dropped into an fpath directory as `_worktree` (the
# `#compdef` tag applies and the guard invokes the function instead).
completion_zsh() {
    cat <<'ZSH_COMPLETION'
#compdef worktree
# git-worktree-manager zsh completion
# Installed via: eval "$(worktree completion zsh)"   # after compinit
#           or:  worktree completion zsh > "${fpath[1]}/_worktree"

# Worktree task names for the current project (empty outside a project).
_worktree_task_names() {
    local -a names
    names=(${(f)"$(command worktree list --names-only 2>/dev/null)"})
    names=(${names:#})
    (( ${#names} )) || return 1
    _describe -t worktrees 'worktree' names
}

# Local branches: the project root itself when it is a git repo (single repo),
# plus every immediate sub-repo (multi repo).
_worktree_branches() {
    local -a branches
    local dir
    branches=(${(f)"$(git for-each-ref --format='%(refname:short)' refs/heads 2>/dev/null)"})
    for dir in */; do
        [[ -e ${dir}.git ]] || continue
        branches+=(${(f)"$(git -C $dir for-each-ref --format='%(refname:short)' refs/heads 2>/dev/null)"})
    done
    branches=(${(u)branches:#})
    (( ${#branches} )) || return 1
    _describe -t branches 'branch' branches
}

_worktree() {
    local curcontext="$curcontext" state line ret=1
    typeset -A opt_args

    local -a commands aliases
    commands=(
        'create:Create worktrees for a task'
        'list:List current worktrees'
        'cleanup:Remove worktrees'
        'checkout:Checkout a branch, or create a worktree from an issue/PR URL'
        'switch:Change directory to a worktree'
        'pull:Pull all repositories'
        'install:Install Claude Code skills'
        'shell-init:Print the shell integration for switch/create/checkout'
        'completion:Print a shell completion script'
    )
    # Offered as their own group so `worktree sw<TAB>` completes without
    # burying the canonical names in the menu.
    aliases=(
        'ls:Alias of list'
        'clean:Alias of cleanup'
        'rm:Alias of cleanup'
        'co:Alias of checkout'
        'sw:Alias of switch'
    )

    _arguments -C \
        '(- 1 *)'{-h,--help}'[Show help]' \
        '(- 1 *)'{-v,--version}'[Show version]' \
        '1: :->command' \
        '*:: :->args' && ret=0

    case $state in
        command)
            _describe -t commands 'worktree command' commands && ret=0
            _describe -t aliases 'worktree alias' aliases && ret=0
            ;;
        args)
            case $words[1] in
                create)
                    _arguments \
                        '--branch-prefix[Prefix for the created branch]:prefix:' \
                        '--no-install[Skip dependency installation]' \
                        '--no-cd[Do not cd into the new worktree]' \
                        '(- *)'{-h,--help}'[Show help]' \
                        '1:task name:' && ret=0
                    ;;
                list|ls)
                    _arguments \
                        '--merged[Show only tasks with at least one merged sub-repo]' \
                        '--names-only[Print task names only, one per line]' \
                        '(- *)'{-h,--help}'[Show help]' && ret=0
                    ;;
                cleanup|clean|rm)
                    _arguments \
                        '--merged[Auto-detect and remove merged tasks]' \
                        '--delete-branches[Delete branches along with worktrees]' \
                        '--dry-run[Show targets without actually deleting]' \
                        '--force[Skip confirmation prompts]' \
                        '(- *)'{-h,--help}'[Show help]' \
                        '1:task name:_worktree_task_names' && ret=0
                    ;;
                checkout|co)
                    _arguments \
                        '--no-install[Skip dependency installation]' \
                        '--no-cd[Do not cd into the new worktree]' \
                        '--branch-prefix[Prefix for the created branch]:prefix:' \
                        '(- *)'{-h,--help}'[Show help]' \
                        '1:branch or issue/PR URL:_worktree_branches' && ret=0
                    ;;
                switch|sw)
                    _arguments \
                        '(- *)'{-h,--help}'[Show help]' \
                        '1:worktree:_worktree_task_names' && ret=0
                    ;;
                pull)
                    _arguments '(- *)'{-h,--help}'[Show help]' && ret=0
                    ;;
                install)
                    _arguments \
                        '--skills[Install Claude Code skills to the project]' \
                        '--global[Install to ~/.claude/skills (all projects)]' \
                        '(- *)'{-h,--help}'[Show help]' && ret=0
                    ;;
                completion)
                    _arguments '1:shell:(bash zsh)' && ret=0
                    ;;
            esac
            ;;
    esac

    return ret
}

# Autoloaded from fpath: funcstack[1] is _worktree, so run the completer.
# Sourced via eval: register it with compdef instead.
if [ "${funcstack[1]}" = "_worktree" ]; then
    _worktree "$@"
else
    compdef _worktree worktree
fi
ZSH_COMPLETION
}

cmd_completion() {
    local shell="${1:-}"

    case "$shell" in
        -h|--help)
            cmd_completion_usage
            return 0
            ;;
        bash)
            completion_bash
            ;;
        zsh)
            completion_zsh
            ;;
        "")
            log_error "Shell name required: worktree completion <bash|zsh>" >&2
            cmd_completion_usage
            return 1
            ;;
        *)
            log_error "Unsupported shell: ${shell} (supported: bash, zsh)" >&2
            cmd_completion_usage
            return 1
            ;;
    esac
}
