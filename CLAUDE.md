# CLAUDE.md

## 概要

git-worktree-manager は、プロジェクトルート配下の複数 git リポジトリに対して worktree の作成・一覧・削除を一括で行うツールです。

Claude Code の並列処理（サブエージェント）で、各エージェントが独立した git worktree で作業できるようにするために使用します。

## インストール

```bash
ln -sf ~/git-repos/git-worktree-manager/worktree ~/.local/bin/worktree
```

## 動作要件 (Bash バージョン)

連想配列 (`declare -A`) を使うため **Bash 4.0 以上が必須**。macOS の `/bin/bash` は GPLv3 回避のため Bash 3.2 のままなので、そのままでは `declare: -A: invalid option` で失敗する。

- `worktree` の shebang は `#!/usr/bin/env bash` とし、PATH 上の新しい bash を使う。`#!/bin/bash` だと macOS で常に 3.2 が使われるため**絶対パス固定にしない**。
- macOS では `brew install bash`（or Nix/home-manager）で Bash 5 を入れ、`$(brew --prefix)/bin` を `/bin` より前に PATH へ通す。ユーザーは既に Nix/home-manager で bash を管理しているため通常は充足済み。
- 起動直後に `BASH_VERSINFO` で 4 未満を検出したら、`brew install bash` を案内して明示エラー終了する（cryptic な `declare -A` エラーを避ける）。
- 併せて `worktree` / `lib/common.sh` の symlink 解決は `readlink -f` (BSD 非対応) を使わず、素の `readlink` ＋ 相対パス解決で行う。
- CI は `ubuntu-latest` ＋ `macos-latest` の matrix で実行し、macOS leg では `brew install bash` 後に PATH を通してから bats を走らせる。

## コマンド

```bash
worktree create <task-name> [--branch-prefix <prefix>] [--no-install] [--no-cd]
worktree list [--merged] [--names-only]
worktree cleanup <task-name> [--force] [--delete-branches]
worktree cleanup --merged [--force] [--delete-branches] [--dry-run]
worktree cleanup [--force] [--delete-branches] < <(task-name-source)
worktree checkout [branch]
worktree checkout <issue-or-pr-URL> [--no-install] [--no-cd]
worktree switch [name|branch|URL|-]
worktree pull
worktree install --skills [--global]
worktree shell-init
worktree completion <bash|zsh>
```

`worktree list --merged --names-only` の出力は `worktree cleanup` の stdin にそのままパイプ可能 (1 行 1 task name)。マージ済み worktree をまとめて削除する用途で使う。`list --merged` は any-merged (1 つでもマージ済み sub-repo を含む) 判定で、`cleanup --merged` の all-merged 判定とは仕様が異なるため、パイプ削除時は未マージ sub-repo まで巻き込んで消える点に注意。

`worktree checkout <URL>` は GitHub の Issue/PR URL を受け付け、
- Issue URL: `issue-<N>` というタスク名で worktree とブランチを作成
- PR URL: `pr-<N>` というタスクディレクトリに、PR の head ブランチ名そのままのローカルブランチで worktree を作成
- マルチリポの場合、PR URL は URL に一致する単一リポの worktree のみ作成
- `gh` CLI はオプション: 無ければ Issue 検証をスキップし、PR はブランチ名を `pr-<N>` にフォールバック

すべてのコマンドはプロジェクトルートまたは `.worktrees/` ディレクトリ内から実行可能。

## worktree switch とシェル統合

`worktree switch [name|branch|URL|-]` は worktree ディレクトリへ `cd` するためのコマンド。worktrunk の `wt switch` 相当。大量の worktree (`pr-*` / `issue-*` / `create` した feature ブランチが混在) から、手元にある識別子 (タスク名・ブランチ名・PR/Issue URL) で目的の worktree を引ける点が主眼。

**根本的な制約**: `worktree` は別プロセスなので、子プロセスから親シェルの CWD は変更できない。そのため `switch` 単体では `cd` できず、**シェル統合が必須**。

