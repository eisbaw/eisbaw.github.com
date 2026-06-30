# Justfile for the niche-built blog. Run from the repo root.

# Local preview port for the ad-hoc HTTP server.
port := "8099"

# List recipes (default).
default:
    @just --list

# Build the static site into ./result (Nix flake output).
build:
    rm -f result
    nix build

# Kill any ad-hoc preview server this Justfile started.
stop:
    -pkill -f "http.server {{port}}"

# Stop a prior preview, rebuild, then serve ./result on {{port}} (Ctrl-C to quit).
serve: stop build
    @echo "Serving http://127.0.0.1:{{port}}/ — Ctrl-C to stop"
    cd result && python3 -m http.server {{port}} --bind 127.0.0.1

# Open the served site in the browser (serve must be running).
open:
    xdg-open "http://127.0.0.1:{{port}}/" 2>/dev/null || true

# Render URL in Brave with a throwaway, cache-disabled profile (fresh fetch; defaults to local server root — run `just serve` first).
preview url=("http://127.0.0.1:" + port + "/"):
    #!/usr/bin/env bash
    set -euo pipefail
    profile=$(mktemp -d /tmp/brave-fresh.XXXXXX)
    setsid brave \
      --user-data-dir="$profile" \
      --disk-cache-dir=/dev/null --disk-cache-size=1 \
      --no-first-run --no-default-browser-check \
      --new-window "{{url}}" >"$profile/brave.log" 2>&1 < /dev/null &
    disown
    echo "Brave (fresh profile $profile) -> {{url}}"
