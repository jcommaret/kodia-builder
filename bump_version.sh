#!/usr/bin/env bash
# shellcheck disable=SC2129

set -e

# Incrémente voidVersion (semver mineur, patch remis à 0) avant un déploiement CI.
# S'appuie sur le max(void dans le clone, dernière release ASSETS_REPOSITORY) puis +1 mineur.

version_max() {
  printf '%s\n%s\n' "$1" "$2" | sort -V | tail -1
}

bump_minor() {
  local version="${1}"
  local major minor

  if [[ ! "${version}" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    echo "Invalid semver for bump: ${version}" >&2
    exit 1
  fi

  major="${BASH_REMATCH[1]}"
  minor="${BASH_REMATCH[2]}"
  minor=$((minor + 1))
  echo "${major}.${minor}.0"
}

extract_void_version_from_tag() {
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

latest_void_from_releases() {
  if [[ -z "${GITHUB_TOKEN:-}" ]] && [[ -z "${GH_TOKEN:-}" ]]; then
    return 0
  fi

  local tags void_part
  tags=$( gh release list --repo "${ASSETS_REPOSITORY}" --limit 50 --json tagName --jq '.[].tagName' 2>/dev/null || true )

  if [[ -z "${tags}" ]]; then
    return 0
  fi

  while IFS= read -r tag; do
    void_part=$(extract_void_version_from_tag "${tag}")
    if [[ -n "${void_part}" ]]; then
      echo "${void_part}"
    fi
  done <<< "${tags}" | sort -V | tail -1
}

write_github_env() {
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

if [[ "${INCREMENT_VERSION}" != "yes" ]]; then
  echo "Version increment disabled (INCREMENT_VERSION != yes)"
  exit 0
fi

if [[ -z "${MS_TAG}" ]]; then
  echo "MS_TAG is not set; cannot compute RELEASE_VERSION"
  exit 1
fi

if [[ -z "${VOID_VERSION}" ]]; then
  echo "voidVersion missing from void product.json; cannot increment"
  exit 1
fi

latest_released=$(latest_void_from_releases || true)
base_version="${VOID_VERSION}"

if [[ -n "${latest_released}" ]]; then
  base_version=$(version_max "${VOID_VERSION}" "${latest_released}")
  echo "Latest void version on ${ASSETS_REPOSITORY}: ${latest_released} (base for bump: ${base_version})"
else
  echo "No prior void release found on ${ASSETS_REPOSITORY}; bumping from ${base_version}"
fi

VOID_VERSION=$(bump_minor "${base_version}")

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
  tmp=$(mktemp)
  jq --arg v "${VOID_VERSION}" '.voidVersion = $v' vscode/product.json > "${tmp}"
  mv "${tmp}" vscode/product.json
  echo "Updated vscode/product.json voidVersion"
fi

write_github_env

export VOID_VERSION RELEASE_VERSION RELEASE_TITLE
