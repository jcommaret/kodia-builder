#!/usr/bin/env bash
# shellcheck disable=SC2164
# Met à jour package-lock.json après policies.patch (hors patch : lock trop volatile).

set -e

[[ -f package.json ]] || exit 0

if ! grep -q '@vscodium/policy-watcher' package.json; then
  exit 0
fi

if grep -q '@vscodium/policy-watcher' package-lock.json 2>/dev/null; then
  echo "package-lock.json already references @vscodium/policy-watcher"
  exit 0
fi

echo "Syncing package-lock.json for @vscodium/policy-watcher..."

npm uninstall @vscode/policy-watcher --package-lock-only --no-audit --no-fund 2>/dev/null || true
npm install --package-lock-only --no-audit --no-fund "@vscodium/policy-watcher@^1.3.0-2503300035"
