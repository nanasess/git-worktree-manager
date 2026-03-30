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

# プロジェクトルートのパスを取得
# .worktrees ディレクトリ内から実行された場合は元のプロジェクトルートを返す
get_project_root() {
    local cwd
    cwd="$(pwd)"
    # パスに .worktrees が含まれる場合、元のプロジェクトルートを算出
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

# CLAUDE.md にワークツリーコンテキストを付加して生成
# /compact 後もエージェントが作業ディレクトリを忘れないようにする
generate_worktree_claude_md() {
    local src="$1"
    local dst="$2"
    local task_name="$3"
    local task_dir="$4"
    local project_root="$5"

    {
        cat <<WORKTREE_CONTEXT
# Worktree Context

このディレクトリは \`worktree create ${task_name}\` で作成された作業用ワークツリーです。

- **タスク名**: ${task_name}
- **作業ディレクトリ**: ${task_dir}
- **プロジェクトルート（参照元）**: ${project_root}

> **重要**: すべてのコード変更は必ずこのディレクトリ (\`${task_dir}\`) 内で行ってください。
> プロジェクトルート (\`${project_root}\`) を直接変更しないでください。

## 動作確認

このワークツリーには Docker Compose 環境がありません。
動作確認が必要な場合は、プロジェクトルート (\`${project_root}\`) で該当ブランチをチェックアウトして行ってください。

---

WORKTREE_CONTEXT
        cat "$src"
    } > "$dst"
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
