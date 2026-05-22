#!/usr/bin/env bash
# shellcheck disable=SC1091
# Crée et/ou publie les assets sur la release GitHub ASSETS_REPOSITORY (tag RELEASE_VERSION).

set -e

setup_github_token() {
  if [[ -n "${STRONGER_GITHUB_TOKEN}" ]]; then
    export GITHUB_TOKEN="${STRONGER_GITHUB_TOKEN}"
    export GH_TOKEN="${STRONGER_GITHUB_TOKEN}"
  fi

  GITHUB_TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-${GH_ENTERPRISE_TOKEN:-${GITHUB_ENTERPRISE_TOKEN}}}}"

  if [[ -z "${GITHUB_TOKEN}" ]]; then
    echo "No GITHUB_TOKEN defined (set STRONGER_GITHUB_TOKEN or GITHUB_TOKEN)" >&2
    return 1
  fi

  export GITHUB_TOKEN="${GITHUB_TOKEN}"
  export GH_TOKEN="${GITHUB_TOKEN}"
}

release_ensure_exists() {
  setup_github_token || return 1

  if [[ -z "${RELEASE_VERSION}" ]]; then
    echo "RELEASE_VERSION is not set" >&2
    return 1
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
    return 0
  fi

  echo "Creating release '${RELEASE_VERSION}' on ${ASSETS_REPOSITORY} (title: '${RELEASE_TITLE}')"

  if [[ "${VSCODE_QUALITY}" == "insider" ]]; then
    NOTES="update vscode to [${MS_COMMIT}](https://github.com/microsoft/vscode/tree/${MS_COMMIT})"
    gh release create "${RELEASE_VERSION}" --repo "${ASSETS_REPOSITORY}" --title "${RELEASE_TITLE}" --notes "${NOTES}"
  else
    gh release create "${RELEASE_VERSION}" --repo "${ASSETS_REPOSITORY}" --title "${RELEASE_TITLE}" --notes ""
  fi
}

release_upload_assets() {
  set -x
  if ! setup_github_token; then
    echo "ERROR: No GITHUB_TOKEN / STRONGER_GITHUB_TOKEN — cannot upload to ${ASSETS_REPOSITORY}" >&2
    echo "Configure secret STRONGER_GITHUB_TOKEN (PAT avec scope repo sur ${ASSETS_REPOSITORY})." >&2
    exit 1
  fi

  if [[ -z "${RELEASE_VERSION}" ]]; then
    echo "RELEASE_VERSION is not set; cannot upload to ${ASSETS_REPOSITORY}"
    exit 1
  fi

  if [[ ! -d assets ]] || [[ -z "$(find assets -maxdepth 1 -type f ! -name '*.sha1' ! -name '*.sha256' 2>/dev/null | head -1)" ]]; then
    echo "ERROR: assets/ is empty or missing — nothing to upload" >&2
    ls -la assets 2>/dev/null || true
    exit 1
  fi

  echo "Uploading assets to ${ASSETS_REPOSITORY} release tag: ${RELEASE_VERSION}"
  echo "assets/:"
  ls -la assets/

  release_ensure_exists || exit 1

  REPOSITORY_OWNER="${ASSETS_REPOSITORY/\/*/}"
  REPOSITORY_NAME="${ASSETS_REPOSITORY/*\//}"

  if command -v github-release &>/dev/null; then
    :
  else
    npm install -g github-release-cli || echo "github-release-cli install failed; retries may be limited" >&2
  fi

  cd assets

  set +e
  local uploaded=0

  for FILE in *; do
    if [[ -f "${FILE}" ]] && [[ "${FILE}" != *.sha1 ]] && [[ "${FILE}" != *.sha256 ]]; then
      echo "::group::Uploading '${FILE}' at $( date "+%T" )"
      local -a UPLOAD_FILES=("${FILE}")
      [[ -f "${FILE}.sha1" ]] && UPLOAD_FILES+=("${FILE}.sha1")
      [[ -f "${FILE}.sha256" ]] && UPLOAD_FILES+=("${FILE}.sha256")
      gh release upload --repo "${ASSETS_REPOSITORY}" "${RELEASE_VERSION}" "${UPLOAD_FILES[@]}"

      EXIT_STATUS=$?
      echo "exit: ${EXIT_STATUS}"

      if (( EXIT_STATUS )); then
        for (( i=0; i<10; i++ )); do
          if command -v github-release &>/dev/null; then
            github-release delete --owner "${REPOSITORY_OWNER}" --repo "${REPOSITORY_NAME}" --tag "${RELEASE_VERSION}" "${UPLOAD_FILES[@]}" 2>/dev/null || true
          fi

          sleep $(( 15 * (i + 1)))

          echo "RE-Uploading '${FILE}' at $( date "+%T" )"
          gh release upload --repo "${ASSETS_REPOSITORY}" "${RELEASE_VERSION}" "${UPLOAD_FILES[@]}"

          EXIT_STATUS=$?
          echo "exit: ${EXIT_STATUS}"

          if ! (( EXIT_STATUS )); then
            break
          fi
        done
        echo "exit: ${EXIT_STATUS}"

        if (( EXIT_STATUS )); then
          echo "'${FILE}' hasn't been uploaded!"
          if command -v github-release &>/dev/null; then
            github-release delete --owner "${REPOSITORY_OWNER}" --repo "${REPOSITORY_NAME}" --tag "${RELEASE_VERSION}" "${UPLOAD_FILES[@]}" 2>/dev/null || true
          fi
          exit 1
        fi
      fi

      uploaded=$((uploaded + 1))
      echo "::endgroup::"
    fi
  done

  cd ..

  if (( uploaded == 0 )); then
    echo "ERROR: No release assets uploaded" >&2
    exit 1
  fi

  echo "Uploaded ${uploaded} asset(s) to ${ASSETS_REPOSITORY}@${RELEASE_VERSION}"
}

case "${1:-}" in
  --create-only)
    release_ensure_exists
    ;;
  --upload-only|"")
    release_upload_assets
    ;;
  *)
    echo "Usage: $0 [--create-only | --upload-only]" >&2
    exit 1
    ;;
esac
