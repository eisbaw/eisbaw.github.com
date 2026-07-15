#!/usr/bin/env bash
set -euo pipefail

script_dir=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
guard=$script_dir/ath11k-private-cache-guard.sh
liveness=$script_dir/ath11k-private-cache-liveness.sh
invoked_as=$(basename -- "$0")
host_path=$PATH
real_sleep=$(command -v sleep)
real_cp=$(command -v cp)

mock_command() {
    local root=${MOCK_ROOT:?}
    local fault=${MOCK_FAULT:-none}
    local value duration current next count module

    case $invoked_as in
        uname)
            [[ ${1:-} == -r ]] && printf '6.12.87\n' || printf 'Linux\n'
            ;;
        ubus)
            if [[ $(<"$root/state/watchdog") == 1 ]]; then
                printf '{ "status": "running", "timeout": 30, "frequency": 5 }\n'
            else
                printf '{ "status": "stopped" }\n'
            fi
            ;;
        logger) ;;
        cp)
            if [[ $fault == final_install_failure && -r $root/run/state &&
                  $(awk -F= '$1 == "state" {print $2}' "$root/run/state") == committing ]]; then
                exit 1
            fi
            "${REAL_CP:?}" "$@"
            ;;
        pgrep)
            case $* in
                *ath11k-memguard.sh*) [[ $(<"$root/state/memguard") == 1 ]] ;;
                *ath11k-reload.sh*) [[ $(<"$root/state/reload_running") == 1 ]] ;;
                *) exit 1 ;;
            esac
            ;;
        logread)
            count=$(<"$root/state/memguard_events")
            while ((count > 0)); do
                printf 'ath11k-memguard: threshold -> reloading ath11k\n'
                ((count--)) || true
            done
            ;;
        lsmod)
            if [[ $(<"$root/state/core_loaded") == 1 ]]; then
                printf 'ath11k 1 0\n'
            fi
            if [[ $(<"$root/state/ahb_loaded") == 1 ]]; then
                printf 'ath11k_ahb 1 0\n'
            fi
            ;;
        iw)
            if [[ ${1:-} == dev && $(<"$root/state/core_loaded") == 1 &&
                  $(<"$root/state/ahb_loaded") == 1 && $(<"$root/state/wifi_up") == 1 ]]; then
                printf 'phy#%s\n' "$(<"$root/state/phy_generation")"
                printf '\tInterface wlan0\n\t\ttype AP\n'
                printf '\tInterface wlan1\n\t\ttype managed\n'
            fi
            ;;
        ip)
            printf 'default via 192.0.2.1 dev wlan1\n'
            ;;
        ping)
            [[ $fault != network_failure || $(<"$root/state/candidate_loads") == 0 ]]
            ;;
        wifi)
            case ${1:-} in
                down)
                    if [[ $fault == hang_wifi ]]; then
                        "${REAL_SLEEP:?}" 30
                    fi
                    printf '0\n' >"$root/state/wifi_up"
                    ;;
                up) printf '1\n' >"$root/state/wifi_up" ;;
                *) exit 2 ;;
            esac
            ;;
        rmmod)
            module=${1:-}
            case $module in
                ath11k_ahb) printf '0\n' >"$root/state/ahb_loaded" ;;
                ath11k)
                    printf '0\n' >"$root/state/core_loaded"
                    rm -rf "$root/sys/module/ath11k"
                    ;;
                *) exit 1 ;;
            esac
            ;;
        insmod)
            module=$(basename -- "${1:-}")
            case $module in
                ath11k.ko)
                    if [[ $fault == baseline_reload && $(<"$root/state/reload_running") == 1 ]]; then
                        : >"$root/state/candidate_reload_overlap"
                        exit 1
                    fi
                    current=$(<"$root/state/candidate_loads")
                    printf '%s\n' "$((current + 1))" >"$root/state/candidate_loads"
                    current=$(<"$root/state/phy_generation")
                    printf '%s\n' "$((current + 1))" >"$root/state/phy_generation"
                    mkdir -p "$root/sys/module/ath11k/sections" "$root/sys/module/ath11k/parameters"
                    printf 'Y\n' >"$root/sys/module/ath11k/parameters/private_rxfrag"
                    printf 'candidate-%s\n' "$((current + 1))" >"$root/sys/module/ath11k/sections/.text"
                    printf '1\n' >"$root/state/core_loaded"
                    ;;
                ath11k_ahb.ko)
                    [[ $fault != partial_candidate_load &&
                       $fault != partial_candidate_load_reload_failure ]] || exit 1
                    printf '1\n' >"$root/state/ahb_loaded"
                    if [[ $fault == memguard_race ]]; then
                        printf '1\n' >"$root/state/memguard_events"
                    fi
                    ;;
                *) exit 1 ;;
            esac
            ;;
        reload)
            [[ $fault != reload_failure &&
               $fault != partial_candidate_load_reload_failure ]] || exit 1
            cp "$root/run/stock/ath11k.ko" "$root/modules/ath11k.ko"
            cp "$root/run/stock/ath11k_ahb.ko" "$root/modules/ath11k_ahb.ko"
            current=$(<"$root/state/phy_generation")
            printf '%s\n' "$((current + 1))" >"$root/state/phy_generation"
            mkdir -p "$root/sys/module/ath11k/sections"
            rm -f "$root/sys/module/ath11k/parameters/private_rxfrag"
            printf 'stock-%s\n' "$((current + 1))" >"$root/sys/module/ath11k/sections/.text"
            printf '1\n' >"$root/state/core_loaded"
            printf '1\n' >"$root/state/ahb_loaded"
            printf '1\n' >"$root/state/wifi_up"
            printf 'MemAvailable: 100000 kB\n' >"$root/proc/meminfo"
            printf '1000 func:__page_frag_cache_refill\n' >"$root/proc/allocinfo"
            ;;
        sleep)
            duration=${1%%.*}
            [[ $duration =~ ^[0-9]+$ ]]
            if [[ $fault == hang_wifi ]]; then
                "${REAL_SLEEP:?}" "$duration"
                exit 0
            fi
            if [[ $fault == baseline_reload && $duration == 3 ]]; then
                printf '0\n' >"$root/state/reload_running"
                printf '1\n' >"$root/state/wifi_up"
            fi
            if [[ $duration == 1 && -e $root/sys/module/ath11k/parameters/private_rxfrag ]]; then
                case $fault in
                    low_memory)
                        if [[ ! -e $root/state/fault_triggered ]]; then
                            printf 'MemAvailable: 20000 kB\n' >"$root/proc/meminfo"
                            : >"$root/state/fault_triggered"
                        fi
                        ;;
                    fatal_dmesg)
                        if [[ ! -e $root/state/fault_triggered ]]; then
                            printf 'BUG: injected ath11k failure\n' >>"$root/state/dmesg"
                            : >"$root/state/fault_triggered"
                        fi
                        ;;
                    memguard_stopped)
                        printf '0\n' >"$root/state/memguard"
                        ;;
                    declining_memory)
                        value=$(awk '/^MemAvailable:/{print $2}' "$root/proc/meminfo")
                        printf 'MemAvailable: %s kB\n' "$((value - 1000))" >"$root/proc/meminfo"
                        value=$(awk '{print $1}' "$root/proc/allocinfo")
                        printf '%s func:__page_frag_cache_refill\n' "$((value + 1048576))" >"$root/proc/allocinfo"
                        ;;
                    signal_term)
                        if [[ ! -e $root/state/fault_triggered ]]; then
                            : >"$root/state/fault_triggered"
                            kill -TERM "$PPID"
                        fi
                        ;;
                    marker_loss)
                        rm -f "$root/sys/module/ath11k/parameters/private_rxfrag"
                        ;;
                    disk_mutation)
                        printf 'mutated-disk-core\n' >"$root/modules/ath11k.ko"
                        ;;
                    allocinfo_failure)
                        : >"$root/proc/allocinfo"
                        ;;
                    watchdog_stopped)
                        printf '0\n' >"$root/state/watchdog"
                        ;;
                    persistent_decline)
                        if [[ $(<"$root/state/candidate_loads") -ge 2 ]]; then
                            value=$(awk '/^MemAvailable:/{print $2}' "$root/proc/meminfo")
                            printf 'MemAvailable: %s kB\n' "$((value - 1000))" >"$root/proc/meminfo"
                            value=$(awk '{print $1}' "$root/proc/allocinfo")
                            printf '%s func:__page_frag_cache_refill\n' "$((value + 1048576))" >"$root/proc/allocinfo"
                        fi
                        ;;
                esac
            fi
            current=$(awk '{print int($1)}' "$root/proc/uptime")
            next=$((current + duration))
            printf '%s.00 0.00\n' "$next" >"$root/proc/uptime"
            ;;
        dmesg)
            cat "$root/state/dmesg"
            ;;
        *)
            printf 'unexpected mock command: %s\n' "$invoked_as" >&2
            exit 127
            ;;
    esac
}

