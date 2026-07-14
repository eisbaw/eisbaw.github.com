# Justfile for the niche-built blog. Run from the repo root.

# Local preview port for the ad-hoc HTTP server.
port := "8099"

# Parent dir for throwaway Brave preview profiles — safe to rm -rf wholesale.
preview-dir := "/tmp/" + env_var_or_default("USER", "user") + "/blog-preview"

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

# Kill any prior server, rebuild, then (re)start a background server on {{port}}.
serve: stop build
    #!/usr/bin/env bash
    set -euo pipefail
    setsid python3 -m http.server {{port}} --bind 127.0.0.1 --directory result \
      >"/tmp/blog-serve-{{port}}.log" 2>&1 < /dev/null &
    disown
    # Block until it actually answers, so dependents (preview) can rely on it.
    curl -sf --retry 50 --retry-delay 1 --retry-connrefused -o /dev/null "http://127.0.0.1:{{port}}/"
    echo "Serving http://127.0.0.1:{{port}}/ (background; log: /tmp/blog-serve-{{port}}.log)"

# Open the served site in the browser (serve must be running).
open:
    xdg-open "http://127.0.0.1:{{port}}/" 2>/dev/null || true

# Render URL in Brave with a throwaway, cache-disabled profile (fresh fetch; (re)starts the server first via `serve`).
preview url=("http://127.0.0.1:" + port + "/"): serve
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p "{{preview-dir}}"
    profile=$(mktemp -d "{{preview-dir}}/profile.XXXXXX")
    # Drop any ephemeral TMPDIR (nix-shell / nix develop set one and delete it on
    # exit). The detached browser outlives this shell and needs a persistent temp
    # dir for its ProcessSingleton socket, or it aborts before opening a window.
    env -u TMPDIR setsid brave \
      --user-data-dir="$profile" \
      --disk-cache-dir=/dev/null --disk-cache-size=1 \
      --no-first-run --no-default-browser-check \
      --new-window "{{url}}" >"$profile/brave.log" 2>&1 < /dev/null &
    disown
    echo "Brave (fresh profile $profile) -> {{url}}"

# The [p] bracket keeps pkill's own shell from matching the pattern.
# Close preview Brave windows and delete all throwaway preview profiles.
clean-preview:
    -pkill -9 -f "user-data-dir={{preview-dir}}/[p]rofile"
    rm -rf "{{preview-dir}}"
    @echo "Removed {{preview-dir}}"
