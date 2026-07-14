#!/bin/sh
# Runs on the router. The local deploy helper stages this file and a manifest.

set -u

run_dir=${1:-}
mode=${2:-run}

if [ -z "$run_dir" ] || [ ! -r "$run_dir/manifest" ]; then
	printf 'usage: %s RUN_DIR [run|rollback]\n' "$0" >&2
	exit 2
fi

# The manifest is generated locally from validated numeric values and hashes.
# shellcheck disable=SC1090
. "$run_dir/manifest"

state_file=$run_dir/state
log_file=$run_dir/watchdog.log
metrics_file=$run_dir/metrics.csv
acceptance_file=$run_dir/acceptance.log
proc_root=${PROC_ROOT_OVERRIDE:-/proc}
sys_root=${SYS_ROOT_OVERRIDE:-/sys}
module_dir=${MODULE_DIR_OVERRIDE:-/lib/modules/$KERNEL_RELEASE}
reload_script=${RELOAD_SCRIPT_OVERRIDE:-/root/ath11k-reload.sh}
global_lock_dir=${GLOBAL_LOCK_DIR_OVERRIDE:-/root/ath11k-private-cache-global.lock}
core_module=$module_dir/ath11k.ko
ahb_module=$module_dir/ath11k_ahb.ko
lock_dir=$run_dir/guard.lock
rollback_needed=0
failure_reason=unexpected_exit
CANDIDATE_TEXT_ADDR=
CANDIDATE_PHY_GENERATION=
MEMGUARD_BASELINE=0
DMESG_BASELINE_LINES=0
BOUNDED_CHILD=
BOUNDED_TIMER=

acquire_lock()
{
	if mkdir "$lock_dir" 2>/dev/null; then
		printf '%s\n' "$$" >"$lock_dir/pid"
		return 0
	fi

	owner=$(cat "$lock_dir/pid" 2>/dev/null || true)
	if [ -n "$owner" ] && kill -0 "$owner" 2>/dev/null; then
		printf 'another guard owns %s (pid %s)\n' "$lock_dir" "$owner" >&2
		return 1
	fi

	stale=$lock_dir.stale.$$
	if mv "$lock_dir" "$stale" 2>/dev/null; then
		if mkdir "$lock_dir" 2>/dev/null; then
			rm -rf "$stale"
			printf '%s\n' "$$" >"$lock_dir/pid"
			return 0
		fi
		printf 'could not recreate guard lock %s after stale recovery\n' "$lock_dir" >&2
		return 1
	fi
	printf 'could not move stale guard lock %s\n' "$lock_dir" >&2
	return 1
}

release_lock()
{
	owner=$(cat "$lock_dir/pid" 2>/dev/null || true)
	if [ "$owner" = "$$" ]; then
		rm -f "$lock_dir/pid"
		rmdir "$lock_dir" 2>/dev/null || true
	fi
}

claim_global_lock()
{
	if mkdir "$global_lock_dir" 2>/dev/null; then
		printf '%s\n' "$run_dir" >"$global_lock_dir/run_dir"
	fi
	[ "$(cat "$global_lock_dir/run_dir" 2>/dev/null)" = "$run_dir" ] || return 1
	printf '%s\n' "$$" >"$global_lock_dir/pid"
	printf 'guard\n' >"$global_lock_dir/phase"
}

release_global_lock()
{
	global_owner=$(cat "$global_lock_dir/run_dir" 2>/dev/null || true)
	global_pid=$(cat "$global_lock_dir/pid" 2>/dev/null || true)
	if [ "$global_owner" = "$run_dir" ] && [ "$global_pid" = "$$" ]; then
		rm -f "$global_lock_dir/pid" "$global_lock_dir/run_dir" \
			"$global_lock_dir/phase" "$global_lock_dir/created_epoch"
		rmdir "$global_lock_dir" 2>/dev/null || true
	fi
}