- バイナリ側の `worktree switch <name>` は、名前を解決した**絶対パスを stdout に出力するだけ**。ログ・エラー・fzf UI・ヒントはすべて stderr へ流し、stdout を解決パス専用に保つ。
- `eval "$(worktree shell-init)"` を `~/.zshrc` / `~/.bashrc` に追加すると、`worktree` がシェル関数になる。`switch` / `sw` のときだけ出力パスを受けて `cd` し、それ以外のサブコマンドは `command worktree` にそのまま委譲する。bash / zsh 両対応。
- 非 URL クエリのマッチング優先順位は **タスク名の完全一致 > ブランチ名の完全一致 > 一意な prefix > 一意な substring**。あいまいな場合は候補を stderr に出して非ゼロ終了。ブランチ名一致は「タスク名 ≠ ブランチ名」のケース (`--branch-prefix` 付き作成、`pr-<N>` タスクで branch が PR head ref) を救う。
- GitHub URL は番号・ブランチ経由で解決 (`gh` 推奨、無ければ命名規約のみにフォールバック):
  - **PR URL** (`.../pull/<N>`): `gh pr view` で head ブランチを取得し、そのブランチを checkout している worktree へ。無ければ `checkout` 由来の `pr-<N>` タスクへ。→ PR を切った元の feature worktree にも着地できる。
  - **Issue URL** (`.../issues/<N>`): まず `checkout` 由来の `issue-<N>` タスク。無ければ、その issue を close する PR (`closes #N`、`closedByPullRequestsReferences`) や `gh issue develop` で紐付けたブランチを辿って対応 worktree へ。複数該当時は候補コマンドを stderr に列挙して非ゼロ終了 (自動選択しない)。
- マルチリポではタスクディレクトリ (worktree のプロジェクトルート) へ `cd` する (個別の sub-repo ではない)。
- `switch -` は直前にいたディレクトリへトグル (`cd -` 相当だが switch 間スコープ)。シェル関数内の `_WORKTREE_PREV` で追跡するため、バイナリ単体に `-` を渡すとシェル統合を案内して非ゼロ終了する。
- 引数なしは `fzf` があり端末が接続されていればインタラクティブ選択、無ければ worktree 名一覧を表示。
- シェル統合なしで `worktree switch <name>` を実行した場合は解決パスを表示するだけ (cd はしない)。`_WORKTREE_SHELL_WRAPPED` が未設定かつ stdout が端末のときは統合を促すヒントを stderr に出す。
- 実装は `lib/cmd_switch.sh` の `cmd_switch` (解決) / `cmd_shell_init` (シェル関数出力) / `resolve_switch_target` (非 URL の解決) / `resolve_task_name` (prefix/substring マッチング) / `resolve_url_to_task` (URL 解決) / `find_tasks_by_branch` (ブランチ→タスク) / `find_tasks_for_issue` (issue→リンク PR/ブランチ→タスク) と、`lib/detect.sh` の `list_all_task_names` (タスク名列挙、`list` と共有) に集約。ブランチ/issue 解決はローカル git 読み取り (`find_tasks_by_branch`) と `gh` (`find_tasks_for_issue`, PR head 取得) を使う。

`switch` は人間がシェルで `cd` するためのコマンドで、サブエージェント (Bash 呼び出しごとに CWD が独立) には適さないため、Claude Code 用の Skill は提供しない。

### create / checkout 後の自動 cd

シェル統合が有効な対話シェルでは、`worktree create` および `worktree checkout <URL>` の成功後、新しい worktree へ**自動的に `cd`** する (worktrunk の `wt switch --create` 相当の UX)。`--no-cd` で無効化できる (オプトアウト方式)。

- `create` / `checkout` は進捗ログを大量に stdout へ出すため、switch のような「stdout=パス」方式は使えない。代わりにシェル関数が一時ファイルを `_WORKTREE_CD_FILE` で渡し、ログは通常どおり画面に流しつつ、バイナリは**成功時に最終 task ディレクトリだけをそのファイルへ書き込む** (`common.sh` の `write_cd_target`)。関数が読んで `cd` する。
- `_WORKTREE_CD_FILE` が未設定のとき `write_cd_target` は no-op。したがって**シェル統合なしの直接実行・サブエージェントの Bash 呼び出しでは一切 cd しない** (既存挙動を完全維持)。自動 cd が効くのは `shell-init` を入れた対話シェルだけ。
- `checkout <branch>` (URL でないブランチ切替) は新ディレクトリを作らないので cd しない。issue URL は `cmd_create` 経由、PR URL は `cmd_checkout_pr` 末尾で `write_cd_target` を呼ぶ。
- 自動 cd 後は `_WORKTREE_PREV` に元のディレクトリが入るため、`worktree switch -` で作成前の場所へ戻れる。