case $invoked_as in
    uname|ubus|logger|cp|pgrep|logread|lsmod|iw|ip|ping|wifi|rmmod|insmod|reload|sleep|dmesg)
        mock_command "$@"
        exit $?
        ;;
esac

test -s "$guard"
test -s "$liveness"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

make_fixture() {
    local root=$1
    local command

    rm -rf "$root"
    mkdir -p "$root/bin" "$root/proc" "$root/sys/module/ath11k/sections" \
        "$root/modules" "$root/run/stock" "$root/run/candidate" "$root/state"
    for command in uname ubus logger cp pgrep logread lsmod iw ip ping wifi rmmod \
                   insmod reload sleep dmesg; do
        ln -s "$script_dir/$(basename -- "$0")" "$root/bin/$command"
    done
    printf 'MemAvailable: 100000 kB\n' >"$root/proc/meminfo"
    printf '0.00 0.00\n' >"$root/proc/uptime"
    printf '1000 func:__page_frag_cache_refill\n' >"$root/proc/allocinfo"
    printf 'stock-core\n' >"$root/run/stock/ath11k.ko"
    printf 'stock-ahb\n' >"$root/run/stock/ath11k_ahb.ko"
    printf 'candidate-core\n' >"$root/run/candidate/ath11k.ko"
    printf 'stock-ahb\n' >"$root/run/candidate/ath11k_ahb.ko"
    cp "$root/run/stock/ath11k.ko" "$root/modules/ath11k.ko"
    cp "$root/run/stock/ath11k_ahb.ko" "$root/modules/ath11k_ahb.ko"
    printf 'stock-0\n' >"$root/sys/module/ath11k/sections/.text"
    printf '1\n' >"$root/state/core_loaded"
    printf '1\n' >"$root/state/ahb_loaded"
    printf '1\n' >"$root/state/wifi_up"
    printf '1\n' >"$root/state/memguard"
    printf '0\n' >"$root/state/reload_running"
    printf '1\n' >"$root/state/watchdog"
    printf '0\n' >"$root/state/memguard_events"
    printf '0\n' >"$root/state/phy_generation"
    printf '0\n' >"$root/state/candidate_loads"
    : >"$root/state/dmesg"

    {
        printf "RUN_ID='test'\n"
        printf "KERNEL_RELEASE='6.12.87'\n"
        printf "GLOBAL_LOCK_DIR_OVERRIDE='%s'\n" "$root/global.lock"
        printf "CANDIDATE_MARKER_VALUE='Y'\n"
        printf "STOCK_CORE_SHA256='%s'\n" "$(sha256sum "$root/run/stock/ath11k.ko" | awk '{print $1}')"
        printf "STOCK_AHB_SHA256='%s'\n" "$(sha256sum "$root/run/stock/ath11k_ahb.ko" | awk '{print $1}')"
        printf "CANDIDATE_CORE_SHA256='%s'\n" "$(sha256sum "$root/run/candidate/ath11k.ko" | awk '{print $1}')"
        printf "CANDIDATE_AHB_SHA256='%s'\n" "$(sha256sum "$root/run/candidate/ath11k_ahb.ko" | awk '{print $1}')"
        printf "EXPECTED_GATEWAY='192.0.2.1'\n"
        printf "MANAGEMENT_PEER='192.0.2.1'\n"
        printf "VALIDATION_SECONDS='3'\n"
        printf "POST_PERSIST_SECONDS='2'\n"
        printf "SAMPLE_SECONDS='1'\n"
        printf "REQUEST_GRACE_SECONDS='4'\n"
        printf "START_MIN_KB='70000'\n"
        printf "LOW_MEM_KB='25000'\n"
        printf "HEALTH_TIMEOUT_SECONDS='3'\n"
        printf "COMMAND_TIMEOUT_SECONDS='1'\n"
        printf "BASELINE_WAIT_SECONDS='9'\n"
        printf "MAX_MEM_DROP_KB='100'\n"
        printf "MAX_MEM_RANGE_KB='100'\n"
        printf "MIN_MEM_SLOPE_KB_PER_MIN='-1'\n"
        printf "MAX_PAGEFRAG_GROWTH_BYTES='100'\n"
        printf "MAX_PAGEFRAG_RANGE_BYTES='100'\n"
        printf "MAX_PAGEFRAG_SLOPE_BYTES_PER_MIN='100'\n"
        printf "PROC_ROOT_OVERRIDE='%s'\n" "$root/proc"
        printf "SYS_ROOT_OVERRIDE='%s'\n" "$root/sys"
        printf "MODULE_DIR_OVERRIDE='%s'\n" "$root/modules"
        printf "RELOAD_SCRIPT_OVERRIDE='%s'\n" "$root/bin/reload"
    } >"$root/run/manifest"
}