acquire_lock || exit 75
if ! claim_global_lock; then
	release_lock
	printf 'another run owns global deployment lock %s\n' "$global_lock_dir" >&2
	exit 75
fi

log()
{
	now=$(date -Iseconds 2>/dev/null || date)
	printf '%s %s\n' "$now" "$*" >>"$log_file"
	logger -t ath11k-private-cache "$RUN_ID $*" 2>/dev/null || true
}

uptime_seconds()
{
	awk '{print int($1)}' "$proc_root/uptime"
}

write_state()
{
	state=$1
	reason=${2:-none}
	tmp=$state_file.tmp.$$
	{
		printf 'run_id=%s\n' "$RUN_ID"
		printf 'state=%s\n' "$state"
		printf 'reason=%s\n' "$reason"
		printf 'router_epoch=%s\n' "$(date +%s)"
		printf 'uptime_seconds=%s\n' "$(uptime_seconds)"
	} >"$tmp"
	mv "$tmp" "$state_file"
	log "state=$state reason=$reason"
}

file_sha()
{
	sha256sum "$1" | awk '{print $1}'
}

mem_available()
{
	awk '/^MemAvailable:/{print $2; found=1; exit} END {if (!found) exit 1}' \
		"$proc_root/meminfo"
}

pagefrag_bytes()
{
	awk '/func:__page_frag_cache_refill/{sum += $1; found=1} END {if (!found) exit 1; print sum + 0}' \
		"$proc_root/allocinfo"
}

memguard_events()
{
	logread 2>/dev/null | awk '/ath11k-memguard:.*-> reloading ath11k/{count++} END {print count + 0}'
}

module_text_addr()
{
	cat "$sys_root/module/ath11k/sections/.text" 2>/dev/null
}

phy_generation()
{
	iw dev 2>/dev/null | awk '
		index($1, "phy#") == 1 {
			printf "%s%s", separator, substr($1, 5)
			separator=","; found=1
		}
		END {if (found) print ""; else exit 1}
	'
}

candidate_marker_loaded()
{
	[ "$(cat "$sys_root/module/ath11k/parameters/private_rxfrag" 2>/dev/null)" = "$CANDIDATE_MARKER_VALUE" ]
}

stock_marker_loaded()
{
	[ ! -e "$sys_root/module/ath11k/parameters/private_rxfrag" ]
}

candidate_instance_loaded()
{
	[ -n "$CANDIDATE_TEXT_ADDR" ] &&
		[ -n "$CANDIDATE_PHY_GENERATION" ] &&
		[ "$(module_text_addr)" = "$CANDIDATE_TEXT_ADDR" ] &&
		[ "$(phy_generation)" = "$CANDIDATE_PHY_GENERATION" ] &&
		candidate_marker_loaded
}

memguard_running()
{
	pgrep -f '^/bin/sh /root/ath11k-memguard.sh$' >/dev/null
}

reload_not_running()
{
	! pgrep -f '^/bin/sh /root/ath11k-reload.sh$' >/dev/null
}

interfaces_healthy()
{
	ap_count=$(iw dev 2>/dev/null | awk '$1 == "type" && $2 == "AP" {count++} END {print count + 0}')
	managed_count=$(iw dev 2>/dev/null | awk '$1 == "type" && $2 == "managed" {count++} END {print count + 0}')
	[ "$ap_count" -ge 1 ] && [ "$managed_count" -ge 1 ]
}

network_healthy()
{
	gateway=$(ip route show default 2>/dev/null | awk 'NR == 1 {print $3}')
	[ "$gateway" = "$EXPECTED_GATEWAY" ] &&
		ping -c 1 -W 1 "$EXPECTED_GATEWAY" >/dev/null 2>&1 &&
		ping -c 1 -W 1 "$MANAGEMENT_PEER" >/dev/null 2>&1
}

modules_loaded()
{
	lsmod | grep -q '^ath11k ' && lsmod | grep -q '^ath11k_ahb '
}

