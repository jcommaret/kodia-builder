#!/usr/bin/env bash
# shellcheck disable=SC1091

set -e

if [[ -z "${GH_TOKEN}" ]] && [[ -z "${GITHUB_TOKEN}" ]] && [[ -z "${GH_ENTERPRISE_TOKEN}" ]] && [[ -z "${GITHUB_ENTERPRISE_TOKEN}" ]]; then
  echo "Will not create release because no GITHUB_TOKEN defined"
  exit 1
fi

if [[ -z "${RELEASE_VERSION}" ]]; then
  echo "RELEASE_VERSION is not set"
  exit 1
fi

VOID_VERSION="${VOID_VERSION:-${RELEASE_VERSION}}"
if [[ -z "${RELEASE_TITLE}" ]]; then
  if [[ -n "${MS_TAG}" && -n "${VOID_VERSION}" ]]; then
    RELEASE_TITLE="${MS_TAG} - ${VOID_VERSION}"
  else
    RELEASE_TITLE="${VOID_VERSION:-${RELEASE_VERSION}}"
  fi
fi

if gh release view "${RELEASE_VERSION}" --repo "${ASSETS_REPOSITORY}" &>/dev/null; then
  echo "Release '${RELEASE_VERSION}' already exists on ${ASSETS_REPOSITORY}"
  exit 0
fi

echo "Creating release '${RELEASE_VERSION}' on ${ASSETS_REPOSITORY} (title: '${RELEASE_TITLE}')"

if [[ "${VSCODE_QUALITY}" == "insider" ]]; then
  NOTES="update vscode to [${MS_COMMIT}](https://github.com/microsoft/vscode/tree/${MS_COMMIT})"
  gh release create "${RELEASE_VERSION}" --repo "${ASSETS_REPOSITORY}" --title "${RELEASE_TITLE}" --notes "${NOTES}"
else
  gh release create "${RELEASE_VERSION}" --repo "${ASSETS_REPOSITORY}" --title "${RELEASE_TITLE}" --notes ""
fi
