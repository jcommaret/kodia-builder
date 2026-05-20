#!/usr/bin/env bash
# shellcheck disable=SC1091

set -ex

if [[ -z "${GH_TOKEN}" ]] && [[ -z "${GITHUB_TOKEN}" ]] && [[ -z "${GH_ENTERPRISE_TOKEN}" ]] && [[ -z "${GITHUB_ENTERPRISE_TOKEN}" ]]; then
  echo "Will not release because no GITHUB_TOKEN defined"
  exit
fi

REPOSITORY_OWNER="${ASSETS_REPOSITORY/\/*/}"
REPOSITORY_NAME="${ASSETS_REPOSITORY/*\//}"

npm install -g github-release-cli

if [[ "${UPLOAD_TO_LATEST_TAG}" == "yes" ]]; then
  echo "Resolving latest release on ${ASSETS_REPOSITORY}..."
  RELEASE_VERSION=$( gh release list --repo "${ASSETS_REPOSITORY}" --limit 1 --json tagName --jq '.[0].tagName // empty' )

  if [[ -z "${RELEASE_VERSION}" ]]; then
    echo "No GitHub release found on ${ASSETS_REPOSITORY}; skipping upload."
    exit 0
  fi

  echo "Uploading assets to latest release tag: ${RELEASE_VERSION}"
else
  VOID_VERSION="${VOID_VERSION:-${RELEASE_VERSION}}"
  if [[ -z "${RELEASE_TITLE}" ]]; then
    if [[ -n "${MS_TAG}" && -n "${VOID_VERSION}" ]]; then
      RELEASE_TITLE="${MS_TAG} - ${VOID_VERSION}"
    else
      RELEASE_TITLE="${VOID_VERSION:-${RELEASE_VERSION}}"
    fi
  fi
fi

if [[ "${UPLOAD_TO_LATEST_TAG}" != "yes" ]] && [[ $( gh release view "${RELEASE_VERSION}" --repo "${ASSETS_REPOSITORY}" 2>&1 ) =~ "release not found" ]]; then
  echo "Creating release '${RELEASE_VERSION}' (title: '${RELEASE_TITLE}')"

  if [[ "${VSCODE_QUALITY}" == "insider" ]]; then
    NOTES="update vscode to [${MS_COMMIT}](https://github.com/microsoft/vscode/tree/${MS_COMMIT})"

    gh release create "${RELEASE_VERSION}" --repo "${ASSETS_REPOSITORY}" --title "${RELEASE_TITLE}" --notes "${NOTES}"
  else
    gh release create "${RELEASE_VERSION}" --repo "${ASSETS_REPOSITORY}" --title "${RELEASE_TITLE}" --generate-notes

    . ./utils.sh

    RELEASE_NOTES=$( gh release view "${RELEASE_VERSION}" --repo "${ASSETS_REPOSITORY}" --json "body" --jq ".body" )

    replace "s|MS_TAG_SHORT|$( echo "${MS_TAG//./_}" | cut -d'_' -f 1,2 )|" release_notes.txt
    replace "s|MS_TAG|${MS_TAG}|" release_notes.txt
    replace "s|RELEASE_VERSION|${RELEASE_VERSION}|g" release_notes.txt
    replace "s|VOID_VERSION|${VOID_VERSION}|g" release_notes.txt
    replace "s|RELEASE_NOTES|${RELEASE_NOTES//$'\n'/\\n}|" release_notes.txt

    gh release edit "${RELEASE_VERSION}" --repo "${ASSETS_REPOSITORY}" --notes-file release_notes.txt
  fi
fi

cd assets

set +e

for FILE in *; do
  if [[ -f "${FILE}" ]] && [[ "${FILE}" != *.sha1 ]] && [[ "${FILE}" != *.sha256 ]]; then
    echo "::group::Uploading '${FILE}' at $( date "+%T" )"
    gh release upload --repo "${ASSETS_REPOSITORY}" "${RELEASE_VERSION}" "${FILE}" "${FILE}.sha1" "${FILE}.sha256"

    EXIT_STATUS=$?
    echo "exit: ${EXIT_STATUS}"

    if (( "${EXIT_STATUS}" )); then
      for (( i=0; i<10; i++ )); do
        github-release delete --owner "${REPOSITORY_OWNER}" --repo "${REPOSITORY_NAME}" --tag "${RELEASE_VERSION}" "${FILE}" "${FILE}.sha1" "${FILE}.sha256"

        sleep $(( 15 * (i + 1)))

        echo "RE-Uploading '${FILE}' at $( date "+%T" )"
        gh release upload --repo "${ASSETS_REPOSITORY}" "${RELEASE_VERSION}" "${FILE}" "${FILE}.sha1" "${FILE}.sha256"

        EXIT_STATUS=$?
        echo "exit: ${EXIT_STATUS}"

        if ! (( "${EXIT_STATUS}" )); then
          break
        fi
      done
      echo "exit: ${EXIT_STATUS}"

      if (( "${EXIT_STATUS}" )); then
        echo "'${FILE}' hasn't been uploaded!"

        github-release delete --owner "${REPOSITORY_OWNER}" --repo "${REPOSITORY_NAME}" --tag "${RELEASE_VERSION}" "${FILE}" "${FILE}.sha1" "${FILE}.sha256"

        exit 1
      fi
    fi

    echo "::endgroup::"
  fi
done

cd ..