disk_pair_is()
{
	expected_core=$1
	expected_ahb=$2
	[ -s "$core_module" ] && [ -s "$ahb_module" ] &&
		[ "$(file_sha "$core_module")" = "$expected_core" ] &&
		[ "$(file_sha "$ahb_module")" = "$expected_ahb" ]
}

install_pair()
{
	source_dir=$1
	expected_core=$2
	expected_ahb=$3

	[ "$(file_sha "$source_dir/ath11k.ko")" = "$expected_core" ] || return 1
	[ "$(file_sha "$source_dir/ath11k_ahb.ko")" = "$expected_ahb" ] || return 1
	rm -f "$core_module.new" "$ahb_module.new"
	cp "$source_dir/ath11k.ko" "$core_module.new" || return 1
	cp "$source_dir/ath11k_ahb.ko" "$ahb_module.new" || {
		rm -f "$core_module.new"
		return 1
	}
	chmod 0644 "$core_module.new" "$ahb_module.new" || return 1
	mv "$core_module.new" "$core_module" || return 1
	mv "$ahb_module.new" "$ahb_module" || return 1
	sync
	disk_pair_is "$expected_core" "$expected_ahb"
}

run_bounded()
{
	limit=$1
	shift
	if [ "${RUN_BOUNDED_DIRECT_OVERRIDE:-0}" = 1 ]; then
		"$@"
		return $?
	fi
	"$@" &
	BOUNDED_CHILD=$!
	(
		sleep "$limit"
		kill -TERM "$BOUNDED_CHILD" 2>/dev/null || exit 0
		sleep 2
		kill -KILL "$BOUNDED_CHILD" 2>/dev/null || true
	) &
	BOUNDED_TIMER=$!
	wait "$BOUNDED_CHILD"
	bounded_status=$?
	kill "$BOUNDED_TIMER" 2>/dev/null || true
	wait "$BOUNDED_TIMER" 2>/dev/null || true
	BOUNDED_CHILD=
	BOUNDED_TIMER=
	return "$bounded_status"
}

stop_bounded_command()
{
	if [ -n "$BOUNDED_CHILD" ]; then
		kill -TERM "$BOUNDED_CHILD" 2>/dev/null || true
		wait "$BOUNDED_CHILD" 2>/dev/null || true
	fi
	if [ -n "$BOUNDED_TIMER" ]; then
		kill -TERM "$BOUNDED_TIMER" 2>/dev/null || true
		wait "$BOUNDED_TIMER" 2>/dev/null || true
	fi
	BOUNDED_CHILD=
	BOUNDED_TIMER=
}

fatal_dmesg_since()
{
	first_line=$1
	current_lines=$(dmesg | wc -l)
	[ "$current_lines" -ge "$first_line" ] || return 0
	dmesg | sed -n "$((first_line + 1)),\$p" >"$run_dir/dmesg-new"
	grep -Eiq 'Unknown symbol|disagrees about version|Exec format error|BUG:|Oops:|Kernel panic|Call trace:|ath11k.*(firmware crash|failed to start|failed to load|failed to wait)' \
		"$run_dir/dmesg-new"
}

identity_healthy()
{
	case $1 in
		candidate) candidate_instance_loaded ;;
		stock) stock_marker_loaded ;;
		*) return 1 ;;
	esac
}

numeric_value()
{
	case ${1:-} in
		''|*[!0-9]*) return 1 ;;
		*) return 0 ;;
	esac
}

wait_health()
{
	expected_identity=$1
	expected_memguard_events=$2
	deadline=$(( $(uptime_seconds) + HEALTH_TIMEOUT_SECONDS ))

	while [ "$(uptime_seconds)" -lt "$deadline" ]; do
		available=$(mem_available 2>/dev/null || true)
		pagefrag=$(pagefrag_bytes 2>/dev/null || true)
		if numeric_value "$available" && numeric_value "$pagefrag" &&
		   modules_loaded && identity_healthy "$expected_identity" &&
		   memguard_running &&
		   [ "$(memguard_events)" -eq "$expected_memguard_events" ] &&
		   [ "$available" -ge "$LOW_MEM_KB" ] &&
		   interfaces_healthy && network_healthy; then
			return 0
		fi
		sleep 3
	done
	return 1
}

