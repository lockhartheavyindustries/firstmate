#!/usr/bin/env bash
# Live driver for the captain-input scenarios: real bin/fm-watch.sh,
# bin/fm-watch-arm.sh, bin/fm-inbox.sh and bin/fm-wake-drain.sh from the run
# worktree against disposable marked lab homes (bin/fm-lab-home.sh create).
# Stand-ins, stated plainly: tmux is not installed on this host, so a stub tmux
# that lists no windows is on PATH; the "owning session" is bash invoked under
# the name `claude` that writes its pid to state/.lock (same shape as
# tests/fm-inbox.test.sh). Everything else is the shipped scripts.
# Usage: drive-captain-input.sh <worktree-root>
set -u
ROOT=$1
BASE=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX")
PIDS=()
cleanup() {
  for p in "${PIDS[@]:-}"; do [ -z "$p" ] || kill "$p" 2>/dev/null; done
  rm -rf "$BASE"
}
trap cleanup EXIT

FAKEBIN="$BASE/fakebin"; mkdir -p "$FAKEBIN"
cat > "$FAKEBIN/tmux" <<'SH'
#!/usr/bin/env bash
[ "${1:-}" = list-windows ] && exit 0
[ "${1:-}" = capture-pane ] && exit 0
exit 1
SH
chmod +x "$FAKEBIN/tmux"
ln -s /bin/bash "$FAKEBIN/claude"

now_ms() { python3 -c 'import time; print(int(time.time()*1000))'; }
say() { printf '\n== %s\n' "$*"; }
RESULT=0
ok() { printf 'PASS: %s\n' "$*"; }
bad() { printf 'FAIL: %s\n' "$*"; RESULT=1; }

lab() { # <name> -> prints home
  local h="$BASE/$1"
  "$ROOT/bin/fm-lab-home.sh" create "$h" >/dev/null || exit 1
  printf '%s\n' "$h"
}
fm() { # <home> <cmd...>  : run as an ordinary (non-owner) process
  local h=$1; shift
  env -u FM_ROOT_OVERRIDE -u FM_STATE_OVERRIDE -u FM_DATA_OVERRIDE -u FM_CONFIG_OVERRIDE -u FM_PROJECTS_OVERRIDE \
    PATH="$FAKEBIN:$PATH" FM_HOME="$h" "$@"
}
owned() { # <home> <cmd...> : run under the session-lock owner
  local h=$1; shift
  # shellcheck disable=SC2016
  env -u FM_ROOT_OVERRIDE -u FM_STATE_OVERRIDE -u FM_DATA_OVERRIDE -u FM_CONFIG_OVERRIDE -u FM_PROJECTS_OVERRIDE \
    PATH="$FAKEBIN:$PATH" FM_HOME="$h" \
    "$FAKEBIN/claude" -c 'printf "%s\n" "$$" > "$FM_HOME/state/.lock"; "$@"; exit' owner "$@"
}
start_watcher() { # <home> <poll>
  local h=$1 i
  fm "$h" env FM_POLL="$2" FM_SIGNAL_GRACE=1 FM_CHECK_INTERVAL=999999 FM_HEARTBEAT=999999 \
    "$ROOT/bin/fm-watch.sh" > "$h/watch.out" 2> "$h/watch.err" &
  WPID=$!; PIDS+=("$WPID")
  for i in $(seq 1 100); do
    [ "$(cat "$h/state/.watch.lock/pid" 2>/dev/null)" = "$WPID" ] && [ -e "$h/state/.last-watcher-beat" ] && return 0
    sleep 0.1
  done
  bad "watcher did not take the lock in $h: $(cat "$h/watch.err")"; return 1
}
start_arm() { # <home> <confirm>
  local h=$1 i
  fm "$h" env FM_ARM_ATTACH_POLL=0.1 FM_ARM_CONFIRM_TIMEOUT="$2" "$ROOT/bin/fm-watch-arm.sh" > "$h/arm.out" 2> "$h/arm.err" &
  APID=$!; PIDS+=("$APID")
  for i in $(seq 1 100); do
    grep -qF "watcher: attached pid=$WPID" "$h/arm.out" 2>/dev/null && return 0
    sleep 0.1
  done
  bad "arm did not attach: $(cat "$h/arm.out" "$h/arm.err")"; return 1
}
wait_ms() { # <pid> <max-ms> -> prints elapsed ms, rc 1 if still alive
  local t0; t0=$(now_ms)
  while kill -0 "$1" 2>/dev/null; do
    [ $(( $(now_ms) - t0 )) -lt "$2" ] || { echo $(( $(now_ms) - t0 )); return 1; }
    sleep 0.05
  done
  echo $(( $(now_ms) - t0 ))
}
needed() { bash -c '. "$1/bin/fm-supervision-lib.sh"; fm_supervision_needed "$2/state"' x "$ROOT" "$1"; }

