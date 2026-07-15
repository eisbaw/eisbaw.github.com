#!/usr/bin/env bash
set -euo pipefail

site_root=${1:-result}

python3 -m unittest discover -s scripts -p 'test_*.py' -v
python3 scripts/check-site.py "$site_root"

while IFS= read -r -d '' test_file; do
    python3 "$test_file"
done < <(find content -type f -name 'test_*.py' -print0 | sort -z)

while IFS= read -r -d '' shell_file; do
    bash -n "$shell_file"
done < <(find content -type f -name '*.sh' -print0 | sort -z)

while IFS= read -r -d '' test_file; do
    bash "$test_file"
done < <(find content -type f -name 'test-*.sh' -print0 | sort -z)

while IFS= read -r -d '' patch_file; do
    git apply --numstat "$patch_file" >/dev/null
done < <(find content -type f -name '*.patch' -print0 | sort -z)

printf '%s\n' 'site end-to-end checks passed'
