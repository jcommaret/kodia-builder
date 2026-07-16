#!/usr/bin/env bash
# shellcheck disable=SC1091
# Point d'entrée unique du job CI « check » : politique, version, release, flags.

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/ci_lib.sh
source "${REPO_ROOT}/scripts/lib/ci_lib.sh"

echo "=== CI check ==="

ci_check_cron_or_pr

if [[ "${INCREMENT_VERSION}" == "yes" && "${SKIP_VERSION_BUMP}" != "yes" ]]; then
  ci_bump_version
fi

if [[ "${SHOULD_BUILD}" == "yes" && "${SHOULD_DEPLOY}" == "yes" ]]; then
  ci_install_gh
  STRONGER_GITHUB_TOKEN="${STRONGER_GITHUB_TOKEN}" GITHUB_TOKEN="${GITHUB_TOKEN}" ./release.sh --create-only
fi

ci_check_tags

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "MS_COMMIT=${MS_COMMIT}"
    echo "MS_TAG=${MS_TAG}"
    echo "RELEASE_VERSION=${RELEASE_VERSION}"
    echo "VOID_VERSION=${VOID_VERSION}"
    echo "SHOULD_BUILD=${SHOULD_BUILD}"
    echo "SHOULD_DEPLOY=${SHOULD_DEPLOY}"
  } >> "${GITHUB_OUTPUT}"
fi

echo "=== CI check done ==="
echo "RELEASE_VERSION=${RELEASE_VERSION} VOID_VERSION=${VOID_VERSION}"
