#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
cycle=${1:-}
module=${2:-$repo_root/driver-analysis/debug-kernel/diagmod/rxown.ko}
# NOTE: address below is a placeholder (RFC5737 documentation range). Set RXOWN_ROUTER to your own router.
router=${RXOWN_ROUTER:-root@192.0.2.9}
interval=${RXOWN_INTERVAL_SECONDS:-12}
start_min_kb=${RXOWN_START_MIN_KB:-80000}
cutoff_kb=${RXOWN_CUTOFF_KB:-30000}
recovery_min_kb=${RXOWN_RECOVERY_MIN_KB:-80000}
max_seconds=${RXOWN_MAX_SECONDS:-1800}
stamp=$(date -u +%Y%m%d-%H%M%S)
prefix=$repo_root/driver-analysis/debug-kernel/rxown-${cycle:-unnamed}-$stamp
raw=$prefix.log
meta=$prefix.meta
ssh_options=(
    -o BatchMode=yes
    -o ConnectTimeout=8
    -o ServerAliveInterval=5
    -o ServerAliveCountMax=2
)
tmp=$(mktemp)
loaded=0
status=not_started

usage() {
    printf 'usage: %s CYCLE [RXOWN_KO]\n' "$0" >&2
    printf 'environment: RXOWN_INTERVAL_SECONDS RXOWN_START_MIN_KB RXOWN_CUTOFF_KB RXOWN_RECOVERY_MIN_KB RXOWN_MAX_SECONDS RXOWN_ROUTER\n' >&2
}

