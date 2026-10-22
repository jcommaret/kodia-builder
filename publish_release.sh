#!/usr/bin/env bash
# Last step of a release, once every platform uploaded its files to the draft release (release.sh) and prepared its
# update manifests (update_version.sh with MANIFESTS_DIR): publishes the release, then commits the manifests to the
# versions repo. GitHub's "Latest" and the app's updates then appear together, and a manifest never points to the
# files of a draft, which can't be downloaded.

set -e

if [[ -n "${STRONGER_GITHUB_TOKEN}" ]]; then
  export GITHUB_TOKEN="${STRONGER_GITHUB_TOKEN}"
fi
export GH_TOKEN="${GITHUB_TOKEN}"
GH_HOST="${GH_HOST:-github.com}"

for var in GITHUB_TOKEN GITHUB_USERNAME RELEASE_VERSION ASSETS_REPOSITORY VERSIONS_REPOSITORY MANIFESTS_DIR; do
  if [[ -z "${!var}" ]]; then
    echo "${var} is not set" >&2
    exit 1
  fi
done

if [[ -z "$( find "${MANIFESTS_DIR}" -name latest.json 2>/dev/null )" ]]; then
  echo "No manifests in ${MANIFESTS_DIR}: the platform jobs prepared none, so the release stays a draft" >&2
  exit 1
fi

echo "Publishing release '${RELEASE_VERSION}' on ${ASSETS_REPOSITORY}"
gh release edit "${RELEASE_VERSION}" --repo "${ASSETS_REPOSITORY}" --draft=false --latest

REPOSITORY_NAME="${VERSIONS_REPOSITORY/*\//}"
echo "Cloning repository: ${VERSIONS_REPOSITORY}"
GIT_LFS_SKIP_SMUDGE=1 git clone "https://${GITHUB_USERNAME}:${GITHUB_TOKEN}@${GH_HOST}/${VERSIONS_REPOSITORY}.git" "${REPOSITORY_NAME}"

cp -R "${MANIFESTS_DIR}/." "${REPOSITORY_NAME}/"
cd "${REPOSITORY_NAME}"
git config user.email "$( echo "${GITHUB_USERNAME}" | awk '{print tolower($0)}' )-ci@not-real.com"
git config user.name "${GITHUB_USERNAME} CI"

# a release build may have pushed to the versions repo meanwhile: rebase onto it and retry
push_master() {
  local i
  for i in {1..5}; do
    if git push origin master --quiet; then
      return 0
    fi
    echo "Push failed (attempt ${i}), rebasing onto origin/master..."
    sleep $(( 5 * i ))
    git pull --rebase origin master
  done
  echo "Could not push to ${VERSIONS_REPOSITORY}" >&2
  return 1
}

git add .
if [[ -n "$( git status --porcelain )" ]]; then
  git commit -m "ci(release): update latest version manifests (build ${GITHUB_RUN_NUMBER})"
fi

echo "${RELEASE_VERSION}" > VERSION
git add VERSION
git commit -m "chore(release): set VERSION to ${RELEASE_VERSION}" --quiet || echo "VERSION already up to date"

push_master
echo "Published ${RELEASE_VERSION} and its update manifests"
