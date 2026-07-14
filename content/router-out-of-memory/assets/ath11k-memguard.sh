#!/bin/sh
# ath11k-memguard.sh - keep the box out of OOM by reloading ath11k before memory
# is exhausted. Checks MemAvailable every INTERVAL s; when it falls below THRESH,
# reloads the driver (which frees ath11k's leaked kernel pages). This keeps the
# router up and reachable and avoids the OOM -> watchdog-reset loop, WITHOUT
# disabling the watchdog (kept as the last-resort safety net).
#
# Runs as a procd service (see /etc/init.d/ath11k-memguard). BOOT_GRACE lets wifi
# associate first. MIN_GAP prevents reload thrashing if memory stays low.
THRESH=${THRESH:-30000}     # kB - reload when MemAvailable drops below this
INTERVAL=${INTERVAL:-30}    # s  - check cadence
BOOT_GRACE=${BOOT_GRACE:-180}
MIN_GAP=${MIN_GAP:-120}     # s  - minimum seconds between reloads

avail() { awk '/^MemAvailable:/{print $2}' /proc/meminfo; }
now()   { awk '{print int($1)}' /proc/uptime; }

sleep "$BOOT_GRACE"
logger -t ath11k-memguard "started: reload when MemAvailable < ${THRESH}kB (check ${INTERVAL}s)"
last=0
while :; do
	a=$(avail)
	if [ "${a:-999999}" -lt "$THRESH" ] && [ $(( $(now) - last )) -ge "$MIN_GAP" ]; then
		logger -t ath11k-memguard "MemAvailable ${a}kB < ${THRESH}kB -> reloading ath11k"
		/root/ath11k-reload.sh
		last=$(now)
	fi
	sleep "$INTERVAL"
done
