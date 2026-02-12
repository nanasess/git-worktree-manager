#!/bin/bash
#
# common.sh - 共通関数（ログ出力、パス算出）
#

# 色定義
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

# プロジェクトルートのパスを取得（カレントディレクトリ）
get_project_root() {
    echo "$(pwd)"
}

# プロジェクト名を取得（ディレクトリ名）
get_project_name() {
    basename "$(get_project_root)"
}

# worktrees ディレクトリのパスを算出
# <project_root>/../<project_name>.worktrees/
get_worktrees_base() {
    local project_root
    project_root="$(get_project_root)"
    local project_name
    project_name="$(get_project_name)"
    echo "$(dirname "$project_root")/${project_name}.worktrees"
}

# 特定タスクの worktree パスを算出
get_task_dir() {
    local task_name="$1"
    echo "$(get_worktrees_base)/${task_name}"
}

# 結果サマリ表示用
# Usage: declare -A RESULTS を事前に行い、print_summary RESULTS repo_list
print_summary() {
    local -n _results=$1
    shift
    local repos=("$@")

    echo ""
    echo "============================================"
    echo " 結果サマリ"
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