load_candidate_transient()
{
	run_bounded "$COMMAND_TIMEOUT_SECONDS" wifi down >/dev/null 2>&1 || return 1
	sleep 2
	run_bounded "$COMMAND_TIMEOUT_SECONDS" rmmod ath11k_ahb >/dev/null 2>&1 || return 1
	run_bounded "$COMMAND_TIMEOUT_SECONDS" rmmod ath11k >/dev/null 2>&1 || return 1
	lsmod | grep -Eq '^ath11k(_ahb)? ' && return 1
	run_bounded "$COMMAND_TIMEOUT_SECONDS" insmod "$run_dir/candidate/ath11k.ko" >/dev/null 2>&1 || return 1
	run_bounded "$COMMAND_TIMEOUT_SECONDS" insmod "$run_dir/candidate/ath11k_ahb.ko" >/dev/null 2>&1 || return 1
	run_bounded "$COMMAND_TIMEOUT_SECONDS" wifi up >/dev/null 2>&1 || return 1
	sleep 10
	return 0
}

capture_candidate_identity()
{
	candidate_marker_loaded || return 1
	CANDIDATE_TEXT_ADDR=$(module_text_addr)
	CANDIDATE_PHY_GENERATION=$(phy_generation)
	[ -n "$CANDIDATE_TEXT_ADDR" ] && [ -n "$CANDIDATE_PHY_GENERATION" ]
}

restore_stock_files()
{
	install_pair "$run_dir/stock" "$STOCK_CORE_SHA256" "$STOCK_AHB_SHA256"
}

restore_stock()
{
	reason=$1
	write_state rolling_back "$reason"
	if ! restore_stock_files; then
		write_state rollback_failed stock_install_failed
		return 1
	fi
	if ! run_bounded "$COMMAND_TIMEOUT_SECONDS" "$reload_script" >>"$log_file" 2>&1; then
		write_state rollback_failed stock_reload_failed
		return 1
	fi
	stock_memguard_events=$(memguard_events)
	if wait_health stock "$stock_memguard_events" &&
	   disk_pair_is "$STOCK_CORE_SHA256" "$STOCK_AHB_SHA256"; then
		rollback_needed=0
		write_state rolled_back "$reason"
		return 0
	fi
	write_state rollback_failed stock_health_failed
	return 1
}

cleanup()
{
	cleanup_status=$?
	trap - 0 HUP INT TERM
	stop_bounded_command
	if [ "$rollback_needed" -eq 1 ]; then
		restore_stock "$failure_reason" || cleanup_status=1
	fi
	release_lock
	release_global_lock
	exit "$cleanup_status"
}

fail()
{
	failure_reason=$1
	write_state failing "$failure_reason"
	exit 1
}

append_metrics()
{
	phase=$1
	started=$2
	now=$(uptime_seconds)
	available=$(mem_available) || fail memavailable_unreadable
	pagefrag=$(pagefrag_bytes) || fail allocinfo_pagefrag_unreadable
	numeric_value "$available" || fail memavailable_nonnumeric
	numeric_value "$pagefrag" || fail allocinfo_pagefrag_nonnumeric
	printf '%s,%s,%s,%s,%s,%s\n' \
		"$(date +%s)" "$((now - started))" "$phase" "$available" \
		"$pagefrag" "$(memguard_events)" >>"$metrics_file"
}

