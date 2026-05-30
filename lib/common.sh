#!/bin/bash
#
# common.sh - Common functions (logging, path calculation)
#

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Get the project root path.
# When run from inside a .worktrees directory, returns the original project root.
get_project_root() {
    local cwd
    cwd="$(pwd)"
    # If path contains .worktrees, calculate the original project root
    case "$cwd" in
        *.worktrees/*)
            local worktrees_dir="${cwd%%\.worktrees/*}.worktrees"
            echo "$(dirname "$worktrees_dir")/$(basename "${worktrees_dir%.worktrees}")"
            ;;
        *.worktrees)
            echo "$(dirname "$cwd")/$(basename "${cwd%.worktrees}")"
            ;;
        *)
            echo "$cwd"
            ;;
    esac
}

# Get the project name (directory name)
get_project_name() {
    basename "$(get_project_root)"
}

# Calculate the worktrees base directory path
# <project_root>/../<project_name>.worktrees/
get_worktrees_base() {
    local project_root
    project_root="$(get_project_root)"
    local project_name
    project_name="$(get_project_name)"
    echo "$(dirname "$project_root")/${project_name}.worktrees"
}

# Calculate the worktree path for a specific task
get_task_dir() {
    local task_name="$1"
    echo "$(get_worktrees_base)/${task_name}"
}

# Append the Worktree Context block to CLAUDE.local.md.
# Writes to CLAUDE.local.md (not CLAUDE.md) so the original CLAUDE.md is never
# modified: no diff is produced on a tracked single-repo CLAUDE.md, and the
# multi-repo project-root CLAUDE.md keeps its plain symlink.
# Ensures the agent remembers the working directory after /compact.
#
# Behaviour:
#   - Never writes through a symlink: if dst is a symlink (e.g. a multi-repo
#     symlinked CLAUDE.local.md), it is replaced with a real copy first so the
#     project-root original is left untouched.
#   - Idempotent: if the context block is already present, nothing is written
#     (avoids duplicate blocks when checkout re-runs on an existing dir).
#   - Preserves any pre-existing local content by appending, not overwriting.
write_worktree_context() {
    local dst="$1"
    local task_name="$2"
    local task_dir="$3"
    local project_root="$4"

    # If dst is a symlink, replace it with a real copy so we never write
    # through to the linked project-root original.
    if [ -L "$dst" ]; then
        local target
        target="$(readlink -f "$dst")"
        rm -f "$dst"
        [ -f "$target" ] && cp "$target" "$dst"
    fi

    # Idempotent: skip if the context block is already present.
    if [ -f "$dst" ] && grep -q '^# Worktree Context$' "$dst"; then
        return
    fi

    # Separate from any pre-existing content with a blank line.
    [ -s "$dst" ] && printf '\n' >> "$dst"

    cat >> "$dst" <<WORKTREE_CONTEXT
# Worktree Context

This directory was created by \`worktree create ${task_name}\` as a working worktree.

- **Task name**: ${task_name}
- **Working directory**: ${task_dir}
- **Project root (source)**: ${project_root}

> **Important**: All code changes must be made within this directory (\`${task_dir}\`).
> Do not modify the project root (\`${project_root}\`) directly.

## Testing

Run \`docker compose up\` or other commands within this directory (\`${task_dir}\`) to verify changes.
WORKTREE_CONTEXT
}

# Copy mise config files (mise.toml, mise.local.toml) from source to destination.
# Skips files that do not exist in the source, or already exist in the destination
# (git worktree add already provides tracked copies).
# Usage: copy_mise_configs <source_dir> <dest_dir>
copy_mise_configs() {
    local src="$1"
    local dst="$2"

    for name in mise.toml mise.local.toml; do
        local src_file="${src}/${name}"
        local dst_file="${dst}/${name}"
        if [ -f "$src_file" ] && [ ! -e "$dst_file" ]; then
            if cp "$src_file" "$dst_file"; then
                log_info "  ${name} -> copied (from ${src_file})"
            else
                log_warn "  Failed to copy ${name} (continuing)"
            fi
        fi
    done
}

# Print result summary
# Usage: declare -A RESULTS, then print_summary RESULTS repo_list
print_summary() {
    local -n _results=$1
    shift
    local repos=("$@")

    echo ""
    echo "============================================"
    echo " Summary"
    echo "============================================"
    for repo in "${repos[@]}"; do
        local result="${_results[$repo]:-SKIPPED}"
        if [[ "$result" == OK:* ]]; then
            echo -e "${GREEN}  ✓${NC} ${BOLD}${repo}${NC}: $result"
        elif [[ "$result" == SKIP:* ]]; then
            echo -e "${YELLOW}  ○${NC} ${BOLD}${repo}${NC}: $result"
        elif [[ "$result" == FAIL:* ]]; then
            echo -e "${RED}  ✗${NC} ${BOLD}${repo}${NC}: $result"
        else
            echo -e "  - ${BOLD}${repo}${NC}: $result"
        fi
    done
    echo ""
}