# ---------------------------------------------------------------------------
say "S1 default-off: a note in a home that never subscribed does not ring a doorbell or wake the idle watcher early (poll 30s)"
H=$(lab default-off)
if needed "$H"; then bad "idle default-off home demands supervision"; else ok "idle default-off home demands no supervision"; fi
start_watcher "$H" 30
echo "\$ fm-inbox.sh note 'hello from the desk'"; fm "$H" "$ROOT/bin/fm-inbox.sh" note 'hello from the desk'
el=$(wait_ms "$WPID" 8000) && bad "default-off watcher exited after ${el}ms: $(cat "$H/watch.out")" \
  || ok "watcher still in its 30s poll sleep ${el}ms after the note"
[ ! -e "$H/state/.captain-input-notify" ] && [ ! -e "$H/state/.captain-input" ] \
  && ok "no .captain-input / .captain-input-notify files exist" || bad "doorbell files appeared in a default-off home"
echo "wake queue row (existing behavior, body in payload as before):"; cat "$H/state/.wake-queue"
echo "\$ fm-inbox.sh input-receipts"; fm "$H" "$ROOT/bin/fm-inbox.sh" input-receipts
kill "$WPID" 2>/dev/null; wait "$WPID" 2>/dev/null

# ---------------------------------------------------------------------------
say "S2 subscribe is owner-only and default-off until the owner opts in"
H=$(lab subscribed)
echo "\$ (non-owner) fm-inbox.sh subscribe"
if fm "$H" "$ROOT/bin/fm-inbox.sh" subscribe; then bad "non-owner subscribe succeeded"; else ok "non-owner subscribe refused (rc=$?)"; fi
[ ! -e "$H/state/.captain-input" ] && ok "refused subscribe left no registration" || bad "refused subscribe wrote the registration"
echo "\$ (owner) fm-inbox.sh subscribe"
owned "$H" "$ROOT/bin/fm-inbox.sh" subscribe && [ -f "$H/state/.captain-input" ] \
  && ok "owner subscribe wrote state/.captain-input ($(cat "$H/state/.captain-input"))" || bad "owner subscribe failed"
needed "$H" && ok "subscribed idle home now demands supervision" || bad "subscription did not create demand"
echo "\$ fm-inbox.sh input-receipts"; fm "$H" "$ROOT/bin/fm-inbox.sh" input-receipts