state_value() {
    local root=$1
    local key=$2
    awk -F= -v wanted="$key" '$1 == wanted {print $2}' "$root/run/state"
}

run_guard() {
    local root=$1
    local fault=$2
    local mode=${3:-run}
    if [[ $fault == hang_wifi ]]; then
        env PATH="$root/bin:$host_path" MOCK_ROOT="$root" MOCK_FAULT="$fault" \
            REAL_SLEEP="$real_sleep" REAL_CP="$real_cp" sh "$guard" "$root/run" "$mode"
    else
        env PATH="$root/bin:$host_path" MOCK_ROOT="$root" MOCK_FAULT="$fault" \
            REAL_SLEEP="$real_sleep" REAL_CP="$real_cp" RUN_BOUNDED_DIRECT_OVERRIDE=1 \
            sh "$guard" "$root/run" "$mode"
    fi
}

assert_case() {
    local name=$1
    local fault=$2
    local expected_state=$3
    local expected_reason=$4
    local root=$tmp/$name
    local rc=0

    make_fixture "$root"
    : >"$root/run/persist_request"
    : >"$root/run/commit_request"
    run_guard "$root" "$fault" || rc=$?
    [[ $(state_value "$root" state) == "$expected_state" ]]
    [[ $(state_value "$root" reason) == "$expected_reason" ]]
    [[ ! -e $root/run/guard.lock ]]
    if [[ $expected_state == rolled_back || $expected_state == rollback_failed ]]; then
        cmp -s "$root/run/stock/ath11k.ko" "$root/modules/ath11k.ko"
        cmp -s "$root/run/stock/ath11k_ahb.ko" "$root/modules/ath11k_ahb.ko"
    fi
    printf 'deploy_guard_case=%s state=%s reason=%s rc=%d\n' \
        "$name" "$expected_state" "$expected_reason" "$rc"
}

