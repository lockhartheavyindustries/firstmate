#!/usr/bin/env bash
# Drive the slot-reuse incident through the real fm-spawn.sh / fm-teardown.sh /
# fm-crew-state.sh CLIs against an isolated FM_HOME (fake terminal backend only).
# Usage: slot-reuse-scenarios.sh <repo-root-under-test> <test-file-with-helpers>
set -u
TREE=$1 HELPERS=$2
cd "$TREE"
# Load the suite's case helpers (make_case, run_spawn, lay_out_as_pool_slot) without running its tests.
HLP="$TREE/tests/.slot-reuse-helpers.$$.sh"
{ sed -n '1,/^test_remote_seeded_home_spawns_from_treehouse_pool() {/p' "$HELPERS" | sed '$d'; sed -n '/^lay_out_as_pool_slot() {/,/^}/p' "$HELPERS"; } > "$HLP"
. "$HLP"; rm -f "$HLP"
ROOT=$TREE
tdown() { FM_ROOT_OVERRIDE='' FM_HOME="$HOME_DIR" PATH="$FAKEBIN_DIR:$PATH" "$ROOT/bin/fm-teardown.sh" "$@" 2>&1; }
cstate() { FM_ROOT_OVERRIDE='' FM_HOME="$HOME_DIR" PATH="$FAKEBIN_DIR:$PATH" "$ROOT/bin/fm-crew-state.sh" "$@" 2>&1; }
section() { printf '\n===== %s =====\n' "$*"; }

section "SCENARIO 1: incident repro - old task's worker exited, record still names slot 1; pool hands slot 1 to a new task"
old=openclaw-cron-optimization-checker-count; id=openclaw-fallback-chain-astra
rec=$(make_case incident "$id"); read_case_record "$rec"; lay_out_as_pool_slot
fm_write_meta "$HOME_DIR/state/$old.meta" "window=firstmate:fm-$old" "endpoint_task_id=$old" \
  "worktree=$POOL_DIR" "project=$PROJECT_DIR" "kind=ship" "mode=no-mistakes" "yolo=off" \
  "pr=https://github.com/example/project/pull/7" "pr_head=$(git -C "$POOL_DIR" rev-parse HEAD)"
printf 'task=%s\nhome=%s\n' "$old" "$HOME_DIR" > "$SLOT_CLAIM"
echo "\$ fm-spawn.sh $id <project> --scout"; run_spawn "$id" --scout | grep -E "spawned|note:|warning:|error" ; echo "exit=${PIPESTATUS[0]}"
echo "--- slot claim after spawn:"; cat "$SLOT_CLAIM"
echo "--- old record after spawn ($old.meta):"; cat "$HOME_DIR/state/$old.meta"
echo "--- \$ fm-crew-state.sh $old"; cstate "$old"
echo "--- \$ fm-spawn.sh $old --relaunch"; fm_test_run_spawn "$HOME_DIR" "$POOL_DIR" "$FAKEBIN_DIR" "$old" --relaunch | tail -3; echo "exit=${PIPESTATUS[0]}"
echo "--- \$ fm-teardown.sh $id --force   (the teardown that was refused on 2026-09-23)"; tdown "$id" --force | tail -6; echo "exit=${PIPESTATUS[0]}"
echo "--- new record gone? $( [ -e "$HOME_DIR/state/$id.meta" ] && echo NO-still-present || echo yes)"
printf 'task=later-task\nhome=%s\n' "$HOME_DIR" > "$SLOT_CLAIM"; : > "$POOL_DIR/later-task-work"
echo "--- slot handed on again to later-task; \$ fm-teardown.sh $old"; tdown "$old" | tail -6; echo "exit=${PIPESTATUS[0]}"
echo "--- later-task's file survived old cleanup? $( [ -e "$POOL_DIR/later-task-work" ] && echo yes || echo NO)"
echo "--- claim still names later-task? $(grep -c '^task=later-task$' "$SLOT_CLAIM")"

section "SCENARIO 2 (adversarial): a secondmate record naming the same slot is a genuine collision, not retired"
id=adv-new-task; sm=adv-secondmate
rec=$(make_case adv-secondmate "$id"); read_case_record "$rec"; lay_out_as_pool_slot
fm_write_meta "$HOME_DIR/state/$sm.meta" "window=firstmate:fm-$sm" "endpoint_task_id=$sm" \
  "worktree=$POOL_DIR" "home=$POOL_DIR" "project=$PROJECT_DIR" "kind=secondmate"
printf 'task=%s\nhome=%s\n' "$sm" "$HOME_DIR" > "$SLOT_CLAIM"
echo "\$ fm-spawn.sh $id <project> --scout"; run_spawn "$id" --scout | grep -E "spawned|note:|warning:|error|REFUSED" ; echo "exit=${PIPESTATUS[0]}"
echo "--- secondmate record reassigned marker present? $(grep -c '^worktree_reassigned_to=' "$HOME_DIR/state/$sm.meta")"
if [ -e "$HOME_DIR/state/$id.meta" ]; then echo "--- \$ fm-teardown.sh $id --force"; tdown "$id" --force | grep -E "REFUSED|error|torn|done" | head -4; echo "exit=${PIPESTATUS[0]}"; fi

section "SCENARIO 3 (adversarial): an unrelated record on a different slot is left untouched"
id=adv-other-new; other=adv-other-slot
rec=$(make_case adv-other "$id"); read_case_record "$rec"; lay_out_as_pool_slot
mkdir -p "$CASE_DIR/slots/2/project"
fm_write_meta "$HOME_DIR/state/$other.meta" "window=firstmate:fm-$other" "endpoint_task_id=$other" \
  "worktree=$CASE_DIR/slots/2/project" "project=$PROJECT_DIR" "kind=ship"
cp "$HOME_DIR/state/$other.meta" "$CASE_DIR/other.before"
run_spawn "$id" --scout | grep -E "spawned|note:|warning:" ; echo "exit=${PIPESTATUS[0]}"
cmp -s "$CASE_DIR/other.before" "$HOME_DIR/state/$other.meta" && echo "--- other-slot record unchanged: yes" || echo "--- other-slot record unchanged: NO"
