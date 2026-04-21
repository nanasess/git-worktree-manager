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
worktree checkout <issue-or-pr-URL> [--no-install]
worktree pull
worktree install --skills [--global]
```

`worktree checkout <URL>` は GitHub の Issue/PR URL を受け付け、
- Issue URL: `issue-<N>` というタスク名で worktree とブランチを作成
- PR URL: `pr-<N>` というタスクディレクトリに、PR の head ブランチ名そのままのローカルブランチで worktree を作成
- マルチリポの場合、PR URL は URL に一致する単一リポの worktree のみ作成
- `gh` CLI はオプション: 無ければ Issue 検証をスキップし、PR はブランチ名を `pr-<N>` にフォールバック

すべてのコマンドはプロジェクトルートまたは `.worktrees/` ディレクトリ内から実行可能。

## worktree 配置構造

worktree はプロジェクトの隣に `<project>.worktrees/` として配置されます（リポジトリ内にはノイズが入らない）。

create 時に CLAUDE.md へ Worktree Context（タスク名、作業ディレクトリ、プロジェクトルート）を付加して生成する。

## mise 設定の引き継ぎ

`worktree create` は、ソース側に `mise.toml` / `mise.local.toml` が存在する場合、それらを新しい worktree にコピーする。gitignored なローカル上書き (`mise.local.toml` など) でも、mise のバージョン固定を引き継げる。

- シングルリポ: プロジェクトルート直下の `mise.toml` / `mise.local.toml`
- マルチリポ: 各サブリポ直下の `mise.toml` / `mise.local.toml`（プロジェクトルート直下の mise.toml は既存の symlink 機構で扱い済み）
- worktree 側に同名ファイルが既に存在する場合（tracked で git worktree add 済みなど）はコピーを skip

## .worktreerc フック

プロジェクトルートに `.worktreerc` を配置し、`post_create()` 関数を定義すると、worktree 作成後に自動実行されます。

環境変数: `WORKTREE_TASK_NAME`, `WORKTREE_TASK_DIR`, `WORKTREE_PROJECT_ROOT`

## テスト

bats-core を使用（git submodule として管理）。

```bash
git submodule update --init --recursive
./test/bats/bin/bats test/*.bats
```

## コマンド追加・修正時のチェックリスト

コマンドを追加または修正した場合、以下を必ず実施すること:

1. **テスト更新** — `test/single_repo.bats` および `test/multi_repo.bats` にテストケースを追加・修正
2. **README.md 更新** — Usage セクションにコマンドの説明を追加・修正
3. **CLAUDE.md 更新** — コマンド一覧を更新
4. **Skills 更新** — `skills/` 配下の SKILL.md を追加・修正。`lib/cmd_install.sh` の Available skills 表示も更新

## 言語ルール

- **CLAUDE.md 以外はすべて英語** で記述する
  - ソースコード（コメント、ログ出力、ヘルプテキスト）
  - コミットメッセージ
  - PR タイトル・説明
  - Issue
  - テストの記述
- **CLAUDE.md のみ日本語** で記述する
