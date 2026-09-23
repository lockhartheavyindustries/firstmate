#!/usr/bin/env bash
# Live drive of the leftover-state audit against a scratch firstmate home that
# recreates the 2026-09-23 incident. Usage: live-drive.sh <worktree-root>
set -u
ROOT=$1
EV=$(cd "$(dirname "$0")" && pwd)
T=$(mktemp -d "${TMPDIR:-/tmp}/fm-hyg-live.XXXXXX")
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
unset FM_ROOT_OVERRIDE FM_STATE_OVERRIDE FM_PROJECTS_OVERRIDE
H=$T/home
say() { printf '\n===== %s =====\n' "$*"; }
cm() { printf '%s\n' "$3" > "$1/$2"; git -C "$1" add "$2"; git -C "$1" commit -qm "$4"; }

# --- scratch home: the operational home is itself a firstmate clone ------------
git init -q -b main "$T/fm-seed"; cm "$T/fm-seed" README fm "fm init"
git clone -q --bare "$T/fm-seed" "$T/fm-origin.git"
git clone -q "file://$T/fm-origin.git" "$H"
mkdir -p "$H/state" "$H/data" "$H/projects"
printf 'state/\ndata/\nprojects/\n' > "$H/.git/info/exclude"
# (3) a small never-pushed docs branch in the home repo itself
git -C "$H" checkout -q -b fm/docs-tweak; cm "$H" DOCS.md tweak "docs tweak"; git -C "$H" checkout -q main

# --- project clone alpha ----------------------------------------------------------
git init -q -b main "$T/a-seed"; cm "$T/a-seed" README a "alpha init"
git clone -q --bare "$T/a-seed" "$T/a-origin.git"
A=$H/projects/alpha
git clone -q "file://$T/a-origin.git" "$A"
base=$(git -C "$A" rev-parse HEAD)
# (3) work that landed via squash under a different commit
git -C "$A" checkout -q -b fm/squashed-a "$base"; cm "$A" s.txt 1 "part 1"; cm "$A" s.txt 2 "part 2"
git -C "$A" checkout -q -b fm/squashed-b "$base"; cm "$A" t.txt 1 "t work"
git -C "$A" checkout -q main
git -C "$A" merge -q --squash fm/squashed-a >/dev/null; git -C "$A" commit -qm "Squash A (#1)"
git -C "$A" merge -q --squash fm/squashed-b >/dev/null; git -C "$A" commit -qm "Squash B (#2)"
git -C "$A" push -q origin main
# (4) the clone falls 10 commits behind its upstream default branch
git clone -q "file://$T/a-origin.git" "$T/other"
for i in 1 2 3 4 5 6 7 8 9 10; do cm "$T/other" "u$i.txt" "$i" "upstream $i"; done
git -C "$T/other" push -q origin main
git -C "$A" fetch -q origin

# (1) pool: slot 1 is named by task record stale-task but claimed by newer-task
P=$T/pool; mkdir -p "$P/1" "$P/2" "$P/3"; printf '{}\n' > "$P/treehouse-state.json"
for s in 1 2 3; do git -C "$A" worktree add -q --detach "$P/$s/alpha"; done
printf 'task=newer-task\nhome=%s\n' "$H" > "$P/1/.fm-slot-owner"
printf 'task=newer-task\nhome=%s\n' "$H" > "$P/3/.fm-slot-owner"
printf 'worktree=%s\nproject=%s\nkind=ship\n' "$P/1/alpha" "$A" > "$H/state/stale-task.meta"
printf 'worktree=%s\nproject=%s\nkind=ship\n' "$P/3/alpha" "$A" > "$H/state/newer-task.meta"
# (1) duplicate claim: a second record names the same copy
printf 'worktree=%s\nproject=%s\nkind=ship\n' "$P/3/alpha" "$A" > "$H/state/dup-task.meta"
# (2) slot 2: nobody owns it, uncommitted changes left behind
printf 'leftover edit\n' >> "$P/2/alpha/README"
# Adversarial: another agent's shared-workspace worktree with live uncommitted work
git -C "$A" worktree add -q -b agent-work "$T/worktrees/alpha/codex--feature"
printf 'in progress\n' >> "$T/worktrees/alpha/codex--feature/README"
# Adversarial: an unpushed fm/* branch owned by a live task record is not a leftover
git -C "$A" checkout -q -b fm/newer-task "$base"; cm "$A" live.txt live "live work"; git -C "$A" checkout -q main
# backlog item for the docs branch (task id docs-tweak)
cat > "$H/data/backlog.md" <<'EOF'
## In flight

## Queued
- [ ] docs-tweak - Small docs tweak (repo: firstmate) (kind: ship) (since 2026-09-20)

## Done
EOF

