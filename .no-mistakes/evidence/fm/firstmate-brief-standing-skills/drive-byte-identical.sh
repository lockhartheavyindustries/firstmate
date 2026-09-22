#!/usr/bin/env bash
# Same task id each time: absent list vs comment-only list must produce byte-identical briefs.
set -u
ROOT=$1
H=$(mktemp -d "${TMPDIR:-/tmp}/fm-standing-skills-ident.XXXXXX"); mkdir -p "$H/config" "$H/data"
scaffold() { case "$1" in
  ship) FM_HOME="$H" "$ROOT/bin/fm-brief.sh" "$2" demo-proj --mode no-mistakes ;;
  scout) FM_HOME="$H" "$ROOT/bin/fm-brief.sh" "$2" demo-proj --scout ;;
  secondmate) FM_HOME="$H" FM_SECONDMATE_CHARTER='Supervise assigned work.' "$ROOT/bin/fm-brief.sh" "$2" --secondmate --no-projects ;;
esac; }
for k in ship scout secondmate; do
  rm -f "$H/config/standing-skills"
  scaffold $k t-$k >/dev/null || exit 1
  a=$(shasum -a 256 < "$H/data/t-$k/brief.md"); rm -rf "$H/data/t-$k"
  printf '%s\n' '# nothing yet' '' '   ' '# kun (commented out)' > "$H/config/standing-skills"
  scaffold $k t-$k >/dev/null || exit 1
  b=$(shasum -a 256 < "$H/data/t-$k/brief.md"); rm -rf "$H/data/t-$k"
  printf 'kun\n' > "$H/config/standing-skills"
  scaffold $k t-$k >/dev/null || exit 1
  c=$(shasum -a 256 < "$H/data/t-$k/brief.md"); rm -rf "$H/data/t-$k"
  printf '%-10s absent=%s\n%-10s comment-only=%s  -> %s\n%-10s kun=%s  -> %s\n' "$k" "${a%% *}" "" "${b%% *}" "$([ "$a" = "$b" ] && echo BYTE-IDENTICAL || echo DIFFERS)" "" "${c%% *}" "$([ "$a" = "$c" ] && echo unchanged?! || echo differs-as-expected)"
done
rm -rf "$H"
