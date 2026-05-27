#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2016

set -ex

# list of urls to match:
# - mobile.events.data.microsoft.com
# - vortex.data.microsoft.com

SEARCH="\.data\.microsoft\.com"
REPLACEMENT="s|//[^/]+\.data\.microsoft\.com|//0\.0\.0\.0|g"

echo "----------- undo_telemetry -----------"
if [[ -z "${VOID_BUILDER_ROOT:-}" ]]; then
  VOID_BUILDER_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  export VOID_BUILDER_ROOT
fi
# shellcheck source=lib/utils.sh
. "${VOID_BUILDER_ROOT}/scripts/lib/utils.sh"


if is_gnu_sed; then
  replace_with_debug () {
    echo "found: ${2}"
    sed -i -E "${1}" "${2}"
  }
else
  replace_with_debug () {
    echo "found: ${2}"
    sed -i '' -E "${1}" "${2}"
  }
fi
export -f replace_with_debug

d1=$( date +%s )

# Exclude compiled output dirs: modifying pre-compiled JS breaks source map integrity checks in the NLS build step.
RG_EXCLUDE=(--glob '!out/**' --glob '!out-build/**' --glob '!out-vscode/**' --glob '!out-vscode-min/**' --glob '!.build/**' --glob '!node_modules/**')
GREP_EXCLUDE=(--exclude-dir=.git --exclude-dir=out --exclude-dir=out-build --exclude-dir=out-vscode --exclude-dir=out-vscode-min --exclude-dir=.build --exclude-dir=node_modules)

if [[ "${OS_NAME}" == "linux" ]]; then
  if [[ ${VSCODE_ARCH} == "x64" ]]; then
    ./node_modules/@vscode/ripgrep/bin/rg --no-ignore "${RG_EXCLUDE[@]}" -l "${SEARCH}" . | xargs -I {} bash -c 'replace_with_debug "${1}" "{}"' _ "${REPLACEMENT}"
  else
    grep -rl "${GREP_EXCLUDE[@]}" -E "${SEARCH}" . | xargs -I {} bash -c 'replace_with_debug "${1}" "{}"' _ "${REPLACEMENT}"
  fi
elif [[ "${OS_NAME}" == "osx" ]]; then
  ./node_modules/@vscode/ripgrep/bin/rg --no-ignore "${RG_EXCLUDE[@]}" -l "${SEARCH}" . | xargs -I {} bash -c 'replace_with_debug "${1}" "{}"' _ "${REPLACEMENT}"
else
  ./node_modules/@vscode/ripgrep/bin/rg --no-ignore "${RG_EXCLUDE[@]}" -l "${SEARCH}" . | xargs -I {} bash -c 'replace_with_debug "${1}" "{}"' _ "${REPLACEMENT}"
fi

d2=$( date +%s )

echo "undo_telemetry: $((d2 - d1))s"