fingerprint() {
  for r in "$H" "$A"; do
    git -C "$r" for-each-ref --format='%(refname) %(objectname)'
    git -C "$r" worktree list --porcelain
  done
  for w in "$P/1/alpha" "$P/2/alpha" "$P/3/alpha" "$T/worktrees/alpha/codex--feature"; do
    echo "$w"; git -C "$w" status --porcelain
  done
  ls -la "$P"/*/.fm-slot-owner 2>/dev/null | awk '{print $5, $NF}'
}
fingerprint > "$T/before.txt"

say "fm-hygiene-audit.sh (text)"
FM_HOME="$H" "$ROOT/bin/fm-hygiene-audit.sh" | sed "s#$T#<scratch>#g"
say "fm-hygiene-audit.sh --json (class/severity/where)"
FM_HOME="$H" "$ROOT/bin/fm-hygiene-audit.sh" --json \
  | jq -r --arg t "$T" '"repos_scanned=\(.repos_scanned) truncated=\(.truncated)", (.findings[] | "\(.severity)\t\(.class)\t\(.repo)\t\(.branch // .path | tostring | sub($t; "<scratch>"))\ttask=\(.task)\tcommits=\(.commits)\tevidence=\(.evidence)")'
say "fm-fleet-view.sh (heartbeat review) - Cleanup section"
FM_HOME="$H" "$ROOT/bin/fm-fleet-view.sh" | sed -n '/^## Cleanup/,/^## Secondmates/p' | sed "s#$T#<scratch>#g"

fingerprint > "$T/after.txt"
say "read-only check: repo refs, worktrees, dirty status, claims unchanged"
if diff "$T/before.txt" "$T/after.txt" >/dev/null; then echo "UNCHANGED"; else echo "CHANGED"; diff "$T/before.txt" "$T/after.txt"; fi

# --- watcher heartbeat -------------------------------------------------------------
FB=$T/fakebin; mkdir -p "$FB"
printf '#!/usr/bin/env bash\n[ "${1:-}" = list-windows ] && exit 0\n[ "${1:-}" = capture-pane ] && exit 0\nexit 1\n' > "$FB/tmux"
printf '#!/usr/bin/env bash\necho "state: working · source: fake · live"\n' > "$FB/fm-crew-state.sh"
chmod +x "$FB/tmux" "$FB/fm-crew-state.sh"
S=$H/state
watch_once() {  # <label> [env...] : run one watcher and report exit or absorb
  local label=$1 out=$T/watch.out pid i=0 rc
  shift
  rm -f "$S/.heartbeat-streak"; : > "$out"
  env PATH="$FB:$PATH" FM_HOME="$H" FM_STATE_OVERRIDE="$S" FM_CREW_STATE_BIN="$FB/fm-crew-state.sh" \
    FM_POLL=1 FM_SIGNAL_GRACE=1 FM_CHECK_INTERVAL=999999 FM_HEARTBEAT=1 "$@" \
    "$ROOT/bin/fm-watch.sh" > "$out" 2>"$T/watch.err" &
  pid=$!
  while [ "$i" -lt 150 ]; do
    kill -0 "$pid" 2>/dev/null || break
    [ "$(cat "$S/.heartbeat-streak" 2>/dev/null || echo 0)" -ge 1 ] && break
    sleep 0.1; i=$((i + 1))
  done
  if kill -0 "$pid" 2>/dev/null; then
    sleep 0.5; kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
    echo "[$label] watcher kept running; heartbeat absorbed (streak=$(cat "$S/.heartbeat-streak" 2>/dev/null)); wake output: '$(cat "$out")'"
  else
    wait "$pid"; rc=$?
    echo "[$label] watcher exited rc=$rc with wake reason: '$(cat "$out")'"
  fi
  echo "[$label] .hygiene-surfaced now holds $(grep -c . "$S/.hygiene-surfaced" 2>/dev/null || echo 0) finding keys"
}
ack() {
  local err=$T/drain.err seq gen
  FM_STATE_OVERRIDE="$S" "$ROOT/bin/fm-wake-drain.sh" >/dev/null 2>"$err"
  seq=$(sed -n 's/^WAKE_ACK_REQUIRED:.*--ack-through \([0-9]*\) --recovery-generation.*/\1/p' "$err")
  gen=$(sed -n 's/^WAKE_ACK_REQUIRED:.*--recovery-generation \([A-Za-z0-9._-]*\)$/\1/p' "$err")
  FM_STATE_OVERRIDE="$S" "$ROOT/bin/fm-wake-drain.sh" --ack-through "$seq" --recovery-generation "$gen" >/dev/null 2>&1
  echo "(captain drained and acked the heartbeat wake)"
}
say "watcher: first heartbeat with new cleanup findings"
watch_once first-heartbeat
sed "s#$T#<scratch>#g" "$S/.hygiene-surfaced" | tr '\t' ' '
ack
say "watcher: next heartbeat, same standing findings"
watch_once standing FM_WATCH_HANDLING_SUCCESSOR=1
say "watcher adversarial: audit fails (invalid bound) - must wake nothing and keep the surfaced set"
cp "$S/.hygiene-surfaced" "$T/surfaced.before"
watch_once audit-failure FM_WATCH_HANDLING_SUCCESSOR=1 FM_HYGIENE_BRANCH_LIMIT=abc
cmp -s "$T/surfaced.before" "$S/.hygiene-surfaced" && echo "surfaced set UNCHANGED after audit failure" || echo "surfaced set CHANGED after audit failure"
say "watcher adversarial: audit disabled (FM_HEARTBEAT_HYGIENE=0)"
watch_once disabled FM_WATCH_HANDLING_SUCCESSOR=1 FM_HEARTBEAT_HYGIENE=0
cmp -s "$T/surfaced.before" "$S/.hygiene-surfaced" && echo "surfaced set UNCHANGED while disabled" || echo "surfaced set CHANGED while disabled"
say "watcher: after the failure, the standing set still does not re-wake"
watch_once post-failure FM_WATCH_HANDLING_SUCCESSOR=1
say "watcher: a NEW leftover appears (another unpushed fm/* branch)"
git -C "$A" checkout -q -b fm/abandoned "$base"; cm "$A" ab.txt ab "abandoned"; git -C "$A" checkout -q main
watch_once new-finding FM_WATCH_HANDLING_SUCCESSOR=1
ack
say "watcher: a finding clears (clone refreshed) - drops out of the surfaced set, no wake"
git -C "$A" merge -q --ff-only origin/main
watch_once cleared FM_WATCH_HANDLING_SUCCESSOR=1
grep -c clone-behind "$S/.hygiene-surfaced" | sed 's/^/clone-behind keys remaining: /'
rm -rf "$T"
