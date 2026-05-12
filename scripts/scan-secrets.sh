#!/usr/bin/env bash
set -euo pipefail

root="${1:-.}"

patterns='(AKIA[0-9A-Z]{16}|ASIA[0-9A-Z]{16}|sk-[A-Za-z0-9_-]{20,}|sk-ant-[A-Za-z0-9_-]{20,}|ghp_[A-Za-z0-9_]{20,}|ghs_[A-Za-z0-9_]{20,}|github_pat_[A-Za-z0-9_]{20,}|xox[baprs]-[A-Za-z0-9-]{20,}|eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{10,}|-----BEGIN (RSA |EC |OPENSSH |)PRIVATE KEY-----)'

# Optional project-specific deny-list. Example:
#   PRIVATE_PATTERNS='(customer-name|private-domain\.com|person@example\.com)' bash scripts/scan-secrets.sh .
private_patterns="${PRIVATE_PATTERNS:-}"
combined_patterns="$patterns"
if [ -n "$private_patterns" ]; then
  combined_patterns="$combined_patterns|$private_patterns"
fi

if command -v rg >/dev/null 2>&1; then
  set +e
  rg -n -i --hidden \
    --glob '!.git/**' \
    --glob '!node_modules/**' \
    --glob '!coverage/**' \
    --glob '!dist/**' \
    "$combined_patterns" "$root"
  matches_found=$?
  set -e
else
  set +e
  grep -RInE "$combined_patterns" "$root" \
    --exclude-dir=.git \
    --exclude-dir=node_modules \
    --exclude-dir=coverage \
    --exclude-dir=dist
  matches_found=$?
  set -e
fi

if [ "$matches_found" -eq 0 ]; then
  echo "Potential secret or private identifier patterns found. Review every hit."
  exit 1
fi

if [ "$matches_found" -gt 1 ]; then
  echo "Secret scan command failed."
  exit "$matches_found"
fi

echo "No high-confidence secret or private identifier patterns found."
