#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
container=${OPENWRT_CONTAINER:-owrt-build}
tree=${OPENWRT_TREE:-/work/openwrt-tree}
# NOTE: addresses below are placeholders (RFC5737 documentation range). Override via ATH11K_ROUTER / ATH11K_MANAGEMENT_PEER.
router=${ATH11K_ROUTER:-root@192.0.2.9}
management_peer=${ATH11K_MANAGEMENT_PEER:-192.0.2.1}
command=${1:-status}
kernel=6.12.87
candidate_marker_value=Y
module_root=$tree/build_dir/target-aarch64_cortex-a53_musl/linux-qualcommax_ipq807x/mac80211-regular/backports-6.18.26
container_candidate_core=$module_root/ipkg-aarch64_cortex-a53/kmod-ath11k/lib/modules/$kernel/ath11k.ko
container_candidate_ahb=$module_root/ipkg-aarch64_cortex-a53/kmod-ath11k-ahb/lib/modules/$kernel/ath11k_ahb.ko
patch_path=$repo_root/driver-analysis/debug-kernel/949-wifi-ath11k-use-private-page-frag-caches-for-rxdma.patch
marker_path=$repo_root/driver-analysis/debug-kernel/950-wifi-ath11k-mark-private-rxfrag-validation-build.patch
guard_path=$repo_root/driver-analysis/debug-kernel/ath11k-private-cache-guard.sh
liveness_path=$repo_root/driver-analysis/debug-kernel/ath11k-private-cache-liveness.sh
package_patch=$tree/package/kernel/mac80211/patches/ath11k/$(basename "$patch_path")
package_marker=$tree/package/kernel/mac80211/patches/ath11k/$(basename "$marker_path")
# These SHA256 baselines pin one specific local build; recompute them for yours.
stock_core_sha=a4eca0ed1d2c395d4f49ffb53f04cae6f82fc93baad5ee2e04fc7da8d75146fd
stock_ahb_sha=3626423d44fdfc74e21f5fc0a5cf171db47dc763533a6d205c05d0f4516fb573
candidate_core_sha_expected=841d064a89620c175111b4095aa75aec109fed1c8c4b0e6efaa680497b306b9a
validation_seconds=${ATH11K_VALIDATION_SECONDS:-1800}
post_persist_seconds=${ATH11K_POST_PERSIST_SECONDS:-300}
sample_seconds=${ATH11K_SAMPLE_SECONDS:-10}
request_grace_seconds=${ATH11K_REQUEST_GRACE_SECONDS:-300}
start_min_kb=${ATH11K_START_MIN_KB:-70000}
low_mem_kb=${ATH11K_LOW_MEM_KB:-25000}
health_timeout_seconds=${ATH11K_HEALTH_TIMEOUT_SECONDS:-120}
command_timeout_seconds=${ATH11K_COMMAND_TIMEOUT_SECONDS:-90}
baseline_wait_seconds=${ATH11K_BASELINE_WAIT_SECONDS:-300}
max_mem_drop_kb=${ATH11K_MAX_MEM_DROP_KB:-8192}
max_mem_range_kb=${ATH11K_MAX_MEM_RANGE_KB:-12288}
min_mem_slope_kb_per_min=${ATH11K_MIN_MEM_SLOPE_KB_PER_MIN:--256}
max_pagefrag_growth_bytes=${ATH11K_MAX_PAGEFRAG_GROWTH_BYTES:-8388608}
max_pagefrag_range_bytes=${ATH11K_MAX_PAGEFRAG_RANGE_BYTES:-12582912}
max_pagefrag_slope_bytes_per_min=${ATH11K_MAX_PAGEFRAG_SLOPE_BYTES_PER_MIN:-262144}
ssh_options=(
    -o BatchMode=yes
    -o ConnectTimeout=8
    -o ServerAliveInterval=5
    -o ServerAliveCountMax=2
)
stage_dir=
manifest=
candidate_core=
candidate_ahb=
candidate_core_sha=
candidate_ahb_sha=
global_lock_dir=/root/ath11k-private-cache-global.lock
owned_global_run=
guard_started=0

