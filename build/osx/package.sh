#!/usr/bin/env bash
# shellcheck disable=SC1091
# Packaging macOS à partir de l'artefact du job compile (vscode.tar.gz), comme build/linux/package_bin.sh et
# build/windows/package.sh : les sources sont déjà compilées et minifiées une seule fois sur Linux, il ne reste ici
# qu'à installer les modules natifs pour l'arch visée, assembler l'app et construire le CLI.
# Les outils de compilation (tsgo, esbuild) ne tournent donc plus ici : en x64 sur un runner arm64, ils tournaient
# sous Rosetta et le job durait trois fois plus longtemps que l'arm64.

set -ex

if [[ "${CI_BUILD}" == "no" ]]; then
  exit 1
fi

VOID_BUILDER_ROOT="${VOID_BUILDER_ROOT:-${GITHUB_WORKSPACE:-}}"
if [[ -z "${VOID_BUILDER_ROOT}" ]]; then
  VOID_BUILDER_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi
export VOID_BUILDER_ROOT

# Le workflow extrait déjà l'artefact pour calculer la clé du cache des node_modules.
[[ -d vscode ]] || tar -xzf ./vscode.tar.gz

cd vscode || { echo "'vscode' dir not found"; exit 1; }

# shellcheck source=scripts/lib/ci_lib.sh
source "${VOID_BUILDER_ROOT}/scripts/lib/ci_lib.sh"
ci_apply_void_version

# shellcheck source=scripts/lib/node_modules_cache.sh
. "${VOID_BUILDER_ROOT}/scripts/lib/node_modules_cache.sh"

if nm_cache_restored; then
  echo "node_modules restored from the cache: skipping npm ci"
else
  # Comme product-build-darwin-node-modules.yml de VS Code : Electron est téléchargé par le packaging, pas par npm ;
  # kerberos_use_rtld=false évite que le module Kerberos passe par dlopen sur macOS.
  export ELECTRON_SKIP_BINARY_DOWNLOAD=1
  export PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1
  export GYP_DEFINES="kerberos_use_rtld=false"

  clang++ --version

  for i in {1..5}; do # try 5 times
    CXX=clang++ npm ci && break
    if [[ $i -eq 3 ]]; then
      echo "Npm install failed too many times" >&2
      exit 1
    fi
    echo "Npm install failed $i, trying again..."
  done

  node --experimental-strip-types build/azure-pipelines/distro/mixin-npm.ts

  nm_cache_archive
fi

npm run gulp "vscode-darwin-${VSCODE_ARCH}-min-ci"

find "../VSCode-darwin-${VSCODE_ARCH}" -print0 | xargs -0 touch -c

. "${VOID_BUILDER_ROOT}/scripts/build_cli.sh"

cd ..
