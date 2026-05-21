#!/usr/bin/env bash
# shellcheck disable=SC2129
# Clone Void + checkout PR void-builder. Usage: ./ci_repo.sh [pr|void|all]

set -e

# Racine void-builder (ne pas recalculer après un cd vscode/ : dirname de ./ci_repo.sh = ".")
VB_REPO_ROOT="${VOID_BUILDER_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
export VOID_BUILDER_ROOT="${VB_REPO_ROOT}"

ci_repo_pr() {
  ci_git_safe_directory

  if [[ -n "${PULL_REQUEST_ID}" ]]; then
    local BRANCH_NAME
    BRANCH_NAME=$( git rev-parse --abbrev-ref HEAD )

    git config --global user.email "$( echo "${GITHUB_USERNAME}" | awk '{print tolower($0)}' )-ci@not-real.com"
    git config --global user.name "${GITHUB_USERNAME} CI"
    git fetch --unshallow
    git fetch origin "pull/${PULL_REQUEST_ID}/head"
    git checkout FETCH_HEAD
    git merge --no-edit "origin/${BRANCH_NAME}"
  fi
}

ci_repo_void() {
  echo "----------- ci_repo void -----------"
  echo "CI_BUILD=${CI_BUILD}"
  echo "GITHUB_REPOSITORY=${GITHUB_REPOSITORY}"
  echo "RELEASE_VERSION=${RELEASE_VERSION}"
  echo "VSCODE_LATEST=${VSCODE_LATEST}"
  echo "VSCODE_QUALITY=${VSCODE_QUALITY}"
  echo "SHOULD_DEPLOY=${SHOULD_DEPLOY}"
  echo "SHOULD_BUILD=${SHOULD_BUILD}"

  ci_git_safe_directory

  local VOID_REPO VOID_BRANCH
  VOID_REPO="${VOID_REPO:-${GH_REPO_PATH:-voideditor/void}}"

  if [[ -z "${VOID_BRANCH}" ]]; then
    VOID_BRANCH=$( git ls-remote --symref "https://github.com/${VOID_REPO}.git" HEAD 2>/dev/null | awk '/^ref:/ { sub("refs/heads/", "", $2); print $2; exit }' )
  fi
  VOID_BRANCH="${VOID_BRANCH:-master}"

  echo "Cloning void ${VOID_REPO} (${VOID_BRANCH})..."

  mkdir -p vscode
  cd vscode || { echo "'vscode' dir not found"; exit 1; }

  git init -q
  git remote add origin "https://github.com/${VOID_REPO}.git"

  if [[ -n "${VOID_COMMIT}" ]]; then
    echo "Using explicit commit ${VOID_COMMIT}"
    git fetch --depth 1 origin "${VOID_COMMIT}"
    git checkout "${VOID_COMMIT}"
  else
    git fetch --depth 1 origin "${VOID_BRANCH}"
    git checkout FETCH_HEAD
  fi

  MS_VERSION=$( jq -r '.version' "package.json" )
  MS_VERSION="${MS_VERSION%%-*}"
  MS_TAG="${MS_VERSION}"
  MS_COMMIT=$( git rev-parse HEAD )
  local pin_versions=false
  if [[ -n "${RELEASE_VERSION:-}" && -n "${VOID_VERSION:-}" ]]; then
    pin_versions=true
    echo "Keeping pinned versions RELEASE_VERSION=${RELEASE_VERSION} VOID_VERSION=${VOID_VERSION}"
  else
    VOID_VERSION=$( jq -r '.voidVersion // empty' "product.json" )
    [[ "${VOID_VERSION}" == "null" ]] && VOID_VERSION=""

    if [[ -n "${VOID_VERSION}" ]]; then
      RELEASE_VERSION="${MS_TAG}-${VOID_VERSION}"
      RELEASE_TITLE="${MS_TAG} - ${VOID_VERSION}"
    else
      RELEASE_VERSION="${MS_TAG}"
      RELEASE_TITLE="${MS_TAG}"
    fi
    [[ -z "${VOID_VERSION}" ]] && VOID_VERSION="${RELEASE_VERSION}"
  fi

  if [[ -n "${VOID_VERSION:-}" ]]; then
    # shellcheck source=scripts/lib/ci_lib.sh
    source "${VB_REPO_ROOT}/scripts/lib/ci_lib.sh"
    ci_apply_void_version
  fi

  echo "RELEASE_TITLE=\"${RELEASE_TITLE}\""
  echo "RELEASE_VERSION=\"${RELEASE_VERSION}\""
  echo "MS_COMMIT=\"${MS_COMMIT}\""
  echo "MS_VERSION=\"${MS_VERSION}\""
  echo "MS_TAG=\"${MS_TAG}\""

  cd ..

  if [[ "${GITHUB_ENV}" ]]; then
    echo "MS_TAG=${MS_TAG}" >> "${GITHUB_ENV}"
    echo "MS_COMMIT=${MS_COMMIT}" >> "${GITHUB_ENV}"
    if [[ "${pin_versions}" != "true" ]]; then
      echo "RELEASE_VERSION=${RELEASE_VERSION}" >> "${GITHUB_ENV}"
      echo "VOID_VERSION=${VOID_VERSION}" >> "${GITHUB_ENV}"
      {
        echo "RELEASE_TITLE<<GITHUB_RELEASE_TITLE"
        echo "${RELEASE_TITLE}"
        echo "GITHUB_RELEASE_TITLE"
      } >> "${GITHUB_ENV}"
    fi
  fi

  export MS_TAG MS_COMMIT RELEASE_VERSION RELEASE_TITLE VOID_VERSION
}

ci_git_safe_directory() {
  if [[ "${CI_BUILD}" != "no" ]]; then
    git config --global --add safe.directory "/__w/$( echo "${GITHUB_REPOSITORY}" | awk '{print tolower($0)}' )"
  fi
}

ci_repo_run() {
  local mode="${1:-all}"
  case "${mode}" in
    pr) ci_repo_pr ;;
    void) ci_repo_void ;;
    all) ci_repo_pr; ci_repo_void ;;
    *)
      echo "Usage: $0 [pr|void|all]" >&2
      return 1
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  ci_repo_run "${1:-all}"
else
  [[ $# -gt 0 ]] && ci_repo_run "$@"
fi
