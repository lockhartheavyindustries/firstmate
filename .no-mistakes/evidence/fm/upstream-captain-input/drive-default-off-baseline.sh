#!/usr/bin/env bash
# Baseline: without subscription an idle watcher is not woken by a note before its poll.
set -u
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX"); rmdir "$LAB"; bin/fm-lab-home.sh create "$LAB" >/dev/null
trap 'kill $(jobs -p) 2>/dev/null; rm -rf "$LAB"' EXIT
export FM_HOME=$LAB; unset NO_MISTAKES_GATE FM_GATE_REFUSE_BYPASS FM_ROOT_OVERRIDE FM_STATE_OVERRIDE FM_DATA_OVERRIDE FM_CONFIG_OVERRIDE FM_PROJECTS_OVERRIDE
S=$LAB/state; printf 'tmux\n' > "$LAB/config/backend"; touch "$S/.last-check"
FM_POLL=30 FM_HEARTBEAT=999999 FM_CHECK_INTERVAL=999999 bin/fm-watch.sh > "$LAB/watch.out" 2>&1 &
wpid=$!; for i in $(seq 100); do [ -f "$S/.last-watcher-beat" ] && break; sleep 0.1; done; sleep 2
bin/fm-inbox.sh note --request-id base-1 'default-off note' >/dev/null
sleep 5
echo "default-off: 5s after note, watcher still sleeping: $(kill -0 $wpid 2>/dev/null && echo yes || echo no); stdout=[$(cat "$LAB/watch.out")]; doorbell file: $( [ -e "$S/.captain-input-notify" ] && echo present || echo absent)"
echo "queue: $(cat "$S/.wake-queue")"
