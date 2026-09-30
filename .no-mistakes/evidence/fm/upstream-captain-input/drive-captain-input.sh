#!/usr/bin/env bash
# Live lab driver for opt-in captain input (run from the gate worktree).
set -u
ROOT=$PWD
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX"); rmdir "$LAB"
bin/fm-lab-home.sh create "$LAB" >/dev/null
trap 'kill $(jobs -p) 2>/dev/null; rm -rf "$LAB"' EXIT
export FM_HOME=$LAB
unset NO_MISTAKES_GATE FM_GATE_REFUSE_BYPASS FM_ROOT_OVERRIDE FM_STATE_OVERRIDE FM_DATA_OVERRIDE FM_CONFIG_OVERRIDE FM_PROJECTS_OVERRIDE
S=$LAB/state
printf 'tmux\n' > "$LAB/config/backend"
say() { printf '\n=== %s\n' "$*"; }
run() { printf '$ %s\n' "$*"; "$@"; rc=$?; printf '[exit %s]\n' "$rc"; return $rc; }
needed() { bash -c '. "$1/bin/fm-supervision-lib.sh"; fm_supervision_needed "$2"' x "$ROOT" "$S" && echo needed=true || echo needed=false; }
# A double-forked process reparented to launchd: outside the Claude harness ancestry,
# exactly like the away/quiet supervision daemon.
detached() { python3 - "$@" <<'PY'
import os, sys
r, w = os.pipe()
if os.fork() == 0:
    os.setsid()
    if os.fork() == 0:
        os.dup2(w, 1); os.dup2(w, 2)
        os.execvp(sys.argv[1], sys.argv[1:])
    os._exit(0)
os.close(w); os.wait()
out = b""
while True:
    b = os.read(r, 65536)
    if not b: break
    out += b
sys.stdout.write(out.decode())
PY
}
qdump() { echo "--- state/.wake-queue:"; cat "$S/.wake-queue" 2>/dev/null; echo "---"; }

say "S1 default-off: note without subscription keeps legacy behavior"
needed
run bin/fm-inbox.sh note --request-id legacy-1 'LEGACY_BODY hello'
qdump
[ -e "$S/.captain-input-notify" ] && echo "doorbell present (UNEXPECTED)" || echo "no doorbell file (expected)"
run bin/fm-inbox.sh drain --ack '../bogus' 'no-such-id'
lid=$(ls "$S/inbox" | grep '\.note$' | sed 's/\.note$//')
run bin/fm-inbox.sh drain --ack "$lid"
bin/fm-wake-drain.sh > "$LAB/l.out" 2> "$LAB/l.err"
run bin/fm-wake-drain.sh --ack-through "$(awk -F '\t' 'NF==5{print $2}' "$LAB/l.out" | tail -1)" --recovery-generation "$(sed -n 's/^WAKE_ACK_REQUIRED:.*--recovery-generation //p' "$LAB/l.err")"
qdump

say "S2 lock: this Claude session (real harness ancestry) takes the lab session lock"
run bin/fm-lock.sh
run bin/fm-lock.sh status

say "S3 non-owner (detached daemon-style process) may not subscribe"
detached "$ROOT/bin/fm-inbox.sh" subscribe; echo "[registration file present? $( [ -f "$S/.captain-input" ] && echo yes || echo no)]"

say "S4 owner subscribes: idle home now demands supervision with zero tasks"
needed
run bin/fm-inbox.sh subscribe
cat "$S/.captain-input"
needed

