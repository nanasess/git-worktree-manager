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
worktree list [--merged] [--names-only]
worktree cleanup <task-name> [--force] [--delete-branches]
worktree cleanup --merged [--force] [--delete-branches] [--dry-run]
worktree cleanup [--force] [--delete-branches] < <(task-name-source)
worktree checkout [branch]
worktree checkout <issue-or-pr-URL> [--no-install]
worktree pull
worktree install --skills [--global]
```

`worktree list --merged --names-only` の出力は `worktree cleanup` の stdin にそのままパイプ可能 (1 行 1 task name)。マージ済み worktree をまとめて削除する用途で使う。`list --merged` は any-merged (1 つでもマージ済み sub-repo を含む) 判定で、`cleanup --merged` の all-merged 判定とは仕様が異なるため、パイプ削除時は未マージ sub-repo まで巻き込んで消える点に注意。

`worktree checkout <URL>` は GitHub の Issue/PR URL を受け付け、
- Issue URL: `issue-<N>` というタスク名で worktree とブランチを作成
- PR URL: `pr-<N>` というタスクディレクトリに、PR の head ブランチ名そのままのローカルブランチで worktree を作成
- マルチリポの場合、PR URL は URL に一致する単一リポの worktree のみ作成
- `gh` CLI はオプション: 無ければ Issue 検証をスキップし、PR はブランチ名を `pr-<N>` にフォールバック

すべてのコマンドはプロジェクトルートまたは `.worktrees/` ディレクトリ内から実行可能。

## base branch の決定ロジック

`worktree create` および `cleanup --merged` のマージ判定は、**`upstream` remote が存在する場合は `upstream/HEAD` を優先**し、なければ `origin/HEAD` を使う。fork ワークフロー (例: `origin` = `nanasess/ec-cube2`、`upstream` = `EC-CUBE/ec-cube2`) で origin が upstream より遅れている場合でも、worktree は upstream の最新を base にできる。`upstream` がある場合は `git fetch upstream` も自動で実行する。

`worktree checkout` (引数なし / branch 指定) は既存 local ブランチを切り替えるだけなので、upstream の追従はユーザ側で `git pull upstream <branch>` する想定 (local commit を破壊しないため意図的に手動)。

## worktree 配置構造

worktree はプロジェクトの隣に `<project>.worktrees/` として配置されます（リポジトリ内にはノイズが入らない）。

create / checkout 時に Worktree Context（タスク名、作業ディレクトリ、プロジェクトルート）を `CLAUDE.local.md` へ書き込む。**オリジナルの `CLAUDE.md` は一切変更しない**ため、単一リポでは tracked な `CLAUDE.md` に差分が出ず、マルチリポでも project root の `CLAUDE.md` は素の symlink のまま維持される。

- 既存の `CLAUDE.local.md`（ユーザー独自のローカルメモリ）がある場合は上書きせず**追記**する。`# Worktree Context` マーカーが既にあれば再追記しない（冪等）。
- マルチリポで project root に `CLAUDE.local.md` がある場合は symlink ではなく**実体コピー**してから追記するため、原本（リンク先）を破壊しない。
- 実装は `lib/common.sh` の `write_worktree_context` に集約。
- `CLAUDE.local.md` は worktree 側で untracked な新規ファイルになるので、対象リポで `.gitignore` 済みであることが望ましい（本ツールは `.gitignore` を自動編集しない）。

## 依存解決ロジック

`worktree create` / `worktree checkout` は、対象 worktree ディレクトリ直下の lock ファイルを検出して依存関係をインストールする。

- **Node.js 系 (`npm` / `pnpm` / `yarn`) は排他**: 同一ディレクトリに複数の lock がある場合は `npm > pnpm > yarn` の優先順位で 1 つだけ実行する。
- **`composer` と `dotnet` は Node.js 系と独立**: `composer.lock` と `package-lock.json` が併存する EC-CUBE 4 系のようなプロジェクトでは、`composer install` と `npm install` の両方が実行される。
- lock ファイルが無い場合 (`composer.json` のみ等) は今は何もしない。
- 部分失敗 (composer 成功 / npm 失敗) は `log_warn` で記録しつつ、1 つでも成功すれば成功扱いで継続する。呼び出し側は `|| true` で吸収済みのため、worktree 作成自体は止まらない。

実装は `lib/deps.sh` の `detect_deps_types` (検出) と `install_deps` (実行) に集約されている。

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

### テストファイルの役割

- `test/single_repo.bats` / `test/multi_repo.bats`: 外部リポを clone して URL 解析・fallback・衝突検出などを検証。`gh` 認証は必須ではない（CI の `GITHUB_TOKEN` は外部リポにアクセスできないため fallback 経路を検証）。
- `test/self_repo_smoke.bats`: 本リポの PR/Issue URL を使って `gh` 成功時のパス（head_ref 保持・worktree マッチング）を smoke test。CI では `GITHUB_TOKEN` が本リポ自身へアクセスできるので PAT 不要。`gh` が使えない環境では各テストが skip される。

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