success_root=$tmp/success
make_fixture "$success_root"
mkdir "$success_root/run/guard.lock"
printf '999999\n' >"$success_root/run/guard.lock/pid"
: >"$success_root/run/persist_request"
: >"$success_root/run/commit_request"
run_guard "$success_root" none
[[ $(state_value "$success_root" state) == committed ]]
[[ $(grep -c 'result=pass' "$success_root/run/acceptance.log") == 2 ]]
cmp -s "$success_root/run/candidate/ath11k.ko" "$success_root/modules/ath11k.ko"
[[ ! -e $success_root/run/guard.lock ]]
printf 'deploy_guard_case=success_with_stale_lock state=committed\n'

run_guard "$success_root" none rollback
[[ $(state_value "$success_root" state) == rolled_back ]]
cmp -s "$success_root/run/stock/ath11k.ko" "$success_root/modules/ath11k.ko"
printf 'deploy_guard_case=manual_rollback state=rolled_back\n'

baseline_root=$tmp/baseline-reload
make_fixture "$baseline_root"
printf '1\n' >"$baseline_root/state/reload_running"
printf '0\n' >"$baseline_root/state/wifi_up"
: >"$baseline_root/run/persist_request"
: >"$baseline_root/run/commit_request"
run_guard "$baseline_root" baseline_reload
[[ $(state_value "$baseline_root" state) == committed ]]
[[ ! -e $baseline_root/state/candidate_reload_overlap ]]
printf 'deploy_guard_case=baseline_reload_waited_for_network state=committed\n'

active_root=$tmp/active-lock
make_fixture "$active_root"
mkdir "$active_root/run/guard.lock"
printf '%s\n' "$$" >"$active_root/run/guard.lock/pid"
active_rc=0
run_guard "$active_root" none || active_rc=$?
[[ $active_rc == 75 ]]
[[ ! -e $active_root/run/state ]]
printf 'deploy_guard_case=active_lock_rejected rc=75\n'

