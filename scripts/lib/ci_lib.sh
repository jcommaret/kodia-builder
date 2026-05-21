#!/usr/bin/env bash
# Bibliothèque CI (sourcée par ci_check.sh, ci_platform.sh). Ne pas exécuter directement.

ci_write_github_env() {
  if [[ ! "${GITHUB_ENV}" ]]; then
    return 0
  fi
  while [[ $# -gt 0 ]]; do
    echo "$1" >> "${GITHUB_ENV}"
    shift
  done
}

ci_git_safe_directory() {
  if [[ "${CI_BUILD}" != "no" ]]; then
    git config --global --add safe.directory "/__w/$( echo "${GITHUB_REPOSITORY}" | awk '{print tolower($0)}' )"
  fi
}

ci_check_cron_or_pr() {
  if [[ "${GITHUB_EVENT_NAME}" == "pull_request" ]]; then
    echo "It's a PR"
    export SHOULD_BUILD="yes"
    export SHOULD_DEPLOY="no"
  elif [[ "${GITHUB_EVENT_NAME}" == "push" ]]; then
    echo "It's a Push"
    export SHOULD_BUILD="yes"
    export SHOULD_DEPLOY="no"
  elif [[ "${GITHUB_EVENT_NAME}" == "workflow_dispatch" ]]; then
    echo "It's a Dispatch"
    export SHOULD_BUILD="yes"
    export SHOULD_DEPLOY="yes"
  else
    echo "It's a Cron"
    export SHOULD_BUILD="yes"
    export SHOULD_DEPLOY="yes"
  fi

  if [[ "${SHOULD_DEPLOY}" == "yes" ]]; then
    export INCREMENT_VERSION="yes"
  fi

  ci_write_github_env \
    "GITHUB_BRANCH=${GITHUB_BRANCH}" \
    "SHOULD_BUILD=${SHOULD_BUILD}" \
    "SHOULD_DEPLOY=${SHOULD_DEPLOY}" \
    "VSCODE_QUALITY=${VSCODE_QUALITY}" \
    "INCREMENT_VERSION=${INCREMENT_VERSION}"
}

ci_version_max() {
  printf '%s\n%s\n' "$1" "$2" | sort -V | tail -1
}

ci_bump_minor() {
  local version="${1}"
  local major minor

  if [[ ! "${version}" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    echo "Invalid semver for bump: ${version}" >&2
    return 1
  fi

  major="${BASH_REMATCH[1]}"
  minor="${BASH_REMATCH[2]}"
  minor=$((minor + 1))
  echo "${major}.${minor}.0"
}

ci_extract_void_version_from_tag() {
  local tag="${1}"
  local void_part=""

  if [[ -n "${MS_TAG}" && "${tag}" == "${MS_TAG}"-* ]]; then
    void_part="${tag#${MS_TAG}-}"
  elif [[ "${tag}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    void_part="${tag}"
  fi

  if [[ -n "${void_part}" && "${void_part}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "${void_part}"
  fi
}

ci_latest_void_from_releases() {
  if [[ -z "${GITHUB_TOKEN:-}" ]] && [[ -z "${GH_TOKEN:-}" ]]; then
    return 0
  fi

  local tags void_part
  tags=$( gh release list --repo "${ASSETS_REPOSITORY}" --limit 50 --json tagName --jq '.[].tagName' 2>/dev/null || true )

  if [[ -z "${tags}" ]]; then
    return 0
  fi

  while IFS= read -r tag; do
    void_part=$(ci_extract_void_version_from_tag "${tag}")
    if [[ -n "${void_part}" ]]; then
      echo "${void_part}"
    fi
  done <<< "${tags}" | sort -V | tail -1
}

ci_bump_version_write_env() {
  if [[ ! "${GITHUB_ENV}" ]]; then
    return 0
  fi

  echo "VOID_VERSION=${VOID_VERSION}" >> "${GITHUB_ENV}"
  echo "RELEASE_VERSION=${RELEASE_VERSION}" >> "${GITHUB_ENV}"
  {
    echo "RELEASE_TITLE<<GITHUB_RELEASE_TITLE"
    echo "${RELEASE_TITLE}"
    echo "GITHUB_RELEASE_TITLE"
  } >> "${GITHUB_ENV}"
}

ci_bump_version() {
  if [[ "${INCREMENT_VERSION}" != "yes" ]]; then
    echo "Version increment disabled (INCREMENT_VERSION != yes)"
    return 0
  fi

  if [[ -z "${MS_TAG}" ]]; then
    echo "MS_TAG is not set; cannot compute RELEASE_VERSION" >&2
    return 1
  fi

  if [[ -z "${VOID_VERSION}" ]]; then
    echo "voidVersion missing from void product.json; cannot increment" >&2
    return 1
  fi

  local latest_released base_version
  latest_released=$(ci_latest_void_from_releases || true)
  base_version="${VOID_VERSION}"

  if [[ -n "${latest_released}" ]]; then
    base_version=$(ci_version_max "${VOID_VERSION}" "${latest_released}")
    echo "Latest void version on ${ASSETS_REPOSITORY}: ${latest_released} (base for bump: ${base_version})"
  else
    echo "No prior void release found on ${ASSETS_REPOSITORY}; bumping from ${base_version}"
  fi

  VOID_VERSION=$(ci_bump_minor "${base_version}")

  if [[ -n "${MS_TAG}" ]]; then
    RELEASE_VERSION="${MS_TAG}-${VOID_VERSION}"
    RELEASE_TITLE="${MS_TAG} - ${VOID_VERSION}"
  else
    RELEASE_VERSION="${VOID_VERSION}"
    RELEASE_TITLE="${VOID_VERSION}"
  fi

  echo "Incremented voidVersion: ${base_version} -> ${VOID_VERSION}"
  echo "RELEASE_VERSION=${RELEASE_VERSION}"
  echo "RELEASE_TITLE=${RELEASE_TITLE}"

  if [[ -f vscode/product.json ]]; then
    local tmp
    tmp=$(mktemp)
    jq --arg v "${VOID_VERSION}" '.voidVersion = $v' vscode/product.json > "${tmp}"
    mv "${tmp}" vscode/product.json
    echo "Updated vscode/product.json voidVersion"
  fi

  ci_bump_version_write_env
  export VOID_VERSION RELEASE_VERSION RELEASE_TITLE
}

ci_install_gh() {
  set -ex

  local GH_ARCH="amd64"
  local api_url="https://api.github.com/repos/cli/cli/releases/latest"
  local -a curl_opts=(
    -sS
    --retry 5
    --retry-delay 10
    -H "Accept: application/vnd.github+json"
  )

  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    curl_opts+=( -H "Authorization: Bearer ${GITHUB_TOKEN}" )
  fi

  local TAG
  TAG="$( curl "${curl_opts[@]}" "$api_url" | jq --raw-output '.tag_name // empty' )"

  if [[ -z "${TAG}" || "${TAG}" == "null" ]]; then
    echo "Impossible d'obtenir cli/cli latest via l'API (rate limit ou erreur) ; repli sur une version pinnée." >&2
    TAG="v2.74.0"
  fi

  local VERSION="${TAG#v}"

  curl --retry 12 --retry-delay 120 -sSL -f \
    "https://github.com/cli/cli/releases/download/${TAG}/gh_${VERSION}_linux_${GH_ARCH}.tar.gz" \
    -o "gh_${VERSION}_linux_${GH_ARCH}.tar.gz"

  tar xf "gh_${VERSION}_linux_${GH_ARCH}.tar.gz"
  cp "gh_${VERSION}_linux_${GH_ARCH}/bin/gh" /usr/local/bin/
  gh --version
}

ci_check_tags() {
  if [[ -z "${GH_TOKEN}" ]] && [[ -z "${GITHUB_TOKEN}" ]] && [[ -z "${GH_ENTERPRISE_TOKEN}" ]] && [[ -z "${GITHUB_ENTERPRISE_TOKEN}" ]]; then
    echo "Will not build because no GITHUB_TOKEN defined"
    return 0
  fi

  GITHUB_TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-${GH_ENTERPRISE_TOKEN:-${GITHUB_ENTERPRISE_TOKEN}}}}"
  GH_HOST="${GH_HOST:-github.com}"

  echo "Always building from main branch"
  export SHOULD_BUILD="yes"
  export SHOULD_DEPLOY="yes"

  export SHOULD_BUILD_APPIMAGE="yes"
  export SHOULD_BUILD_DEB="yes"
  export SHOULD_BUILD_DMG="yes"
  export SHOULD_BUILD_EXE_SYS="yes"
  export SHOULD_BUILD_EXE_USR="yes"
  export SHOULD_BUILD_MSI="yes"
  export SHOULD_BUILD_MSI_NOUP="yes"
  export SHOULD_BUILD_REH="yes"
  export SHOULD_BUILD_REH_WEB="yes"
  export SHOULD_BUILD_RPM="yes"
  export SHOULD_BUILD_TAR="yes"
  export SHOULD_BUILD_ZIP="yes"

  if [[ "${IS_SPEARHEAD}" == "yes" ]]; then
    export SHOULD_BUILD_SRC="no"
  elif [[ "${OS_NAME}" == "linux" ]]; then
    if [[ "${VSCODE_ARCH}" == "ppc64le" || "${VSCODE_ARCH}" == "riscv64" || "${VSCODE_ARCH}" == "loong64" ]]; then
      export SHOULD_BUILD_DEB="no"
      export SHOULD_BUILD_RPM="no"
    fi
    if [[ "${VSCODE_ARCH}" != "x64" || "${DISABLE_APPIMAGE}" == "yes" ]]; then
      export SHOULD_BUILD_APPIMAGE="no"
    fi
  elif [[ "${OS_NAME}" == "windows" ]]; then
    if [[ "${VSCODE_ARCH}" == "arm64" ]]; then
      export SHOULD_BUILD_REH="no"
      export SHOULD_BUILD_REH_WEB="no"
    fi
    if [[ "${DISABLE_MSI}" == "yes" ]]; then
      export SHOULD_BUILD_MSI="no"
      export SHOULD_BUILD_MSI_NOUP="no"
    fi
  fi

  ci_write_github_env \
    "SHOULD_BUILD=${SHOULD_BUILD}" \
    "SHOULD_DEPLOY=${SHOULD_DEPLOY}" \
    "SHOULD_BUILD_APPIMAGE=${SHOULD_BUILD_APPIMAGE}" \
    "SHOULD_BUILD_DEB=${SHOULD_BUILD_DEB}" \
    "SHOULD_BUILD_DMG=${SHOULD_BUILD_DMG}" \
    "SHOULD_BUILD_EXE_SYS=${SHOULD_BUILD_EXE_SYS}" \
    "SHOULD_BUILD_EXE_USR=${SHOULD_BUILD_EXE_USR}" \
    "SHOULD_BUILD_MSI=${SHOULD_BUILD_MSI}" \
    "SHOULD_BUILD_MSI_NOUP=${SHOULD_BUILD_MSI_NOUP}" \
    "SHOULD_BUILD_REH=${SHOULD_BUILD_REH}" \
    "SHOULD_BUILD_REH_WEB=${SHOULD_BUILD_REH_WEB}" \
    "SHOULD_BUILD_RPM=${SHOULD_BUILD_RPM}" \
    "SHOULD_BUILD_TAR=${SHOULD_BUILD_TAR}" \
    "SHOULD_BUILD_ZIP=${SHOULD_BUILD_ZIP}" \
    "SHOULD_BUILD_SRC=${SHOULD_BUILD_SRC}"
}
