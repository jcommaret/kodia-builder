#!/usr/bin/env bash

# Racine du dépôt void-builder (scripts/lib → ../..)
if [[ -z "${VOID_BUILDER_ROOT:-}" ]]; then
  VOID_BUILDER_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
  export VOID_BUILDER_ROOT
fi

APP_NAME="${APP_NAME:-Void}"
APP_NAME_LC="$( echo "${APP_NAME}" | awk '{print tolower($0)}' )"
BINARY_NAME="${BINARY_NAME:-void}"
GH_REPO_PATH="${GH_REPO_PATH:-voideditor/void}"
ORG_NAME="${ORG_NAME:-voideditor}"

echo "---------- utils.sh -----------"
echo "APP_NAME=\"${APP_NAME}\""
echo "APP_NAME_LC=\"${APP_NAME_LC}\""
echo "BINARY_NAME=\"${BINARY_NAME}\""
echo "GH_REPO_PATH=\"${GH_REPO_PATH}\""
echo "ORG_NAME=\"${ORG_NAME}\""

# All common functions can be added to this file

apply_patch() {
  if [[ -z "$2" ]]; then
    echo applying patch: "$1";
  fi
  # grep '^+++' "$1"  | sed -e 's#+++ [ab]/#./vscode/#' | while read line; do shasum -a 256 "${line}"; done

  cp $1{,.bak}

  replace "s|!!APP_NAME!!|${APP_NAME}|g" "$1"
  replace "s|!!APP_NAME_LC!!|${APP_NAME_LC}|g" "$1"
  replace "s|!!BINARY_NAME!!|${BINARY_NAME}|g" "$1"
  replace "s|!!GH_REPO_PATH!!|${GH_REPO_PATH}|g" "$1"
  replace "s|!!ORG_NAME!!|${ORG_NAME}|g" "$1"
  replace "s|!!RELEASE_VERSION!!|${RELEASE_VERSION}|g" "$1"

  if ! git apply --ignore-whitespace "$1"; then
    echo failed to apply patch "$1" >&2
    exit 1
  fi

  mv -f $1{.bak,}
}

exists() { type -t "$1" &> /dev/null; }

is_gnu_sed() {
  sed --version &> /dev/null
}

replace() {
  if is_gnu_sed; then
    sed -i -E "${1}" "${2}"
  else
    sed -i '' -E "${1}" "${2}"
  fi
}

if ! exists gsed; then
  if is_gnu_sed; then
    function gsed() {
      sed -i -E "$@"
    }
  else
    function gsed() {
      sed -i '' -E "$@"
    }
  fi
fi

ensure_build_sourceversion() {
  if [[ -n "${BUILD_SOURCEVERSION}" ]]; then
    export BUILD_SOURCEVERSION
    return 0
  fi

  echo "Computing BUILD_SOURCEVERSION..."

  if [[ -d "./vscode" ]]; then
    local CURRENT_DIR
    CURRENT_DIR=$(pwd)
    cd ./vscode
    BUILD_SOURCEVERSION=$(git rev-parse HEAD)
    cd "${CURRENT_DIR}"
  else
    if ! command -v checksum &>/dev/null; then
      npm install -g checksum
    fi
    BUILD_SOURCEVERSION=$( echo "${RELEASE_VERSION/-*/}" | checksum )
  fi

  echo "BUILD_SOURCEVERSION=\"${BUILD_SOURCEVERSION}\""

  if [[ "${GITHUB_ENV}" ]]; then
    echo "BUILD_SOURCEVERSION=${BUILD_SOURCEVERSION}" >> "${GITHUB_ENV}"
  fi

  export BUILD_SOURCEVERSION
}
