# wtp + tmux Zsh Functions

Git worktree 管理ツール **wtp** と **tmux** を連携させるための Zsh 関数セットです。

- worktree 作成・移動・削除を **tmux window/session と同期**
- peco を使ったインタラクティブ操作
- プロジェクト固有処理を **フックとして分離**可能


## 機能

- **Worktree ライフサイクル管理**
  - 作成 (`wa`, `wn`)
  - 移動 (`wm`)
  - 削除 (`wd`, `wdc`)
- **tmux 連携**
  - worktree = tmux window / session
  - 既存 window があれば再利用
- **インタラクティブ操作**
  - peco によるブランチ / worktree 選択
- **フック機構**
  - プロジェクト固有の前処理 / 後処理を外部ファイルに分離
- **安全設計**
  - メイン worktree (`@`) の削除防止
  - 削除前の確認プロンプト


## 必要要件

- zsh
- git
- wtp
- tmux
- peco


## インストール

### 1. ファイルの配置

```bash
mkdir -p ~/.zsh/functions
# リポジトリのファイルをコピーする
~/.zsh/functions/.wtp_functions.zsh        # 共通ロジック
# 必要に応じて作成する
~/.zsh/functions/.wtp_functions.local.zsh  # （任意）プロジェクト固有ロジック
```

### 2. `.zshrc` から読み込む
```zsh
# ~/.zshrc

WTP_FUNCS="$HOME/.zsh/functions/.wtp_functions.zsh"
WTP_LOCAL="$HOME/.zsh/functions/.wtp_functions.local.zsh"

[[ -f "$WTP_FUNCS"  ]] && source "$WTP_FUNCS"
[[ -f "$WTP_LOCAL"  ]] && source "$WTP_LOCAL"
```

## コマンド一覧
### `wl`

worktree 一覧を表示します。

### `wa [branch-name]`

既存ブランチから worktree と対応する tmux window を作成します。

- 引数あり → そのブランチを使用
- 引数なし → peco でブランチ選択
- tmux window / session を自動作成

### `wn <worktree-name>`

新しいブランチと worktree と tmux window を同時に作成します（`wtp add -b` を使用）。

### `wm`

worktree と対応する tmux window に移動します。

- peco で worktree を選択
- 同名の tmux window が存在すればそこへ移動
- 無ければ新規 window を作成して `wtp cd`

### `wd`

peco で選択した worktree とブランチと対応する tmux window を削除します。

- 削除前に確認あり
- 対応する tmux window も削除

### `wdc`
現在のディレクトリに対応する worktree とブランチと tmux window を削除します。

- カレントディレクトリから worktree を判定
- メイン worktree (@) は削除不可
- 削除前に確認あり
- tmux window も同時に削除

## フック機構（プロジェクト固有処理）
プロジェクト固有の処理は共通ファイルに書かず、`.wtp_functions.local.zsh` に分離します。

### 利用可能なフック
| フック名                    | 実行タイミング         |
| ----------------------- | --------------- |
| `_wtp_hook_pre_create`  | `wtp add` 実行前   |
| `_wtp_hook_post_create` | `wtp add` 実行後   |
| `_wtp_hook_cleanup`     | `wtp add` 成功/失敗/中断時（必ず実行） |

### 例
```zsh
_wtp__is_target_repo() {
  git rev-parse --show-toplevel >/dev/null 2>&1 || return 1
  [[ "$(git rev-parse --show-toplevel)" == */repo_name ]]
}

_wtp_hook_pre_create() {
  _wtp__is_target_repo || return 0
  mv apps/desktop/.env.development.local \
     apps/desktop/.env.development.local_
  typeset -g _WTP_ENV_MOVED=1
}

_wtp_hook_cleanup() {
  [[ "${_WTP_ENV_MOVED:-0}" -eq 1 ]] || return 0
  mv apps/desktop/.env.development.local_ \
     apps/desktop/.env.development.local
}
```
