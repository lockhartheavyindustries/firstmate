#!/usr/bin/env bash
# Live: primary home names standing skills; bin/fm-config-push.sh pushes them into a
# registered secondmate home (a real detached git worktree); a brief scaffolded in that
# secondmate home then carries the paragraph. Removing the primary file converges absence.
# Only the terminal backend (tmux) is faked, so the reread nudge has somewhere to go.
set -u
ROOT=$1
W=$(mktemp -d "${TMPDIR:-/tmp}/fm-standing-skills-push.XXXXXX")
mkdir -p "$W/home/state" "$W/home/data" "$W/home/config"
touch "$W/home/state/.last-watcher-beat"
git init -q -b main "$W/main"
printf 'projects/\nstate/\ndata/\n.no-mistakes/\nconfig/\n' > "$W/main/.gitignore"
printf 'v1\n' > "$W/main/AGENTS.md"; mkdir -p "$W/main/bin"; printf 'echo a\n' > "$W/main/bin/tool.sh"; git -C "$W/main" add -A; git -C "$W/main" -c user.email=t@t -c user.name=t commit -qm c1
head=$(git -C "$W/main" rev-parse HEAD)
git -C "$W/main" worktree add -q --detach "$W/sm" "$head"
printf 'sm\n' > "$W/sm/.fm-secondmate-home"
{ printf 'window=firstmate:fm-sm\nkind=secondmate\nhome=%s/sm\n' "$W"; } > "$W/home/state/sm.meta"
FB="$W/fakebin"; mkdir -p "$FB"
cat > "$FB/tmux" <<'SH'
#!/usr/bin/env bash
[ -n "${FM_FAKE_TMUX_LOG:-}" ] && printf '%s\n' "$*" >> "$FM_FAKE_TMUX_LOG"
case "$*" in
  list-windows*) sed -n 's/^window=[^:]*://p' "${FM_HOME:?}"/state/*.meta; exit 0 ;;
  *display-message*'#{pane_current_command}'*) echo codex; exit 0 ;;
  *display-message*'#{pane_id}'*) echo '%1'; exit 0 ;;
  *display-message*'#{cursor_y}'*) echo 0; exit 0 ;;
  *capture-pane*) printf '❯\n'; exit 0 ;;
esac
exit 0
SH
chmod +x "$FB/tmux"
push() { PATH="$FB:$PATH" FM_HOME="$W/home" FM_ROOT_OVERRIDE="$W/main" FM_SEND_SETTLE=0 FM_FAKE_TMUX_LOG="$W/tmux.log" "$ROOT/bin/fm-config-push.sh"; }
echo "== 1. primary config/standing-skills = kun; push =="
printf '# captain standing skills\nkun\n' > "$W/home/config/standing-skills"
push; echo "  exit=$?"
echo "  secondmate home config/standing-skills: $( [ -f "$W/sm/config/standing-skills" ] && tr '\n' '|' < "$W/sm/config/standing-skills" || echo MISSING)"
echo "  secondmate worktree git status (must stay clean): '$(git -C "$W/sm" status --porcelain)'"
echo "== 2. brief scaffolded IN the secondmate home carries the paragraph =="
mkdir -p "$W/sm/data"
FM_HOME="$W/sm" "$ROOT/bin/fm-brief.sh" crew-task some-proj --mode no-mistakes >/dev/null && grep -n 'Standing skills' "$W/sm/data/crew-task/brief.md" | sed 's/^/  line /'
echo "== 3. unchanged push is a no-op =="
push; echo "  exit=$?"
echo "== 4. primary removes the file; push mirrors absence =="
rm -f "$W/home/config/standing-skills"
push; echo "  exit=$?"
echo "  secondmate home config/standing-skills: $( [ -e "$W/sm/config/standing-skills" ] && echo STILL-PRESENT || echo absent)"
rm -rf "$W/sm/data/crew-task"
FM_HOME="$W/sm" "$ROOT/bin/fm-brief.sh" crew-task some-proj --mode no-mistakes >/dev/null && echo "  brief in secondmate home now: $(grep -c 'Standing skills' "$W/sm/data/crew-task/brief.md") 'Standing skills' occurrences"
echo "== 5. an invalid primary list is copied as-is; the secondmate's scaffold then refuses loudly =="
printf '/kun\n' > "$W/home/config/standing-skills"; push >/dev/null; echo "  push exit=$?; sm file: $(cat "$W/sm/config/standing-skills")"
rm -rf "$W/sm/data/crew-task"; FM_HOME="$W/sm" "$ROOT/bin/fm-brief.sh" crew-task some-proj --mode no-mistakes; echo "  scaffold exit=$?"
git -C "$W/main" worktree remove --force "$W/sm" 2>/dev/null; rm -rf "$W"