## シェル補完 (worktree completion)

`worktree completion <bash|zsh>` は補完スクリプトを stdout に出力する。`shell-init` と同じ「eval して使う」方式で、`~/.zshrc` / `~/.bashrc` に `eval "$(worktree completion zsh)"` を追加する (zsh は **compinit の後**)。zsh は `fpath` に `_worktree` として置く運用も可能。

- **補完スクリプトはチェックイン済みファイルではなく `lib/cmd_completion.sh` から生成する**。コマンド定義と補完定義が同じバイナリに同梱され、乖離しない。**コマンド・オプションを追加したらここも更新する** (「コマンド追加・修正時のチェックリスト」参照)。
- タスク名の候補は `worktree list --names-only` (= `list_all_task_names`) を呼んで得る。`list` / `switch` と候補集合が常に一致し、`gh` もリポジトリごとの git 呼び出しも走らないので対話補完に耐える速度。プロジェクト外では空を返すだけ (エラーにしない)。
- `checkout` のブランチ補完はプロジェクトルート自身 (シングルリポ) と直下のサブリポ (マルチリポ) の `refs/heads` を集める。ツール側の検出ロジックを呼ばず補完スクリプト内で完結させ、CLI に内部用サブコマンドを増やさない方針。
- **マッチングは prefix ベース** (`compgen` / `_describe`) で、`switch` の substring 解決より狭い。`switch login` は解決できるが `switch login<TAB>` は補完されない — シェル標準の挙動に合わせる意図的な差。
- bash 側は **bash 3.2 互換**を保つ (連想配列・`_init_completion` 等の bash-completion ヘルパーを使わない)。バイナリ本体と違い、補完スクリプトを読むのは macOS の `/bin/bash` (3.2) かもしれず、bash-completion 未導入環境もあるため。
- zsh 側は eval と fpath autoload の**両対応**: 先頭に `#compdef worktree` タグを置き、末尾で `funcstack[1]` を見て「autoload なら `_worktree` を実行 / eval なら `compdef` で登録」を分岐する。
- `switch` と同様、これは人間がシェルで使う機能なので Claude Code 用 Skill は提供しない。

## base branch の決定ロジック

`worktree create` および `cleanup --merged` のマージ判定は、**`upstream` remote が存在する場合は `upstream/HEAD` を優先**し、なければ `origin/HEAD` を使う。fork ワークフロー (例: `origin` = `nanasess/ec-cube2`、`upstream` = `EC-CUBE/ec-cube2`) で origin が upstream より遅れている場合でも、worktree は upstream の最新を base にできる。`upstream` がある場合は `git fetch upstream` も自動で実行する。

`worktree checkout` (引数なし / branch 指定) は既存 local ブランチを切り替えるだけなので、upstream の追従はユーザ側で `git pull upstream <branch>` する想定 (local commit を破壊しないため意図的に手動)。

### `<remote>/HEAD` キャッシュの鮮度 (issue #23)

base branch の検出 (`detect_remote_default_branch`) はローカルにキャッシュされた `<remote>/HEAD` シンボリック参照を読む。しかし `git fetch <remote>` はこの参照を更新しないため、**リモートのデフォルトブランチが変更されても古い値が残り続け**、誤ったベースブランチで worktree が作られていた。

- `worktree create` / `checkout <PR URL>` は fetch 直後に `git remote set-head <remote> --auto` (`lib/detect.sh` の `refresh_remote_head`) を呼び、`<remote>/HEAD` を最新化してから base branch を決める。
- `refresh_remote_head` は **ネットワークアクセスを伴う** ため、fetch 済みコンテキスト (create/checkout) からのみ呼ぶ。`cleanup --merged` はオフライン実行を許容する設計なので**意図的に refresh しない** (キャッシュ依存のまま)。
- `detect_remote_default_branch` 自体は読み取り専用 (ネットワークなし) を維持する。

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
5. **補完更新** — `lib/cmd_completion.sh` の bash / zsh 両スクリプトにサブコマンド・オプションを追加・修正 (`worktree` 本体の `usage()` とサブコマンド dispatch も忘れずに)

## 言語ルール

- **CLAUDE.md 以外はすべて英語** で記述する
  - ソースコード（コメント、ログ出力、ヘルプテキスト）
  - コミットメッセージ
  - PR タイトル・説明
  - Issue
  - テストの記述
- **CLAUDE.md のみ日本語** で記述する
