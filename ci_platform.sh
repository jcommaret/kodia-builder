#!/usr/bin/env bash
# shellcheck disable=SC1091
# Préparation des jobs plateforme : gh CLI + flags de build (ex-install_gh + check_tags).

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/ci_lib.sh
source "${REPO_ROOT}/scripts/lib/ci_lib.sh"

if [[ "${SKIP_GH_INSTALL}" != "yes" ]]; then
  ci_install_gh
fi
ci_check_tags
