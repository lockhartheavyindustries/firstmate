#!/usr/bin/env bash
if [ "${1-}" = -o ] && [ "${2-}" = pgid= ] && [ "${3-}" = -p ] && [ "${4-}" = "${FM_PROCEVENT_RUNNER_GROUP-none}" ] && [ -n "${FM_HOME-}" ]; then
  case "${PT_MODE-}" in
    slow) if [ ! -e "$FM_HOME/.pt-slowed" ]; then : > "$FM_HOME/.pt-slowed"; sleep ${PT_DELAY:-5}; fi ;;
    nostart) printf 'pt-shim refused runner pgid check\n' >&2; exit 1 ;;
  esac
fi
exec /bin/ps "$@"
