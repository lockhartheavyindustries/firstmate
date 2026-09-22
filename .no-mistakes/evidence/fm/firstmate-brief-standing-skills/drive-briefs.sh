#!/usr/bin/env bash
# Live driver: scaffold ship/scout/secondmate briefs under an isolated FM_HOME
# with and without config/standing-skills, then try to break the parser.
set -u
ROOT=$1; EV=$2
HOME_DIR=$(mktemp -d "${TMPDIR:-/tmp}/fm-standing-skills-live.XXXXXX")
CFG="$HOME_DIR/config"; mkdir -p "$CFG" "$HOME_DIR/data"
echo "isolated FM_HOME=$HOME_DIR"
scaffold() { # <kind> <id>
  case "$1" in
    ship) FM_HOME="$HOME_DIR" "$ROOT/bin/fm-brief.sh" "$2" demo-proj --mode no-mistakes ;;
    scout) FM_HOME="$HOME_DIR" "$ROOT/bin/fm-brief.sh" "$2" demo-proj --scout ;;
    secondmate) FM_HOME="$HOME_DIR" FM_SECONDMATE_CHARTER='Supervise assigned work.' "$ROOT/bin/fm-brief.sh" "$2" --secondmate --no-projects ;;
  esac
}
echo "== A. absent list -> baseline briefs =="
for k in ship scout secondmate; do
  scaffold $k base-$k >/dev/null || { echo "FAIL: baseline $k"; exit 1; }
  cp "$HOME_DIR/data/base-$k/brief.md" "$EV/brief-$k-no-standing-skills.md"
  grep -c 'Standing skills' "$HOME_DIR/data/base-$k/brief.md" | sed "s/^/  $k baseline 'Standing skills' occurrences: /"
done
echo "== B. comment-only list -> byte-identical =="
printf '%s\n' '# nothing yet' '' '   ' '# kun  (commented out)' > "$CFG/standing-skills"
for k in ship scout secondmate; do
  scaffold $k skillfree-$k >/dev/null || { echo "FAIL: skill-free $k"; exit 1; }
  if cmp -s "$HOME_DIR/data/base-$k/brief.md" "$HOME_DIR/data/skillfree-$k/brief.md"; then echo "  $k: byte-identical to baseline (cmp)"; else echo "  $k: DIFFERS"; diff "$HOME_DIR/data/base-$k/brief.md" "$HOME_DIR/data/skillfree-$k/brief.md"; fi
done
echo "== C. standing-skills = kun (the captain's ask) =="
printf '%s\n' '# captain standing skills' 'kun' > "$CFG/standing-skills"
for k in ship scout secondmate; do
  scaffold $k kun-$k >/dev/null || { echo "FAIL: kun $k"; exit 1; }
  b="$HOME_DIR/data/kun-$k/brief.md"
  cp "$b" "$EV/brief-$k-with-kun.md"
  echo "  --- $k: paragraph count=$(grep -c 'Standing skills' "$b"); section placement (section heading -> paragraph -> next heading) ---"
  if [ $k = secondmate ]; then awk '/^# Operating model$/{p=1} p{print "    "$0} /^# The captain and the parent channel$/{if(p)exit}' "$b" | grep -n 'Standing skills\|^    # ' ; else awk '/^# Setup$/{p=1} p{print "    "$0} /^# Rules$/{if(p)exit}' "$b" | grep -n 'Standing skills\|^    # '; fi
  diff -u "$HOME_DIR/data/base-$k/brief.md" "$b" > "$EV/diff-$k-baseline-vs-kun.diff"; echo "  diff saved: diff-$k-baseline-vs-kun.diff ($(grep -c '^+[^+]' "$EV/diff-$k-baseline-vs-kun.diff") added lines)"
done
echo "== D. two skills incl. plugin-namespaced, trailing comment, odd whitespace =="
printf '%s\n' '  kun   # trailing comment' '' 'plugin:review-kit' > "$CFG/standing-skills"
scaffold scout two-scout >/dev/null || { echo "FAIL: two-skill scout"; exit 1; }
grep 'Standing skills' "$HOME_DIR/data/two-scout/brief.md" | sed 's/^/  /'
grep -q 'on Claude\|Gemini\|Cursor' "$HOME_DIR/data/two-scout/brief.md" && echo "  FAIL: harness list still present" || echo "  no per-harness enumeration in the paragraph (review decision honoured)"
echo "== E. adversarial: invalid names must refuse and leave nothing behind =="
n=0
for bad in '/lavish' '$kun' 'kun run' '-kun' 'kun;rm -rf x' 'kun`id`' '../kun' 'kùn'; do
  n=$((n+1)); printf '%s\n' 'kun' "$bad" > "$CFG/standing-skills"
  out=$(scaffold ship bad-$n 2>&1); rc=$?
  state=absent; [ -e "$HOME_DIR/data/bad-$n" ] && state=LEFT-BEHIND
  printf '  [%s] rc=%s data/bad-%s=%s :: %s\n' "$bad" "$rc" "$n" "$state" "$out"
done
echo "== F. adversarial: unusable path =="
rm -f "$CFG/standing-skills"; mkdir "$CFG/standing-skills"
out=$(scaffold scout unusable-dir 2>&1); rc=$?; state=absent; [ -e "$HOME_DIR/data/unusable-dir" ] && state=LEFT-BEHIND
echo "  directory: rc=$rc data=$state :: $out"
rmdir "$CFG/standing-skills"; ln -s "$CFG/does-not-exist" "$CFG/standing-skills"
out=$(scaffold secondmate unusable-link 2>&1); rc=$?; state=absent; [ -e "$HOME_DIR/data/unusable-link" ] && state=LEFT-BEHIND
echo "  dangling symlink: rc=$rc data=$state :: $out"
rm -f "$CFG/standing-skills"; printf 'kun\n' > "$CFG/real"; ln -s "$CFG/real" "$CFG/standing-skills"
scaffold ship via-link >/dev/null && echo "  symlink to a real file: accepted, paragraph count=$(grep -c 'Standing skills' "$HOME_DIR/data/via-link/brief.md")"
rm -f "$CFG/standing-skills"; printf 'kun\n' > "$CFG/standing-skills"; chmod 000 "$CFG/standing-skills"
out=$(scaffold ship unreadable 2>&1); rc=$?; state=absent; [ -e "$HOME_DIR/data/unreadable" ] && state=LEFT-BEHIND
echo "  mode-000 file: rc=$rc data=$state :: $out"
chmod 644 "$CFG/standing-skills"
echo "== G. no trailing newline on last line still counts =="
printf 'kun' > "$CFG/standing-skills"
scaffold scout no-newline >/dev/null && echo "  paragraph count=$(grep -c 'Standing skills' "$HOME_DIR/data/no-newline/brief.md")"
rm -rf "$HOME_DIR"
echo "done"