cleanup_local() {
    if [[ -n ${owned_global_run:-} && $guard_started == 0 ]]; then
        ssh_run "owner=\$(cat '$global_lock_dir/run_dir' 2>/dev/null || true)
            if test \"\$owner\" = '$owned_global_run' &&
               test \"\$(cat '$global_lock_dir/phase' 2>/dev/null || true)\" = staging &&
               test ! -r '$global_lock_dir/pid' &&
               test \"\$(cat /root/ath11k-private-cache-current 2>/dev/null || true)\" != '$owned_global_run' &&
               test ! -e /sys/module/ath11k/parameters/private_rxfrag &&
               test \"\$(sha256sum /lib/modules/$kernel/ath11k.ko | cut -d' ' -f1)\" = '$stock_core_sha' &&
               test \"\$(sha256sum /lib/modules/$kernel/ath11k_ahb.ko | cut -d' ' -f1)\" = '$stock_ahb_sha'; then
                rm -f '$global_lock_dir/pid' '$global_lock_dir/run_dir' '$global_lock_dir/phase' '$global_lock_dir/created_epoch'
                rmdir '$global_lock_dir' 2>/dev/null || true
            fi" >/dev/null 2>&1 || true
    fi
    [[ -z ${stage_dir:-} ]] || rm -rf "$stage_dir"
    [[ -z ${manifest:-} ]] || rm -f "$manifest"
}
trap cleanup_local EXIT

usage() {
    printf 'usage: %s start|status|persist|commit|rollback|validate-local\n' "$0" >&2
    printf 'start and persist keep stock files on disk; only commit installs the candidate.\n' >&2
}

ssh_run() {
    ssh "${ssh_options[@]}" "$router" "$@"
}

validate_run_dir() {
    [[ $1 =~ ^/root/ath11k-private-cache-[A-Za-z0-9-]+$ ]]
}

current_run() {
    local run_dir
    run_dir=$(ssh_run 'set -eu; test -r /root/ath11k-private-cache-current; cat /root/ath11k-private-cache-current') || return 1
    validate_run_dir "$run_dir" || return 1
    printf '%s\n' "$run_dir"
}

remote_state() {
    local run_dir=$1
    validate_run_dir "$run_dir" || return 1
    ssh_run "test -r '$run_dir/state' && awk -F= '\$1 == \"state\" {print \$2}' '$run_dir/state'"
}

guard_alive() {
    local run_dir=$1
    validate_run_dir "$run_dir" || return 1
    ssh_run "test -x '$run_dir/liveness.sh' || exit 1
    for pidfile in '$run_dir/watchdog.pid' '$run_dir/manual-rollback.pid' '$run_dir/guard.lock/pid'; do
        if '$run_dir/liveness.sh' \"\$pidfile\" '$run_dir/guard.sh' '$run_dir'; then
            exit 0
        fi
    done
    exit 1"
}