say "S5 idle real watcher (FM_POLL=30) wakes promptly on an external note"
touch "$S/.last-check"
FM_POLL=30 FM_HEARTBEAT=999999 FM_CHECK_INTERVAL=999999 bin/fm-watch.sh > "$LAB/watch.out" 2> "$LAB/watch.err" &
wpid=$!
for i in $(seq 100); do [ -f "$S/.last-watcher-beat" ] && break; sleep 0.1; done
sleep 2
echo "watcher still running idle before note: $(kill -0 $wpid 2>/dev/null && echo yes || echo no); stdout so far: [$(cat "$LAB/watch.out")]"
t0=$(python3 -c 'import time;print(time.time())')
bin/fm-inbox.sh note --json --request-id slack-msg-0001 'PRIVATE_SLACK_TEXT please check the build' > "$LAB/note.json"
cat "$LAB/note.json"; echo
for i in $(seq 300); do kill -0 $wpid 2>/dev/null || break; sleep 0.05; done
t1=$(python3 -c 'import time;print(time.time())')
wait $wpid; echo "[watcher exit $?]"
echo "watcher stdout:"; cat "$LAB/watch.out"
python3 -c "print('note-to-watcher-wake latency: %.2fs (fleet poll is 30s)' % ($t1-$t0))"
qdump
echo "doorbell: $(cat "$S/.captain-input-notify")"
grep -c PRIVATE_SLACK_TEXT "$S/.wake-queue" "$S/.captain-input-notify" | sed 's/^/body occurrences /'
nid=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["id"])' "$LAB/note.json")

say "S6 duplicate delivery of the same listener message id is a replay with no second wake"
run bin/fm-inbox.sh note --request-id slack-msg-0001 'PRIVATE_SLACK_TEXT please check the build'
echo "inbox rows queued: $(grep -c 'inbox:' "$S/.wake-queue")"

say "S7 owner drain: ack before handling is refused; handle note; ack; exactly one receipt"
bin/fm-wake-drain.sh > "$LAB/d.out" 2> "$LAB/d.err"; cat "$LAB/d.out"; grep WAKE_ACK "$LAB/d.err"
seq=$(awk -F '\t' 'NF==5{print $2}' "$LAB/d.out" | tail -1)
gen=$(sed -n 's/^WAKE_ACK_REQUIRED:.*--recovery-generation //p' "$LAB/d.err")
run bin/fm-wake-drain.sh --ack-through "$seq" --recovery-generation "$gen"
echo "detached (non-owner) note handling attempt:"; detached "$ROOT/bin/fm-inbox.sh" drain --ack "$nid"
run bin/fm-inbox.sh drain --ack "$nid"
run bin/fm-inbox.sh drain --ack "$nid"
run bin/fm-wake-drain.sh --ack-through "$seq" --recovery-generation "$gen"
qdump
run bin/fm-inbox.sh input-receipts
bin/fm-inbox.sh input-receipts | python3 -m json.tool

say "S8 away daemon: detached non-owner drain + ack retires a batch holding an unhandled input row"
id2=$(bin/fm-inbox.sh note --json --request-id slack-msg-0002 'while away' | python3 -c 'import json,sys;print(json.load(sys.stdin)["id"])')
bash -c '. "$1/bin/fm-wake-lib.sh"; fm_wake_append check ordinary "check: ordinary pr poll"' x "$ROOT"
qdump
detached "$ROOT/bin/fm-wake-drain.sh" > "$LAB/dd.all"
cat "$LAB/dd.all"
seq=$(awk -F '\t' 'NF==5{print $2}' "$LAB/dd.all" | tail -1)
gen=$(sed -n 's/^WAKE_ACK_REQUIRED:.*--recovery-generation //p' "$LAB/dd.all")
detached bash -c '"$0" --ack-through "$1" --recovery-generation "$2"; echo "[daemon ack exit $?]"' "$ROOT/bin/fm-wake-drain.sh" "$seq" "$gen"
qdump
echo "note $id2 still pending for the owner: $( [ -f "$S/inbox/$id2.note" ] && echo yes || echo no)"
echo "receipt for $id2: $( [ -f "$S/.input-ack/$id2" ] && echo yes || echo none)"

say "S9 unsubscribe restores default-off"
run bin/fm-inbox.sh unsubscribe
needed
