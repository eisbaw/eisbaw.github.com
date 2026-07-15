#!/bin/sh
# ath11k-reload.sh - release ath11k-associated page-frag backing by reloading.
# Reloads ALL wifi including the STA uplink (phy0-sta0), so it briefly drops this
# box's connectivity (~10-20s). MUST be run detached (setsid, no controlling tty)
# so it survives its own uplink drop - if launched from an ssh session it would
# otherwise die at `wifi down` before `wifi up` runs.
#
# Logs MemAvailable before/after via logger so the effect shows in the klog
# stream. If the reload botches the uplink, the qcom watchdog is still armed and
# will recover the box - that's why we keep the watchdog enabled.
log() { logger -t ath11k-reload "$*"; }
avail() { awk '/^MemAvailable:/{print $2}' /proc/meminfo; }

log "reload start: MemAvailable=$(avail) kB uptime=$(awk '{print int($1)}' /proc/uptime)s"
wifi down
sleep 2
rmmod ath11k_ahb 2>/dev/null
rmmod ath11k 2>/dev/null
sleep 1
modprobe ath11k
modprobe ath11k_ahb
sleep 2
wifi up
sleep 10
log "reload done:  MemAvailable=$(avail) kB"