acquire_global_lock() {
    local run_dir=$1
    local owner phase age
    validate_run_dir "$run_dir" || return 1
    if ssh_run "set -eu; mkdir '$global_lock_dir'; printf '%s\n' '$run_dir' > '$global_lock_dir/run_dir'; printf 'staging\n' > '$global_lock_dir/phase'; date +%s > '$global_lock_dir/created_epoch'"; then
        owned_global_run=$run_dir
        return 0
    fi

    owner=$(ssh_run "cat '$global_lock_dir/run_dir' 2>/dev/null" || true)
    phase=$(ssh_run "cat '$global_lock_dir/phase' 2>/dev/null" || true)
    if [[ $phase == staging ]]; then
        age=$(ssh_run "now=\$(date +%s); created=\$(cat '$global_lock_dir/created_epoch' 2>/dev/null || echo 0); echo \$((now - created))")
        if [[ $age =~ ^[0-9]+$ ]] && ((age < 600)); then
            printf 'global deployment staging lock is active: %s age=%ss\n' "${owner:-missing-owner}" "$age" >&2
            return 1
        fi
    fi
    if validate_run_dir "$owner" && guard_alive "$owner" 2>/dev/null; then
        printf 'global deployment lock is active: %s\n' "$owner" >&2
        return 1
    fi
    if validate_run_dir "$owner" &&
       ssh_run "test -r '$owner/manifest' && test -x '$owner/guard.sh' && test -x '$owner/liveness.sh'" 2>/dev/null; then
        printf 'recovering dead global-lock owner: %s\n' "$owner" >&2
        recover_dead_guard "$owner" || return 1
    else
        printf 'releasing incomplete stock-safe global stage: %s\n' "${owner:-missing-owner}" >&2
        ssh_run "set -eu
            test ! -e /sys/module/ath11k/parameters/private_rxfrag
            test \"\$(sha256sum /lib/modules/$kernel/ath11k.ko | cut -d' ' -f1)\" = '$stock_core_sha'
            test \"\$(sha256sum /lib/modules/$kernel/ath11k_ahb.ko | cut -d' ' -f1)\" = '$stock_ahb_sha'
            test \"\$(cat '$global_lock_dir/run_dir' 2>/dev/null || true)\" = '$owner'
            rm -f '$global_lock_dir/pid' '$global_lock_dir/run_dir' '$global_lock_dir/phase' '$global_lock_dir/created_epoch'
            rmdir '$global_lock_dir'"
    fi

    ssh_run "set -eu; mkdir '$global_lock_dir'; printf '%s\n' '$run_dir' > '$global_lock_dir/run_dir'; printf 'staging\n' > '$global_lock_dir/phase'; date +%s > '$global_lock_dir/created_epoch'"
    owned_global_run=$run_dir
}

release_global_lock() {
    local run_dir=$1
    validate_run_dir "$run_dir" || return 1
    ssh_run "set -eu; test \"\$(cat '$global_lock_dir/run_dir')\" = '$run_dir'; rm -f '$global_lock_dir/pid' '$global_lock_dir/run_dir' '$global_lock_dir/phase' '$global_lock_dir/created_epoch'; rmdir '$global_lock_dir'"
    owned_global_run=
}

wait_for_state() {
    local run_dir=$1
    local timeout=$2
    local success=$3
    shift 3
    local deadline=$((SECONDS + timeout))
    local state expected liveness_failed_since=

    while ((SECONDS < deadline)); do
        state=$(remote_state "$run_dir" 2>/dev/null || true)
        if [[ $state == "$success" ]]; then
            printf 'run_dir=%s\nstate=%s\n' "$run_dir" "$state"
            return 0
        fi
        for expected in "$@"; do
            if [[ $state == "$expected" ]]; then
                printf 'run_dir=%s\nstate=%s\n' "$run_dir" "$state" >&2
                return 1
            fi
        done
        if guard_alive "$run_dir" 2>/dev/null; then
            liveness_failed_since=
        elif [[ -z $liveness_failed_since ]]; then
            liveness_failed_since=$SECONDS
        elif ((SECONDS - liveness_failed_since >= 30)); then
            printf 'guard unavailable for 30s before state %s (last state=%s)\n' \
                "$success" "${state:-missing}" >&2
            if recover_dead_guard "$run_dir"; then
                [[ $success == rolled_back ]]
                return $?
            fi
            return 1
        fi
        sleep 3
    done
    printf 'timed out waiting for state %s in %s\n' "$success" "$run_dir" >&2
    return 1
}

upload_file() {
    local source=$1
    local destination=$2
    ssh "${ssh_options[@]}" "$router" \
        "set -eu; umask 077; cat > '$destination.new'; mv '$destination.new' '$destination'" \
        <"$source"
}

