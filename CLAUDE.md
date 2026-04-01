# CLAUDE.md

## 概要

git-worktree-manager は、プロジェクトルート配下の複数 git リポジトリに対して worktree の作成・一覧・削除を一括で行うツールです。

Claude Code の並列処理（サブエージェント）で、各エージェントが独立した git worktree で作業できるようにするために使用します。

## インストール

```bash
ln -sf ~/git-repos/git-worktree-manager/worktree ~/.local/bin/worktree
```

## コマンド

```bash
worktree create <task-name> [--branch-prefix <prefix>] [--no-install]
worktree list
worktree cleanup <task-name> [--force] [--delete-branches]
worktree cleanup --merged [--force] [--delete-branches] [--dry-run]
worktree checkout [branch]
worktree pull
worktree install --skills [--global]
```

すべてのコマンドはプロジェクトルートまたは `.worktrees/` ディレクトリ内から実行可能。

## worktree 配置構造

worktree はプロジェクトの隣に `<project>.worktrees/` として配置されます（リポジトリ内にはノイズが入らない）。

create 時に CLAUDE.md へ Worktree Context（タスク名、作業ディレクトリ、プロジェクトルート）を付加して生成する。

## .worktreerc フック

プロジェクトルートに `.worktreerc` を配置し、`post_create()` 関数を定義すると、worktree 作成後に自動実行されます。

環境変数: `WORKTREE_TASK_NAME`, `WORKTREE_TASK_DIR`, `WORKTREE_PROJECT_ROOT`

## テスト

bats-core を使用（git submodule として管理）。

```bash
git submodule update --init --recursive
./test/bats/bin/bats test/*.bats
```

## 言語ルール

- **CLAUDE.md 以外はすべて英語** で記述する
  - ソースコード（コメント、ログ出力、ヘルプテキスト）
  - コミットメッセージ
  - PR タイトル・説明
  - Issue
  - テストの記述
- **CLAUDE.md のみ日本語** で記述する
