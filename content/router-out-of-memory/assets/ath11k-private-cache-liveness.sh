#!/bin/sh
# Validate a detached shebang-script process without relying on /proc/PID/exe.

set -u

pid_file=${1:-}
expected_script=${2:-}
expected_run_dir=${3:-}

[ -n "$pid_file" ] && [ -n "$expected_script" ] && [ -n "$expected_run_dir" ] || exit 2
[ -r "$pid_file" ] || exit 1
pid=$(cat "$pid_file")
case $pid in
	''|*[!0-9]*) exit 1 ;;
esac
kill -0 "$pid" 2>/dev/null || exit 1
[ -r "/proc/$pid/cmdline" ] || exit 1
cmdline=$(tr '\000' ' ' <"/proc/$pid/cmdline")
case " $cmdline " in
	*" $expected_script $expected_run_dir "*) ;;
	*) exit 1 ;;
esac

# The lock can be absent while start-stop-daemon's child enters the guard.
# Once present, it must identify the same process.
if [ -r "$expected_run_dir/guard.lock/pid" ]; then
	[ "$(cat "$expected_run_dir/guard.lock/pid")" = "$pid" ] || exit 1
fi

exit 0