check_candidate()
{
	[ ! -e "$run_dir/rollback_request" ] || fail requested_rollback
	modules_loaded || fail modules_unloaded
	candidate_instance_loaded || fail candidate_instance_changed
	disk_pair_is "$STOCK_CORE_SHA256" "$STOCK_AHB_SHA256" || fail disk_pair_not_stock_during_test
	memguard_running || fail memguard_not_running
	hardware_watchdog_running || fail hardware_watchdog_not_running
	[ "$(memguard_events)" -eq "$MEMGUARD_BASELINE" ] || fail new_memguard_reload
	available=$(mem_available 2>/dev/null || true)
	pagefrag=$(pagefrag_bytes 2>/dev/null || true)
	numeric_value "$available" || fail memavailable_unreadable
	numeric_value "$pagefrag" || fail allocinfo_pagefrag_unreadable
	[ "$available" -ge "$LOW_MEM_KB" ] || fail low_memory
	interfaces_healthy || fail wireless_interfaces_unhealthy
	network_healthy || fail network_unreachable
	fatal_dmesg_since "$DMESG_BASELINE_LINES" && fail candidate_fatal_dmesg
}

monitor_candidate()
{
	phase=$1
	duration=$2
	started=$(uptime_seconds)
	deadline=$((started + duration))

	while [ "$(uptime_seconds)" -lt "$deadline" ]; do
		check_candidate
		append_metrics "$phase" "$started"
		sleep "$SAMPLE_SECONDS"
	done
}

metrics_flat()
{
	phase=$1
	duration=$2
	minimum_elapsed=$((duration - SAMPLE_SECONDS * 2))
	[ "$minimum_elapsed" -ge 1 ] || minimum_elapsed=1
	awk -F, \
		-v wanted="$phase" \
		-v min_elapsed="$minimum_elapsed" \
		-v max_mem_drop="$MAX_MEM_DROP_KB" \
		-v max_mem_range="$MAX_MEM_RANGE_KB" \
		-v min_mem_slope="$MIN_MEM_SLOPE_KB_PER_MIN" \
		-v max_pf_growth="$MAX_PAGEFRAG_GROWTH_BYTES" \
		-v max_pf_range="$MAX_PAGEFRAG_RANGE_BYTES" \
		-v max_pf_slope="$MAX_PAGEFRAG_SLOPE_BYTES_PER_MIN" '
		NR == 1 || $3 != wanted {next}
		{
			x=$2+0; mem=$4+0; pf=$5+0
			if (count == 0) {
				first_x=x; first_mem=mem; first_pf=pf
				min_mem=max_mem=mem; min_pf=max_pf=pf
			}
			count++; last_x=x; last_mem=mem; last_pf=pf
			if (mem < min_mem) min_mem=mem
			if (mem > max_mem) max_mem=mem
			if (pf < min_pf) min_pf=pf
			if (pf > max_pf) max_pf=pf
			sx += x; sxx += x*x
			sm += mem; sxm += x*mem
			sp += pf; sxp += x*pf
		}
		END {
			elapsed=last_x-first_x
			den=count*sxx-sx*sx
			if (den > 0) {
				mem_slope=60*(count*sxm-sx*sm)/den
				pf_slope=60*(count*sxp-sx*sp)/den
			}
			mem_drop=first_mem-last_mem
			pf_growth=last_pf-first_pf
			mem_range=max_mem-min_mem
			pf_range=max_pf-min_pf
			ok=(count >= 2 && elapsed >= min_elapsed &&
			    mem_drop <= max_mem_drop && mem_range <= max_mem_range &&
			    mem_slope >= min_mem_slope &&
			    pf_growth <= max_pf_growth && pf_range <= max_pf_range &&
			    pf_slope <= max_pf_slope)
			printf "phase=%s samples=%d elapsed=%d mem_drop_kb=%d mem_range_kb=%d mem_slope_kb_per_min=%.3f pagefrag_growth_bytes=%d pagefrag_range_bytes=%d pagefrag_slope_bytes_per_min=%.3f result=%s\n", wanted, count, elapsed, mem_drop, mem_range, mem_slope, pf_growth, pf_range, pf_slope, (ok ? "pass" : "fail")
			exit(ok ? 0 : 1)
		}
	' "$metrics_file" >>"$acceptance_file"
}