validate_number() {
    [[ $1 =~ ^[0-9]+$ ]]
}

validate_integer() {
    [[ $1 =~ ^-?[0-9]+$ ]]
}

start_manual_rollback() {
    local run_dir=$1
    validate_run_dir "$run_dir" || return 1
    ssh_run "set -eu
        test -x '$run_dir/liveness.sh'
        for pidfile in '$run_dir/watchdog.pid' '$run_dir/manual-rollback.pid' '$run_dir/guard.lock/pid'; do
            if '$run_dir/liveness.sh' \"\$pidfile\" '$run_dir/guard.sh' '$run_dir'; then
                exit 75
            fi
        done
        rm -f '$run_dir/manual-rollback.pid'
        start-stop-daemon -S -b -m -p '$run_dir/manual-rollback.pid' \
            -x '$run_dir/guard.sh' -O '$run_dir/manual-rollback.log' -- '$run_dir' rollback"
}

recover_dead_guard() {
    local run_dir=$1
    local deadline state

    start_manual_rollback "$run_dir" || return 1
    deadline=$((SECONDS + 240))
    while ((SECONDS < deadline)); do
        state=$(remote_state "$run_dir" 2>/dev/null || true)
        case $state in
            rolled_back)
                printf 'run_dir=%s\nstate=rolled_back\n' "$run_dir" >&2
                return 0
                ;;
            rollback_failed)
                printf 'run_dir=%s\nstate=rollback_failed\n' "$run_dir" >&2
                return 1
                ;;
        esac
        sleep 3
    done
    printf 'manual dead-guard recovery timed out for %s\n' "$run_dir" >&2
    return 1
}

reconcile_previous_run() {
    local run_dir=$1
    local state
    state=$(remote_state "$run_dir" 2>/dev/null || true)

    if guard_alive "$run_dir" 2>/dev/null; then
        printf 'active run already exists: %s state=%s\n' "$run_dir" "${state:-missing}" >&2
        return 1
    fi
    case $state in
        rolled_back) return 0 ;;
        committed)
            printf 'previous run is committed; roll it back before starting another test\n' >&2
            return 1
            ;;
        *)
            printf 'reconciling dead previous guard: %s state=%s\n' "$run_dir" "${state:-missing}" >&2
            start_manual_rollback "$run_dir"
            wait_for_state "$run_dir" 240 rolled_back rollback_failed
            ;;
    esac
}

validate_candidate_modules() {
    local core=$1
    local ahb=$2
    local module module_file module_strings module_parameters

    for module in "$core" "$ahb"; do
        test -s "$module"
        module_file=$(file "$module")
        [[ $module_file == *'ELF 64-bit LSB relocatable, ARM aarch64'* ]]
        test "$(modinfo -F vermagic "$module")" = '6.12.87 SMP mod_unload aarch64'
    done
    module_strings=$(strings "$core")
    grep -Fxq 'private_rxfrag' <<<"$module_strings"
    module_parameters=$(modinfo -p "$core")
    grep -Eq '^private_rxfrag:' <<<"$module_parameters"
}

stage_candidate_modules() {
    stage_dir=$(mktemp -d)
    candidate_core=$stage_dir/ath11k.ko
    candidate_ahb=$stage_dir/ath11k_ahb.ko
    docker exec "$container" test -s "$container_candidate_core"
    docker exec "$container" test -s "$container_candidate_ahb"
    docker cp "$container:$container_candidate_core" "$candidate_core" >/dev/null
    docker cp "$container:$container_candidate_ahb" "$candidate_ahb" >/dev/null
    validate_candidate_modules "$candidate_core" "$candidate_ahb"
    candidate_core_sha=$(sha256sum "$candidate_core" | mawk '{print $1}')
    candidate_ahb_sha=$(sha256sum "$candidate_ahb" | mawk '{print $1}')
    test "$candidate_core_sha" = "$candidate_core_sha_expected"
    test "$candidate_ahb_sha" = "$stock_ahb_sha"
}