global_root=$tmp/global-lock
make_fixture "$global_root"
mkdir "$global_root/global.lock"
printf '/tmp/a-different-run\n' >"$global_root/global.lock/run_dir"
global_rc=0
run_guard "$global_root" none || global_rc=$?
[[ $global_rc == 75 ]]
[[ ! -e $global_root/run/guard.lock ]]
[[ ! -e $global_root/run/state ]]
printf 'deploy_guard_case=distinct_run_global_lock_rejected rc=75\n'

assert_case partial-load partial_candidate_load rolled_back candidate_load_failed
assert_case memguard-race memguard_race rolled_back candidate_health_failed
assert_case low-memory low_memory rolled_back low_memory
assert_case fatal-dmesg fatal_dmesg rolled_back candidate_fatal_dmesg
assert_case memguard-stopped memguard_stopped rollback_failed stock_health_failed
assert_case declining-memory declining_memory rolled_back transient_memory_not_flat
grep -q 'result=fail' "$tmp/declining-memory/run/acceptance.log"
assert_case signal-term signal_term rolled_back signal_term
assert_case network-failure network_failure rollback_failed stock_health_failed
assert_case reload-failure partial_candidate_load_reload_failure rollback_failed stock_reload_failed
assert_case marker-loss marker_loss rolled_back candidate_instance_changed
assert_case disk-mutation disk_mutation rolled_back disk_pair_not_stock_during_test
assert_case allocinfo-failure allocinfo_failure rolled_back allocinfo_pagefrag_unreadable
assert_case watchdog-stopped watchdog_stopped rolled_back hardware_watchdog_not_running
assert_case persistent-decline persistent_decline rolled_back persistent_memory_not_flat
assert_case command-timeout hang_wifi rolled_back candidate_load_failed
assert_case final-install-failure final_install_failure rolled_back final_candidate_install_failed

timeout_root=$tmp/request-timeout
make_fixture "$timeout_root"
timeout_rc=0
run_guard "$timeout_root" none || timeout_rc=$?
[[ $timeout_rc != 0 ]]
[[ $(state_value "$timeout_root" state) == rolled_back ]]
[[ $(state_value "$timeout_root" reason) == persist_request_timeout ]]
cmp -s "$timeout_root/run/stock/ath11k.ko" "$timeout_root/modules/ath11k.ko"
printf 'deploy_guard_case=request-timeout state=rolled_back reason=persist_request_timeout rc=%d\n' "$timeout_rc"

degraded_root=$tmp/degraded-rollback
make_fixture "$degraded_root"
: >"$degraded_root/proc/allocinfo"
printf '0\n' >"$degraded_root/state/watchdog"
run_guard "$degraded_root" none rollback
[[ $(state_value "$degraded_root" state) == rolled_back ]]
cmp -s "$degraded_root/run/stock/ath11k.ko" "$degraded_root/modules/ath11k.ko"
printf 'deploy_guard_case=degraded_rollback_preflight state=rolled_back\n'

printf 'deploy_guard_fault_cases=19\n'

liveness_root=$tmp/liveness
mkdir -p "$liveness_root/run/guard.lock"
probe_script=$liveness_root/guard.sh
printf '%s\n' '#!/bin/sh' 'sleep 30' >"$probe_script"
chmod 0700 "$probe_script"
"$probe_script" "$liveness_root/run" &
probe_pid=$!
printf '%s\n' "$probe_pid" >"$liveness_root/watchdog.pid"
printf '%s\n' "$probe_pid" >"$liveness_root/run/guard.lock/pid"
"$liveness" "$liveness_root/watchdog.pid" "$probe_script" "$liveness_root/run"

expect_liveness_rejection() {
	if "$liveness" "$@"; then
		printf 'expected liveness rejection for: %s\n' "$*" >&2
		return 1
	fi
}

printf '%s\n' "$((probe_pid + 1))" >"$liveness_root/run/guard.lock/pid"
expect_liveness_rejection "$liveness_root/watchdog.pid" "$probe_script" "$liveness_root/run"
printf '%s\n' "$probe_pid" >"$liveness_root/run/guard.lock/pid"
expect_liveness_rejection "$liveness_root/watchdog.pid" "$probe_script" "$liveness_root/wrong-run"
printf '%s\n' "$$" >"$liveness_root/stale.pid"
expect_liveness_rejection "$liveness_root/stale.pid" "$probe_script" "$liveness_root/run"
kill -TERM "$probe_pid" 2>/dev/null || true
wait "$probe_pid" 2>/dev/null || true
printf 'deploy_guard_liveness=shebang_cmdline_and_lock_pass\n'