wait_for_request()
{
	request=$1
	phase=$2
	started=$(uptime_seconds)
	deadline=$((started + REQUEST_GRACE_SECONDS))

	while [ "$(uptime_seconds)" -lt "$deadline" ]; do
		check_candidate
		if [ -e "$run_dir/$request" ]; then
			return 0
		fi
		append_metrics "$phase" "$started"
		sleep "$SAMPLE_SECONDS"
	done
	return 1
}

hardware_watchdog_running()
{
	ubus call system watchdog 2>/dev/null | grep -Eq '"status"[[:space:]]*:[[:space:]]*"running"'
}

guard_preflight()
{
	for required in awk cat chmod cp date dmesg grep insmod ip iw kill logger \
		logread lsmod mkdir modprobe mv pgrep ping rm rmdir rmmod sed sha256sum \
		sleep sync ubus uname wc wifi; do
		command -v "$required" >/dev/null 2>&1 || return 1
	done
	[ -x "$reload_script" ] || return 1
	[ -r "$proc_root/meminfo" ] || return 1
	[ -r "$proc_root/uptime" ] || return 1
	[ -r "$proc_root/allocinfo" ] || return 1
	numeric_value "$(mem_available 2>/dev/null || true)" || return 1
	numeric_value "$(pagefrag_bytes 2>/dev/null || true)" || return 1
	hardware_watchdog_running || return 1
}

rollback_preflight()
{
	for required in awk cat chmod cp date kill logger mkdir modprobe mv rm rmdir \
		rmmod sha256sum sleep sync wifi; do
		command -v "$required" >/dev/null 2>&1 || return 1
	done
	[ -x "$reload_script" ] || return 1
	[ -r "$proc_root/uptime" ] || return 1
}

wait_for_safe_baseline()
{
	deadline=$(( $(uptime_seconds) + BASELINE_WAIT_SECONDS ))
	stable=0
	stable_events=
	write_state baseline_wait waiting_for_stock_health
	while [ "$(uptime_seconds)" -lt "$deadline" ]; do
		disk_pair_is "$STOCK_CORE_SHA256" "$STOCK_AHB_SHA256" || return 1
		memguard_running || return 1
		available=$(mem_available 2>/dev/null || true)
		events=$(memguard_events)
		if stock_marker_loaded && modules_loaded && reload_not_running &&
			hardware_watchdog_running && interfaces_healthy && network_healthy &&
			numeric_value "$available" && [ "$available" -ge "$START_MIN_KB" ]; then
			if [ "$stable" -eq 1 ] && [ "$events" = "$stable_events" ]; then
				return 0
			fi
			stable=1
			stable_events=$events
		else
			stable=0
			stable_events=
		fi
		sleep 3
	done
	return 1
}

trap cleanup 0
trap 'failure_reason=signal_hup; write_state failing "$failure_reason"; exit 129' HUP
trap 'failure_reason=signal_int; write_state failing "$failure_reason"; exit 130' INT
trap 'failure_reason=signal_term; write_state failing "$failure_reason"; exit 143' TERM

if [ "$mode" = rollback ]; then
	rollback_needed=1
	failure_reason=manual_rollback
	if ! rollback_preflight; then
		write_state rollback_failed rollback_preflight_failed
		rollback_needed=0
		exit 1
	fi
	[ "$(file_sha "$run_dir/stock/ath11k.ko")" = "$STOCK_CORE_SHA256" ] || fail stock_core_hash_mismatch
	[ "$(file_sha "$run_dir/stock/ath11k_ahb.ko")" = "$STOCK_AHB_SHA256" ] || fail stock_ahb_hash_mismatch
	restore_stock manual_rollback
	exit $?
fi
[ "$mode" = run ] || exit 2

guard_preflight || fail preflight_failed