validate_local_candidate() {
    docker inspect "$container" >/dev/null
    stage_candidate_modules
    printf 'candidate_core_sha256=%s\ncandidate_ahb_sha256=%s\nlocal_candidate_validation=pass\n' \
        "$candidate_core_sha" "$candidate_ahb_sha"
}

remote_preflight() {
    ssh_run "set -eu
        test \"\$(uname -r)\" = '$kernel'
        test \"\$(sha256sum /lib/modules/$kernel/ath11k.ko | cut -d' ' -f1)\" = '$stock_core_sha'
        test \"\$(sha256sum /lib/modules/$kernel/ath11k_ahb.ko | cut -d' ' -f1)\" = '$stock_ahb_sha'
        test ! -e /sys/module/ath11k/parameters/private_rxfrag
        ! lsmod | grep -q '^rxown '
        test \"\$(cat /sys/kernel/debug/tracing/tracing_on)\" = 0
        test \"\$(grep -c . /sys/kernel/debug/tracing/kprobe_events || true)\" = 0
        pgrep -f '^/bin/sh /root/ath11k-memguard.sh$' >/dev/null
        test -x /root/ath11k-reload.sh
        test -r /proc/allocinfo
        awk '/func:__page_frag_cache_refill/{sum += \$1; found=1} END {exit(found ? 0 : 1)}' /proc/allocinfo
        for required in awk cat chmod cp date dmesg grep insmod ip iw kill logger logread lsmod mkdir modprobe mv pgrep ping rm rmdir rmmod sed sha256sum sleep start-stop-daemon sync tr ubus uname wc wifi; do
            command -v \"\$required\" >/dev/null
        done
        ubus call system watchdog | grep -Eq '\"status\"[[:space:]]*:[[:space:]]*\"running\"'
        ping -c 1 -W 1 '$management_peer' >/dev/null"
}