# ---------------------------------------------------------------------------
say "S3 subscribed: an idle watcher in a 30s poll sleep wakes promptly on a new inbox note"
start_watcher "$H" 30
sleep 1.5   # let the cycle reach its terminal poll sleep
t0=$(now_ms)
echo "\$ fm-inbox.sh note 'PRIVATE_BODY please look at the deploy'"
NOTE_OUT=$(fm "$H" "$ROOT/bin/fm-inbox.sh" note 'PRIVATE_BODY please look at the deploy'); echo "$NOTE_OUT"
ID=${NOTE_OUT#queued }; ID=${ID%%$'\n'*}
if el=$(wait_ms "$WPID" 10000); then
  total=$(( $(now_ms) - t0 ))
  [ "$total" -lt 5000 ] && ok "watcher closed ${total}ms after the note (poll interval is 30000ms)" \
    || bad "watcher took ${total}ms"
else bad "watcher still asleep ${el}ms after the note"; fi
echo "watcher stdout: $(cat "$H/watch.out")"
grep -q "^check: captain-input [0-9]* $ID\$" "$H/watch.out" && ok "watcher reason names the queue sequence and note id" \
  || bad "watcher reason is not the captain-input receipt"
echo "doorbell: $(cat "$H/state/.captain-input-notify")"; echo "wake queue:"; cat "$H/state/.wake-queue"
grep -q PRIVATE_BODY "$H/state/.wake-queue" "$H/state/.captain-input-notify" "$H/watch.out" \
  && bad "note body leaked into queue/doorbell/banner" || ok "queue, doorbell and reason line carry no note body"
[ "$(grep -c "inbox:$ID" "$H/state/.wake-queue")" = 1 ] && ok "exactly one queue row for the note (no redundant wake row)" \
  || bad "unexpected queue row count"

# ---------------------------------------------------------------------------
say "S5 owner handles the note: wake ack is refused before the note is handled, then exactly one receipt"
owned "$H" "$ROOT/bin/fm-wake-drain.sh" > "$H/drain.out" 2> "$H/drain.err"; cat "$H/drain.out"; grep WAKE_ACK_REQUIRED "$H/drain.err"
SEQ=$(awk -F '\t' 'NF == 5 {print $2}' "$H/drain.out" | tail -1)
GEN=$(sed -n 's/^WAKE_ACK_REQUIRED:.*--recovery-generation //p' "$H/drain.err")
echo "\$ (owner) fm-wake-drain.sh --ack-through $SEQ   # note not yet handled"
if owned "$H" "$ROOT/bin/fm-wake-drain.sh" --ack-through "$SEQ" --recovery-generation "$GEN"; then
  bad "wake ack consumed an unhandled note"; else ok "wake ack refused while the note is unhandled"; fi
echo "\$ (non-owner) fm-inbox.sh drain --ack $ID"
if fm "$H" "$ROOT/bin/fm-inbox.sh" drain --ack "$ID"; then bad "non-owner handled subscribed input"; else ok "non-owner note ack refused"; fi
echo "\$ (owner) fm-inbox.sh drain --ack $ID"; owned "$H" "$ROOT/bin/fm-inbox.sh" drain --ack "$ID"
echo "\$ (owner) fm-wake-drain.sh --ack-through $SEQ"
owned "$H" "$ROOT/bin/fm-wake-drain.sh" --ack-through "$SEQ" --recovery-generation "$GEN" && ok "owner wake ack succeeded after handling" || bad "owner wake ack failed"
echo "\$ fm-inbox.sh input-receipts"; R=$(fm "$H" "$ROOT/bin/fm-inbox.sh" input-receipts); echo "$R"
n=$(printf '%s' "$R" | python3 -c 'import json,sys; d=json.load(sys.stdin); r=d["records"]; print(len(r), r[0].get("queue_acknowledged"), r[0].get("note_handled")) if r else print(0)')
[ "$n" = "1 True True" ] && ok "exactly one input receipt, queue acknowledged, note handled" || bad "receipts: $n"
[ ! -s "$H/state/.wake-queue" ] && ok "wake queue is empty after the ack" || bad "queue not empty: $(cat "$H/state/.wake-queue")"

# ---------------------------------------------------------------------------
say "S4 attached arm (the merge-resolved path): arm forwards the input delivery without spending its 20s successor window"
start_watcher "$H" 30
start_arm "$H" 20
t0=$(now_ms)
NOTE_OUT=$(fm "$H" "$ROOT/bin/fm-inbox.sh" note 'second note'); echo "$NOTE_OUT"
ID2=${NOTE_OUT#queued }; ID2=${ID2%%$'\n'*}
wait_ms "$WPID" 10000 >/dev/null || bad "watcher did not close"
if el=$(wait_ms "$APID" 10000); then
  wait "$APID"; rc=$?; total=$(( $(now_ms) - t0 ))
  ok "arm exited rc=$rc ${total}ms after the note (successor window is 20000ms)"
  [ "$rc" = 0 ] || bad "arm exit code $rc"
else bad "arm still waiting ${el}ms after the watcher closed (spent the successor window)"; fi
echo "arm stdout:"; cat "$H/arm.out"
grep -q "^check: captain-input [0-9]* $ID2\$" "$H/arm.out" && ok "arm printed the exact delivery reason" || bad "arm omitted the captain-input reason"
grep -qF 'watcher: FAILED' "$H/arm.out" && bad "arm reported FAILED" || ok "arm reported no failure"
echo "cycle ledger tail:"; tail -3 "$H/state/.watch-cycle-exits.log"
grep -q 'reason=attached-delivered-wake' "$H/state/.watch-cycle-exits.log" && ok "ledger classifies the close as attached-delivered-wake" || bad "ledger missing attached-delivered-wake"

# ---------------------------------------------------------------------------
say "S6 away/quiet daemon-style actor (not the session owner) retires the inbox row and writes no receipt"
fm "$H" "$ROOT/bin/fm-wake-drain.sh" > "$H/d2.out" 2> "$H/d2.err"; cat "$H/d2.out"
SEQ=$(awk -F '\t' 'NF == 5 {print $2}' "$H/d2.out" | tail -1)
GEN=$(sed -n 's/^WAKE_ACK_REQUIRED:.*--recovery-generation //p' "$H/d2.err")
echo "\$ (non-owner) fm-wake-drain.sh --ack-through $SEQ"
fm "$H" "$ROOT/bin/fm-wake-drain.sh" --ack-through "$SEQ" --recovery-generation "$GEN" && ok "non-owner drain+ack succeeded" || bad "non-owner ack failed (daemon wedge)"
[ ! -s "$H/state/.wake-queue" ] && ok "batch retired" || bad "rows stayed queued: $(cat "$H/state/.wake-queue")"
[ ! -e "$H/state/.input-ack/$ID2" ] && ok "no input receipt written for the unhandled note" || bad "receipt written by non-owner"

# ---------------------------------------------------------------------------
say "S7 adversarial: subscribed home, ORDINARY (non-input) wake - the attached arm must not take the input shortcut"
H2=$(lab ordinary); owned "$H2" "$ROOT/bin/fm-inbox.sh" subscribe
H=$H2; start_watcher "$H" 5; start_arm "$H" 1
printf 'done: fixture finished\n' > "$H/state/demo.status"
wait_ms "$WPID" 20000 >/dev/null || bad "watcher did not close on the signal"
wait_ms "$APID" 20000 >/dev/null || bad "arm did not close"
wait "$APID"; rc=$?
echo "arm stdout:"; cat "$H/arm.out"
grep -q '^signal:' "$H/arm.out" && ! grep -q 'captain-input' "$H/arm.out" && [ "$rc" = 0 ] \
  && ok "ordinary wake still reported as signal: through the upstream close path (rc=0)" || bad "ordinary wake mis-routed (rc=$rc)"

say "S8 adversarial: unsubscribe restores default-off - next note does not wake the idle watcher early"
owned "$H" "$ROOT/bin/fm-inbox.sh" unsubscribe && [ ! -e "$H/state/.captain-input" ] && ok "owner unsubscribe removed the registration" || bad "unsubscribe failed"
fm "$H" "$ROOT/bin/fm-wake-drain.sh" > "$H/d3.out" 2> "$H/d3.err"
SEQ=$(awk -F '\t' 'NF == 5 {print $2}' "$H/d3.out" | tail -1); GEN=$(sed -n 's/^WAKE_ACK_REQUIRED:.*--recovery-generation //p' "$H/d3.err")
fm "$H" "$ROOT/bin/fm-wake-drain.sh" --ack-through "$SEQ" --recovery-generation "$GEN"
rm -f "$H/state/demo.status"
start_watcher "$H" 30; sleep 1.5
fm "$H" "$ROOT/bin/fm-inbox.sh" note 'after unsubscribe'
el=$(wait_ms "$WPID" 8000) && bad "unsubscribed watcher exited after ${el}ms: $(cat "$H/watch.out")" \
  || ok "watcher still in its 30s poll sleep ${el}ms after the note"
kill "$WPID" 2>/dev/null; wait "$WPID" 2>/dev/null

say "RESULT: $([ "$RESULT" = 0 ] && echo ALL PASS || echo FAILURES)"
exit "$RESULT"