mkdir -p "$run_dir/stock" "$run_dir/candidate"
printf 'epoch,elapsed_seconds,phase,mem_available_kb,pagefrag_bytes,memguard_events\n' >"$metrics_file"
: >"$acceptance_file"
write_state staging none

[ "$(uname -r)" = "$KERNEL_RELEASE" ] || fail kernel_release_mismatch
[ "$(file_sha "$run_dir/stock/ath11k.ko")" = "$STOCK_CORE_SHA256" ] || fail stock_core_hash_mismatch
[ "$(file_sha "$run_dir/stock/ath11k_ahb.ko")" = "$STOCK_AHB_SHA256" ] || fail stock_ahb_hash_mismatch
[ "$(file_sha "$run_dir/candidate/ath11k.ko")" = "$CANDIDATE_CORE_SHA256" ] || fail candidate_core_hash_mismatch
[ "$(file_sha "$run_dir/candidate/ath11k_ahb.ko")" = "$CANDIDATE_AHB_SHA256" ] || fail candidate_ahb_hash_mismatch
disk_pair_is "$STOCK_CORE_SHA256" "$STOCK_AHB_SHA256" || fail installed_pair_not_stock
wait_for_safe_baseline || fail baseline_not_safe

rollback_needed=1
failure_reason=candidate_load_failed
write_state loading_candidate none
MEMGUARD_BASELINE=$(memguard_events)
DMESG_BASELINE_LINES=$(dmesg | wc -l)
load_candidate_transient || fail candidate_load_failed
capture_candidate_identity || fail candidate_identity_missing
wait_health candidate "$MEMGUARD_BASELINE" || fail candidate_health_failed
fatal_dmesg_since "$DMESG_BASELINE_LINES" && fail candidate_fatal_dmesg
disk_pair_is "$STOCK_CORE_SHA256" "$STOCK_AHB_SHA256" || fail transient_test_changed_disk_pair

write_state monitoring none
monitor_candidate transient "$VALIDATION_SECONDS"
metrics_flat transient "$VALIDATION_SECONDS" || fail transient_memory_not_flat
write_state eligible none
wait_for_request persist_request eligible_wait || fail persist_request_timeout
rm -f "$run_dir/persist_request"

# Load the same staged modules a second time without changing the stock files on
# disk. A reboot or memguard event therefore remains an automatic rollback.
write_state persist_reloading none
MEMGUARD_BASELINE=$(memguard_events)
DMESG_BASELINE_LINES=$(dmesg | wc -l)
load_candidate_transient || fail persistent_candidate_reload_failed
capture_candidate_identity || fail persistent_candidate_identity_missing
wait_health candidate "$MEMGUARD_BASELINE" || fail persistent_candidate_health_failed
fatal_dmesg_since "$DMESG_BASELINE_LINES" && fail persistent_candidate_fatal_dmesg
disk_pair_is "$STOCK_CORE_SHA256" "$STOCK_AHB_SHA256" || fail persistent_test_changed_disk_pair

write_state persist_monitoring none
monitor_candidate persistent "$POST_PERSIST_SECONDS"
metrics_flat persistent "$POST_PERSIST_SECONDS" || fail persistent_memory_not_flat
write_state persist_eligible none
wait_for_request commit_request persist_eligible_wait || fail commit_request_timeout

# Only this explicit commit transition makes the already validated candidate
# durable. No module reload is needed, so the currently checked instance remains
# resident while the exact staged files are installed.
check_candidate
write_state committing none
install_pair "$run_dir/candidate" "$CANDIDATE_CORE_SHA256" "$CANDIDATE_AHB_SHA256" || fail final_candidate_install_failed
disk_pair_is "$CANDIDATE_CORE_SHA256" "$CANDIDATE_AHB_SHA256" || fail final_candidate_hash_mismatch
candidate_instance_loaded || fail candidate_instance_changed_during_commit
rollback_needed=0
write_state committed none
exit 0