cleanup() {
    rm -f "$tmp"
    if ((loaded)); then
        ssh "${ssh_options[@]}" "$router" \
            'if lsmod | grep -q "^rxown "; then rmmod rxown; fi' \
            >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT

if [[ -z $cycle || $cycle == --help || $cycle == -h ]]; then
    usage
    [[ $cycle == --help || $cycle == -h ]] && exit 0
    exit 2
fi
[[ $cycle =~ ^[a-zA-Z0-9_-]+$ ]]
[[ $interval =~ ^[0-9]+$ && $start_min_kb =~ ^[0-9]+$ ]]
[[ $cutoff_kb =~ ^[0-9]+$ && $recovery_min_kb =~ ^[0-9]+$ ]]
[[ $max_seconds =~ ^[0-9]+$ ]]
test -s "$module"

module_sha=$(sha256sum "$module" | mawk '{print $1}')
module_vermagic=$(modinfo -F vermagic "$module")
test "$module_vermagic" = '6.12.87 SMP mod_unload aarch64'

ssh_run() {
    ssh "${ssh_options[@]}" "$router" "$@"
}

wait_for_router() {
    local deadline=$((SECONDS + 180))

    while ((SECONDS < deadline)); do
        if ssh_run 'true' >/dev/null 2>&1; then
            return 0
        fi
        sleep 3
    done
    return 1
}

router_mem_available() {
    ssh_run 'mawk '\''/^MemAvailable:/{print $2}'\'' /proc/meminfo 2>/dev/null || awk '\''/^MemAvailable:/{print $2}'\'' /proc/meminfo'
}

append_meta() {
    printf '%s\n' "$*" >>"$meta"
}

capture_snapshot() {
    local sequence=$1
    local phase=$2
    local attempt

    for attempt in 1 2 3; do
        if ssh_run 'set -eu
            printf "router_epoch=%s router_time=%s uptime_seconds=%s\n" \
                "$(date +%s)" "$(date -Iseconds)" "$(mawk "{print int(\$1)}" /proc/uptime 2>/dev/null || awk "{print int(\$1)}" /proc/uptime)"
            grep -E "^(MemAvailable|MemFree|Slab|SReclaimable|SUnreclaim):" /proc/meminfo
            grep -F "__page_frag_cache_refill" /proc/allocinfo || true
            printf "memguard_pids=%s\n" "$(pgrep -f "^/bin/sh /root/ath11k-memguard.sh$" | tr "\n" ",")"
            printf "tracing_on=%s kprobe_events=%s rxown_loaded=%s\n" \
                "$(cat /sys/kernel/debug/tracing/tracing_on 2>/dev/null || printf unknown)" \
                "$(grep -c . /sys/kernel/debug/tracing/kprobe_events 2>/dev/null || true)" \
                "$(lsmod | grep -c "^rxown " || true)"
            test -r /sys/kernel/debug/rxown/stats
            cat /sys/kernel/debug/rxown/stats' >"$tmp"; then
            {
                printf '=== SNAPSHOT sequence=%s phase=%s local_epoch=%s local_time=%s ===\n' \
                    "$sequence" "$phase" "$(date +%s)" "$(date -u -Iseconds)"
                cat "$tmp"
            } >>"$raw"
            return 0
        fi
        sleep 2
    done
    return 1
}

snapshot_value() {
    local key=$1

    mawk -v key="$key" '
        {
            for (i = 1; i <= NF; i++) {
                split($i, pair, "=")
                if (pair[1] == key) {
                    print pair[2]
                    exit
                }
            }
        }
    ' "$tmp"
}

validate_snapshot() {
    mawk '
        function values(line, fields, count, i, pair) {
            count = split(line, fields, /[[:space:]]+/)
            for (i = 1; i <= count; i++) {
                split(fields[i], pair, "=")
                value[pair[1]] = pair[2]
            }
        }
        /^failures / {
            delete value
            values($0)
            if (value["record_alloc"] || value["record_capacity"] ||
                value["page_alloc"] || value["page_capacity"] ||
                value["scope_alloc"] || value["ring_capacity"] ||
                value["caller_capacity"] || value["head_collision"] ||
                value["skb_collision"])
                bad = 1
            global_unmatched = value["idr_remove_unmatched"] + 0
            saw_failures = 1
        }
        /^nmissed / {
            delete value
            values($0)
            for (name in value)
                if (name != "nmissed" && value[name] + 0 != 0)
                    bad = 1
            saw_misses = 1
        }
        /^ring / {
            delete value
            values($0)
            if (!value["actual_valid"] || value["idr_alloc_failures"] ||
                value["release_while_posted"] ||
                value["known_idr_alloc_unmatched"])
                bad = 1
            if (value["idr"] == "(null)" || seen_idr[value["idr"]]++)
                bad = 1
            ring_allocations += value["allocations"]
            ring_posts += value["posts"]
            reinject_posts += value["reinject_posts"]
            ring_unmatched += value["untracked_removes"]
            rings++
        }
        /^ring_state / {
            delete value
            values($0)
            if (value["state"] == "allocated")
                allocated += value["current"]
        }
        /^allocations=/ {
            delete value
            values($0)
            scoped_allocations = value["scoped_allocations"] + 0
        }
        /^records=/ {
            delete value
            values($0)
            records = value["records"] + 0
            scoped_records = value["scoped_records"] + 0
        }
        /^unscoped / {
            delete value
            values($0)
            unscoped_current = value["current"] + 0
        }
        /^memguard_pids=/ {if ($0 == "memguard_pids=") bad = 1}
        /^tracing_on=/ {
            delete value
            values($0)
            if (value["tracing_on"] != 0 || value["kprobe_events"] != 0 ||
                value["rxown_loaded"] != 1)
                bad = 1
        }
        END {
            if (!saw_failures || !saw_misses || !rings)
                bad = 1
            if (allocated > 32)
                bad = 1
            if (ring_allocations + reinject_posts != ring_posts)
                bad = 1
            if (scoped_allocations != ring_allocations)
                bad = 1
            if (global_unmatched != ring_unmatched)
                bad = 1
            if (records != scoped_records + unscoped_current)
                bad = 1
            exit bad
        }
    ' "$tmp"
}

safe_unload_and_reload() {
    ssh_run 'set -eu
        if lsmod | grep -q "^rxown "; then
            rmmod rxown
        fi
        ! lsmod | grep -q "^rxown "
        test ! -e /sys/kernel/debug/rxown/stats
        printf "rxown_unloaded_before_reload=1\n"
        (sleep 1; /root/ath11k-reload.sh >/tmp/rxown-controlled-reload.log 2>&1 </dev/null) >/dev/null 2>&1 &'
    loaded=0
}

wait_for_recovery() {
    local deadline=$((SECONDS + 180))
    local available

    while ((SECONDS < deadline)); do
        if available=$(router_mem_available 2>/dev/null) &&
           [[ $available =~ ^[0-9]+$ ]] &&
           ((available >= recovery_min_kb)) &&
           ssh_run '! lsmod | grep -q "^rxown "; lsmod | grep -q "^ath11k "' \
               >/dev/null 2>&1; then
            {
                printf '=== RECOVERY local_epoch=%s local_time=%s ===\n' \
                    "$(date +%s)" "$(date -u -Iseconds)"
                ssh_run 'date -Iseconds; grep -E "^(MemAvailable|MemFree|Slab|SReclaimable|SUnreclaim):" /proc/meminfo; grep -F "__page_frag_cache_refill" /proc/allocinfo || true; lsmod | grep -E "^(ath11k|rxown)" || true'
            } >>"$raw"
            append_meta "recovery_mem_available_kb=$available"
            return 0
        fi
        sleep 3
    done
    return 1
}

available=$(router_mem_available)
[[ $available =~ ^[0-9]+$ ]]
if ((available < start_min_kb)); then
    printf 'router MemAvailable %s kB is below start minimum %s kB\n' \
        "$available" "$start_min_kb" >&2
    exit 1
fi

ssh_run 'set -eu
    ! lsmod | grep -q "^rxown "
    test "$(cat /sys/kernel/debug/tracing/tracing_on)" = 0
    test "$(grep -c . /sys/kernel/debug/tracing/kprobe_events || true)" = 0
    pgrep -f "^/bin/sh /root/ath11k-memguard.sh$" >/dev/null'

{
    printf 'cycle=%s\n' "$cycle"
    printf 'started_utc=%s\n' "$(date -u -Iseconds)"
    printf 'router=%s\n' "$router"
    printf 'module_path=%s\n' "$module"
    printf 'module_sha256=%s\n' "$module_sha"
    printf 'module_vermagic=%s\n' "$module_vermagic"
    printf 'interval_seconds=%s\n' "$interval"
    printf 'start_min_kb=%s\n' "$start_min_kb"
    printf 'cutoff_kb=%s\n' "$cutoff_kb"
    printf 'recovery_min_kb=%s\n' "$recovery_min_kb"
    printf 'max_seconds=%s\n' "$max_seconds"
    printf 'initial_mem_available_kb=%s\n' "$available"
} >"$meta"

upload_sha=$(ssh "${ssh_options[@]}" "$router" \
    'set -eu; umask 077; cat > /tmp/rxown.ko.new; mv /tmp/rxown.ko.new /tmp/rxown.ko; sha256sum /tmp/rxown.ko | cut -d" " -f1' \
    <"$module")
test "$upload_sha" = "$module_sha"
append_meta "uploaded_sha256=$upload_sha"

ssh_run 'set -eu
    insmod /tmp/rxown.ko
    lsmod | grep -q "^rxown "
    test -r /sys/kernel/debug/rxown/stats
    test "$(cat /sys/kernel/debug/tracing/tracing_on)" = 0'
loaded=1
status=collecting
start=$SECONDS
sequence=0
sleep 2

while ((SECONDS - start < max_seconds)); do
    sequence=$((sequence + 1))
    if ! capture_snapshot "$sequence" growth; then
        status=ssh_capture_failure
        append_meta "integrity_failure=ssh_capture_failure_sequence_$sequence"
        break
    fi
    available=$(mawk '/^MemAvailable:/{print $2; exit}' "$tmp")
    if ! validate_snapshot; then
        status=integrity_failure
        append_meta "integrity_failure=snapshot_$sequence"
        break
    fi
    printf 'cycle=%s snapshot=%s elapsed=%ss MemAvailable=%skB tracked_backing=%s scoped=%s\n' \
        "$cycle" "$sequence" "$((SECONDS - start))" "$available" \
        "$(snapshot_value tracked_backing_bytes)" \
        "$(snapshot_value scoped_allocations)"
    if ((available <= cutoff_kb)); then
        status=cutoff_reached
        append_meta "cutoff_sequence=$sequence"
        append_meta "cutoff_mem_available_kb=$available"
        break
    fi
    sleep "$interval"
done

if [[ $status == collecting ]]; then
    status=max_duration_reached
    append_meta "integrity_failure=max_duration_without_cutoff"
fi

if ((loaded)); then
    safe_unload_and_reload >>"$raw"
fi
if ! wait_for_recovery; then
    status=recovery_timeout
    append_meta "integrity_failure=recovery_timeout"
fi

append_meta "finished_utc=$(date -u -Iseconds)"
append_meta "snapshots=$sequence"
append_meta "status=$status"
printf 'artifact_log=%s\nartifact_meta=%s\nstatus=%s\n' "$raw" "$meta" "$status"

[[ $status == cutoff_reached ]]
