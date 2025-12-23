## For wtp and tmux integration
_wtp_is_main() {
  [[ "$1" == "@" || "$1" == "@*" ]]
}

_wtp_winname() {
  # worktree/branch name -> tmux window/session safe name
  echo "${1//\//_}"
}

_wtp_select_branch() {
  # usage: _wtp_select_branch [branch]
  if [[ -n "$1" ]]; then
    echo "$1"
    return 0
  fi

  git branch -a \
    | sed -E 's/^[* ]+//' \
    | grep -v -e '->' \
    | sed -E 's#^remotes/[^/]*/##' \
    | sort -u \
    | peco
}

_wtp_worktree_path() {
  # usage: _wtp_worktree_path <name>
  local name="$1"
  git worktree list | awk -v name="$name" '$NF == "[" name "]" {print $1; exit}'
}

_wtp_with_env_mv() {
  # usage: _wtp_with_env_mv <command...>
  # Temporarily move apps/desktop/.env.development.local -> ..._
  local moved=0
  local src="apps/desktop/.env.development.local"
  local bak="apps/desktop/.env.development.local_"

  _restore() {
    (( moved )) && [ -e "$bak" ] && mv "$bak" "$src"
  }
  trap _restore EXIT INT TERM

  if [ -e "$src" ]; then
    mv "$src" "$bak"
    moved=1
  fi

  "$@"
}

_wtp_tmux_open_for_path() {
  # usage: _wtp_tmux_open_for_path <name> <path>
  local name="$1"
  local wt="$2"
  local win
  local wname="$(_wtp_winname "$name")"

  command -v tmux >/dev/null 2>&1 || return 0

  if [[ -n "$TMUX" ]]; then
    # in tmux: create a window in current session
    tmux new-window -c "$wt" -n "$wname"
  else
    # outside tmux: create a new session
    tmux new-session -s "$wname" -c "$wt"
  fi
}

_wtp_tmux_find_window_id() {
  # usage: _wtp_tmux_find_window_id <winname>
  local wname="$1"
  tmux list-windows -F '#{window_id} #{window_name}' \
    | awk -v w="$wname" '$2 == w {print $1; exit}'
}

_wtp_tmux_kill_window_by_name() {
  # usage: _wtp_tmux_kill_window_by_name <name>
  command -v tmux >/dev/null 2>&1 || return 0
  [[ -n "$TMUX" ]] || return 0

  local wname="$(_wtp_winname "$1")"
  local win="$(_wtp_tmux_find_window_id "$wname")"
  [[ -n "$win" ]] && tmux kill-window -t "$win"
}

_wtp_confirm_delete() {
  # usage: _wtp_confirm_delete <name>
  local name="$1"
  local wname="$(_wtp_winname "$name")"
  local ans

  echo "Delete worktree '$name' with branch and tmux window '$wname'? [y/N]"
  read -r ans
  [[ "$ans" =~ ^[Yy]$ ]]
}

_wtp_run_hook() {
  # usage: _wtp_run_hook <hook-func-name>
  local hook="$1"
  (( $+functions[$hook] )) && "$hook"
}

# _wtp_with_add_hooks: run `wtp add` command with pre/post/cleanup hooks
_wtp_with_add_hooks() {
  # usage: _wtp_with_hooks <command...>
  # - pre hook:  _wtp_hook_pre_create
  # - post hook: _wtp_hook_post_create
  # - cleanup:   _wtp_hook_cleanup (必ず実行)
  _wtp_run_hook _wtp_hook_pre_create || return

  _wtp__cleanup() { _wtp_run_hook _wtp_hook_cleanup; }
  trap _wtp__cleanup EXIT INT TERM

  "$@" || return $?

  _wtp_run_hook _wtp_hook_post_create
}

# --- public commands --------------------------------------------------

wl() { wtp ls "$@"; }

# wa: pick branch (arg or peco), create worktree, open tmux window/session
wa() {
  local name wt

  name="$(_wtp_select_branch "$1")" || return
  [[ -n "$name" ]] || return

  _wtp_with_env_mv wtp add "$name" || return 1

  wt="$(_wtp_worktree_path "$name")"
  [[ -n "$wt" ]] || { echo "worktree not found: $name" >&2; return 1; }

  _wtp_tmux_open_for_path "$name" "$wt"
}

# wn: create worktree with -b, open tmux window/session
wn() {
  local name="$1" wt
  [[ -n "$name" ]] || { echo "usage: wn <worktree-name>"; return 2; }

  _wtp_with_env_mv wtp add -b "$@" || return 1

  wt="$(_wtp_worktree_path "$name")"
  [[ -n "$wt" ]] || { echo "worktree not found: $name" >&2; return 1; }

  _wtp_tmux_open_for_path "$name" "$wt"
}

# wd: select worktree, confirm, remove, kill tmux window
wd() {
  local name
  name="$(wtp ls -q | peco)" || return
  [[ -n "$name" ]] || return

  _wtp_is_main "$name" && { echo "refusing to remove main worktree (@)" >&2; return 1; }

  _wtp_confirm_delete "$name" || { echo "aborted"; return 0; }

  wtp remove --with-branch "$name" || return 1
  _wtp_tmux_kill_window_by_name "$name"
}

# wm: select worktree; if tmux window exists -> jump; else create; then wtp cd in that window
wm() {
  local p winname win

  p="$(wtp ls -q | peco)" || return
  [[ -n "$p" ]] || return

  winname="$(_wtp_winname "$p")"

  if ! command -v tmux >/dev/null 2>&1; then
    wtp cd "$p"
    return
  fi

  if [[ -z "$TMUX" ]]; then
    tmux new-session -s "$winname" -c "$(pwd)" "wtp cd \"$p\"; exec \$SHELL"
    return
  fi

  win="$(_wtp_tmux_find_window_id "$winname")"
  if [[ -n "$win" ]]; then
    tmux select-window -t "$win"
  else
    tmux new-window -n "$winname"
  fi

  tmux send-keys "wtp cd \"$p\"" C-m
}

# wdc: delete current worktree (by cwd), confirm, cd @, remove, kill tmux window
wdc() {
  local cwd name

  cwd="$(pwd -P)"

  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
    echo "not inside a git repository" >&2
    return 1
  }

  name="$(git worktree list | awk -v cwd="$cwd" '$1 == cwd { gsub(/[\[\]]/, "", $NF); print $NF; exit }')"
  [[ -n "$name" ]] || { echo "current directory is not a registered worktree" >&2; return 1; }

  _wtp_is_main "$name" && { echo "refusing to remove main worktree (@)" >&2; return 1; }

  _wtp_confirm_delete "$name" || { echo "aborted"; return 0; }

  wtp cd "@" || return 1
  wtp remove --with-branch "$name" || return 1
  _wtp_tmux_kill_window_by_name "$name"
}