start_test() {
    local run_id run_dir
    local local_patch_sha installed_patch_sha local_marker_sha installed_marker_sha
    local gateway existing

    for value in "$validation_seconds" "$post_persist_seconds" "$sample_seconds" \
                 "$request_grace_seconds" "$start_min_kb" "$low_mem_kb" \
                 "$health_timeout_seconds" "$command_timeout_seconds" "$baseline_wait_seconds" \
                 "$max_mem_drop_kb" "$max_mem_range_kb" \
                 "$max_pagefrag_growth_bytes" "$max_pagefrag_range_bytes" \
                 "$max_pagefrag_slope_bytes_per_min"; do
        validate_number "$value"
    done
    validate_integer "$min_mem_slope_kb_per_min"
    [[ $management_peer =~ ^[0-9a-fA-F:.]+$ ]]
    ((validation_seconds >= 1800))
    ((post_persist_seconds >= 300))
    ((sample_seconds > 0 && sample_seconds <= 10))
    ((request_grace_seconds <= 300))
    ((health_timeout_seconds <= 120))
    ((command_timeout_seconds >= 15 && command_timeout_seconds <= 90))
    ((baseline_wait_seconds >= 120 && baseline_wait_seconds <= 300))
    ((start_min_kb >= 70000))
    ((low_mem_kb >= 25000))
    ((low_mem_kb < start_min_kb))
    ((max_mem_drop_kb <= 8192))
    ((max_mem_range_kb <= 12288))
    ((min_mem_slope_kb_per_min >= -256))
    ((max_pagefrag_growth_bytes <= 8388608))
    ((max_pagefrag_range_bytes <= 12582912))
    ((max_pagefrag_slope_bytes_per_min <= 262144))

    test -s "$patch_path"
    test -s "$marker_path"
    test -s "$guard_path"
    test -s "$liveness_path"
    bash -n "$0"
    sh -n "$guard_path"
    sh -n "$liveness_path"
    docker inspect "$container" >/dev/null

    local_patch_sha=$(sha256sum "$patch_path" | mawk '{print $1}')
    installed_patch_sha=$(docker exec -u ubuntu "$container" sha256sum "$package_patch" | mawk '{print $1}')
    test "$local_patch_sha" = "$installed_patch_sha"
    local_marker_sha=$(sha256sum "$marker_path" | mawk '{print $1}')
    installed_marker_sha=$(docker exec -u ubuntu "$container" sha256sum "$package_marker" | mawk '{print $1}')
    test "$local_marker_sha" = "$installed_marker_sha"

    manifest=$(mktemp)
    stage_candidate_modules

    if existing=$(current_run 2>/dev/null); then
        reconcile_previous_run "$existing"
    fi
    remote_preflight

    gateway=$(ssh_run "ip route show default | awk 'NR == 1 {print \$3}'")
    [[ $gateway =~ ^[0-9a-fA-F:.]+$ ]]
    ssh_run "ping -c 1 -W 1 '$gateway' >/dev/null"
    run_id=$(date -u +%Y%m%d-%H%M%S)-$$
    run_dir=/root/ath11k-private-cache-$run_id
    acquire_global_lock "$run_dir"

    {
        printf "RUN_ID='%s'\n" "$run_id"
        printf "KERNEL_RELEASE='%s'\n" "$kernel"
        printf "GLOBAL_LOCK_DIR_OVERRIDE='%s'\n" "$global_lock_dir"
        printf "CANDIDATE_MARKER_VALUE='%s'\n" "$candidate_marker_value"
        printf "STOCK_CORE_SHA256='%s'\n" "$stock_core_sha"
        printf "STOCK_AHB_SHA256='%s'\n" "$stock_ahb_sha"
        printf "CANDIDATE_CORE_SHA256='%s'\n" "$candidate_core_sha"
        printf "CANDIDATE_AHB_SHA256='%s'\n" "$candidate_ahb_sha"
        printf "EXPECTED_GATEWAY='%s'\n" "$gateway"
        printf "MANAGEMENT_PEER='%s'\n" "$management_peer"
        printf "VALIDATION_SECONDS='%s'\n" "$validation_seconds"
        printf "POST_PERSIST_SECONDS='%s'\n" "$post_persist_seconds"
        printf "SAMPLE_SECONDS='%s'\n" "$sample_seconds"
        printf "REQUEST_GRACE_SECONDS='%s'\n" "$request_grace_seconds"
        printf "START_MIN_KB='%s'\n" "$start_min_kb"
        printf "LOW_MEM_KB='%s'\n" "$low_mem_kb"
        printf "HEALTH_TIMEOUT_SECONDS='%s'\n" "$health_timeout_seconds"
        printf "COMMAND_TIMEOUT_SECONDS='%s'\n" "$command_timeout_seconds"
        printf "BASELINE_WAIT_SECONDS='%s'\n" "$baseline_wait_seconds"
        printf "MAX_MEM_DROP_KB='%s'\n" "$max_mem_drop_kb"
        printf "MAX_MEM_RANGE_KB='%s'\n" "$max_mem_range_kb"
        printf "MIN_MEM_SLOPE_KB_PER_MIN='%s'\n" "$min_mem_slope_kb_per_min"
        printf "MAX_PAGEFRAG_GROWTH_BYTES='%s'\n" "$max_pagefrag_growth_bytes"
        printf "MAX_PAGEFRAG_RANGE_BYTES='%s'\n" "$max_pagefrag_range_bytes"
        printf "MAX_PAGEFRAG_SLOPE_BYTES_PER_MIN='%s'\n" "$max_pagefrag_slope_bytes_per_min"
    } >"$manifest"

    ssh_run "set -eu; umask 077; mkdir -p '$run_dir/stock' '$run_dir/candidate'; cp /lib/modules/$kernel/ath11k.ko '$run_dir/stock/'; cp /lib/modules/$kernel/ath11k_ahb.ko '$run_dir/stock/'"
    upload_file "$manifest" "$run_dir/manifest"
    upload_file "$guard_path" "$run_dir/guard.sh"
    upload_file "$liveness_path" "$run_dir/liveness.sh"
    upload_file "$candidate_core" "$run_dir/candidate/ath11k.ko"
    upload_file "$candidate_ahb" "$run_dir/candidate/ath11k_ahb.ko"
    ssh_run "set -eu
        test \"\$(sha256sum '$run_dir/stock/ath11k.ko' | cut -d' ' -f1)\" = '$stock_core_sha'
        test \"\$(sha256sum '$run_dir/stock/ath11k_ahb.ko' | cut -d' ' -f1)\" = '$stock_ahb_sha'
        test \"\$(sha256sum '$run_dir/candidate/ath11k.ko' | cut -d' ' -f1)\" = '$candidate_core_sha'
        test \"\$(sha256sum '$run_dir/candidate/ath11k_ahb.ko' | cut -d' ' -f1)\" = '$candidate_ahb_sha'
        sh -n '$run_dir/guard.sh'
        sh -n '$run_dir/liveness.sh'
        chmod 0700 '$run_dir/guard.sh' '$run_dir/liveness.sh'
        printf '%s\n' '$run_dir' > /root/ath11k-private-cache-current"
    ssh_run "rm -f '$run_dir/watchdog.pid'; start-stop-daemon -S -b -m -p '$run_dir/watchdog.pid' -x '$run_dir/guard.sh' -O '$run_dir/nohup.log' -- '$run_dir'"
    guard_started=1
    wait_for_state "$run_dir" "$((baseline_wait_seconds + health_timeout_seconds + 120))" monitoring rolled_back rollback_failed
}

