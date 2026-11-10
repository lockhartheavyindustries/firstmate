# Appended to a test-less copy of tests/fm-teardown.test.sh (reuses make_case,
# write_meta, run_teardown, prepare_scout_teardown). Swaps the fake treehouse
# for the REAL treehouse binary on an isolated TREEHOUSE_ROOT/HOME per case.
REAL_TH=$(PATH=$FM_LIVE_ORIG_PATH command -v treehouse)
live_case() {  # <name> -> echoes case_dir; slot path in $case_dir/slot
  local name=$1 case_dir slot
  case_dir=$(make_case "$name")
  mkdir -p "$case_dir/thhome"
  cat > "$case_dir/fakebin/treehouse" <<SH
#!/usr/bin/env bash
export TREEHOUSE_ROOT="$case_dir/thpool" HOME="$case_dir/thhome"
exec "$REAL_TH" "\$@"
SH
  chmod +x "$case_dir/fakebin/treehouse"
  git -C "$case_dir/project" worktree remove "$case_dir/wt"
  git -C "$case_dir/project" branch -D fm/task-x1 >/dev/null
  slot=$(cd "$case_dir/project" && "$case_dir/fakebin/treehouse" get --lease 2>/dev/null)
  git -C "$slot" switch -q -c fm/task-x1
  printf '%s\n' "$slot" > "$case_dir/slot"
  printf '%s\n' "$case_dir"
}
th() { local c=$1; shift; (cd "$c/project" && "$c/fakebin/treehouse" "$@"); }
report() {  # <case_dir> <label> <rc>
  local c=$1 slot; slot=$(cat "$c/slot")
  echo "--- $2: teardown rc=$3"
  echo "stderr:"; sed 's/^/  | /' "$c/stderr"
  echo "slot HEAD     : $(git -C "$slot" rev-parse HEAD) ($(git -C "$slot" rev-parse --abbrev-ref HEAD))"
  echo "origin/main   : $(git -C "$c/project" rev-parse origin/main)"
  echo "local main    : $(git -C "$c/project" rev-parse main)"
  echo "branches      : $(git -C "$c/project" for-each-ref --format='%(refname:short)=%(objectname:short)' refs/heads | tr '\n' ' ')"
  echo "slot dirty?   : '$(git -C "$slot" status --porcelain)'"
  echo "treehouse status after teardown:"; th "$c" status 2>&1 | sed 's/^/  | /'
  local next; next=$(th "$c" get --lease 2>/dev/null)
  echo "next 'treehouse get --lease' -> $next"
  if [ "$next" = "$slot" ]; then echo "RESULT: slot RECYCLED"; else echo "RESULT: slot STRANDED (new slot created)"; fi
  th "$c" return "$next" >/dev/null 2>&1 || true
}
live_A() {  # local-only, landed in local main
  local c rc; c=$(live_case liveA); local slot; slot=$(cat "$c/slot")
  git -C "$slot" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "local-only landed"
  git -C "$c/project" update-ref refs/heads/main "$(git -C "$slot" rev-parse HEAD)"
  write_meta "$c" local-only ship "$slot"
  rc=0; FM_HOME="$c" run_teardown "$c" >"$c/stdout" 2>"$c/stderr" || rc=$?
  report "$c" "A local-only landed in local main" $rc
}
live_B() {  # local-only, work only on the local task branch, --force
  local c rc; c=$(live_case liveB); local slot; slot=$(cat "$c/slot")
  git -C "$slot" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "local branch only"
  echo "task commit   : $(git -C "$slot" rev-parse HEAD)"
  write_meta "$c" local-only ship "$slot"
  rc=0; FM_HOME="$c" run_teardown "$c" --force >"$c/stdout" 2>"$c/stderr" || rc=$?
  report "$c" "B local-only, commit only on local task branch, --force" $rc
}
live_C() {  # scout: teardown deletes task branch -> HEAD held by no branch
  local c rc; c=$(live_case liveC); local slot; slot=$(cat "$c/slot")
  git -C "$slot" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "never landed"
  echo "task commit   : $(git -C "$slot" rev-parse HEAD)"
  write_meta "$c" no-mistakes scout "$slot"
  prepare_scout_teardown "$c"
  rc=0; FM_HOME="$c" run_teardown "$c" >"$c/stdout" 2>"$c/stderr" || rc=$?
  report "$c" "C scout, HEAD held by no branch" $rc
}
live_D() {  # work already published on origin -> slot must not be moved
  local c rc; c=$(live_case liveD); local slot; slot=$(cat "$c/slot")
  git -C "$slot" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "published"
  git -C "$slot" push -q origin HEAD:refs/heads/fm/task-x1; git -C "$c/project" fetch -q origin
  echo "task commit   : $(git -C "$slot" rev-parse HEAD) (pushed to origin/fm/task-x1)"
  write_meta "$c" local-only ship "$slot"
  rc=0; FM_HOME="$c" run_teardown "$c" >"$c/stdout" 2>"$c/stderr" || rc=$?
  report "$c" "D HEAD already on a remote-tracking branch" $rc
}
for f in ${FM_LIVE_CASES:-live_A live_B live_C live_D}; do $f; done
