#!/usr/bin/env bash
# shellcheck disable=SC1091

set -ex

if [[ "${CI_BUILD}" == "no" ]]; then
  exit 1
fi

VOID_BUILDER_ROOT="${VOID_BUILDER_ROOT:-${GITHUB_WORKSPACE:-}}"
if [[ -z "${VOID_BUILDER_ROOT}" ]]; then
  VOID_BUILDER_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi
export VOID_BUILDER_ROOT

tar -xzf ./vscode.tar.gz

cd vscode || { echo "'vscode' dir not found"; exit 1; }

# shellcheck source=scripts/lib/ci_lib.sh
source "${VOID_BUILDER_ROOT}/scripts/lib/ci_lib.sh"
ci_apply_void_version

for i in {1..5}; do # try 5 times
  npm ci && break
  if [[ $i -eq 3 ]]; then
    echo "Npm install failed too many times" >&2
    exit 1
  fi
  echo "Npm install failed $i, trying again..."
done

node --experimental-strip-types build/azure-pipelines/distro/mixin-npm.ts

. "${VOID_BUILDER_ROOT}/build/windows/rtf/make.sh"

# rcedit (x64) cannot patch ARM64 PE binaries when cross-compiling on windows-2022 x64.
if [[ "${VSCODE_ARCH}" == "arm64" ]] && [[ -f build/gulpfile.vscode.ts ]]; then
  node --input-type=commonjs - << 'NODEEOF'
const {readFileSync, writeFileSync} = require('fs');
const f = 'build/gulpfile.vscode.ts';
let c = readFileSync(f, 'utf8');
const needle = "\t\tawait rcedit(path.join(cwd, dep), {";
const patch = "\t\ttry {\n\t\t\tawait rcedit(path.join(cwd, dep), {";
if (c.includes(needle) && !c.includes('rcedit skipped for')) {
  c = c.replace(needle, patch);
  c = c.replace(
    /\t\t\}\);\n\t\}\);\n\n\t\tawait Promise\.all\(patchPromises\);/,
    "\t\t});\n\t\t} catch (err) {\n\t\t\tconsole.warn(`[patchWin32Dependencies] rcedit skipped for ${dep}: ${err?.message ?? err}`);\n\t\t}\n\t});\n\n\t\tawait Promise.all(patchPromises);"
  );
  writeFileSync(f, c);
  console.log('patched build/gulpfile.vscode.ts: rcedit failures are non-fatal on arm64');
}
NODEEOF
fi

npm run gulp "vscode-win32-${VSCODE_ARCH}-min-ci"

. "${VOID_BUILDER_ROOT}/scripts/build_cli.sh"

if [[ "${VSCODE_ARCH}" == "x64" ]]; then
  if [[ "${SHOULD_BUILD_REH}" != "no" ]]; then
    echo "Building REH"
    npm run gulp minify-vscode-reh
    npm run gulp "vscode-reh-win32-${VSCODE_ARCH}-min-ci"
  fi

  if [[ "${SHOULD_BUILD_REH_WEB}" != "no" ]]; then
    echo "Building REH-web"
    npm run gulp minify-vscode-reh-web
    npm run gulp "vscode-reh-web-win32-${VSCODE_ARCH}-min-ci"
  fi
fi

cd ..