show_status() {
    local run_dir liveness
    run_dir=$(current_run)
    if guard_alive "$run_dir" 2>/dev/null; then liveness=running; else liveness=stopped; fi
    ssh_run "printf '%s\n' 'run_dir=$run_dir' 'guard=$liveness'; cat '$run_dir/state'; tail -n 12 '$run_dir/metrics.csv' 2>/dev/null || true; cat '$run_dir/acceptance.log' 2>/dev/null || true; tail -n 30 '$run_dir/watchdog.log' 2>/dev/null || true"
}

request_transition() {
    local request=$1
    local required=$2
    local success=$3
    local timeout=$4
    local run_dir state

    run_dir=$(current_run)
    state=$(remote_state "$run_dir")
    [[ $state == "$required" ]] || {
        printf 'run %s is state=%s, expected %s\n' "$run_dir" "$state" "$required" >&2
        return 1
    }
    guard_alive "$run_dir" || {
        printf 'guard is not running; use rollback to reconcile safely\n' >&2
        return 1
    }
    ssh_run "set -eu; : > '$run_dir/$request'"
    wait_for_state "$run_dir" "$timeout" "$success" rolled_back rollback_failed
}

rollback_test() {
    local run_dir state
    run_dir=$(current_run)
    state=$(remote_state "$run_dir" 2>/dev/null || true)
    if [[ $state == rolled_back ]]; then
        printf 'run_dir=%s\nstate=rolled_back\n' "$run_dir"
        return 0
    fi
    if guard_alive "$run_dir" 2>/dev/null; then
        ssh_run "set -eu; : > '$run_dir/rollback_request'"
    else
        start_manual_rollback "$run_dir"
    fi
    wait_for_state "$run_dir" 240 rolled_back rollback_failed
}

case $command in
    start) start_test ;;
    status) show_status ;;
    persist) request_transition persist_request eligible persist_monitoring 300 ;;
    commit) request_transition commit_request persist_eligible committed 300 ;;
    rollback) rollback_test ;;
    validate-local) validate_local_candidate ;;
    -h|--help|help) usage ;;
    *) usage; exit 2 ;;
esac
