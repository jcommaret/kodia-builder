#!/usr/bin/env bash
# shellcheck disable=SC2129

set -e

# Echo all environment variables used by this script
echo "----------- get_repo -----------"
echo "Environment variables:"
echo "CI_BUILD=${CI_BUILD}"
echo "GITHUB_REPOSITORY=${GITHUB_REPOSITORY}"
echo "RELEASE_VERSION=${RELEASE_VERSION}"
echo "VSCODE_LATEST=${VSCODE_LATEST}"
echo "VSCODE_QUALITY=${VSCODE_QUALITY}"
echo "GITHUB_ENV=${GITHUB_ENV}"

echo "SHOULD_DEPLOY=${SHOULD_DEPLOY}"
echo "SHOULD_BUILD=${SHOULD_BUILD}"
echo "-------------------------"

# git workaround
if [[ "${CI_BUILD}" != "no" ]]; then
  git config --global --add safe.directory "/__w/$( echo "${GITHUB_REPOSITORY}" | awk '{print tolower($0)}' )"
fi

VOID_REPO="${VOID_REPO:-${GH_REPO_PATH:-voideditor/void}}"
VOID_BRANCH="main"
echo "Cloning void ${VOID_REPO} (${VOID_BRANCH})..."

mkdir -p vscode
cd vscode || { echo "'vscode' dir not found"; exit 1; }

git init -q
git remote add origin "https://github.com/${VOID_REPO}.git"

# Allow callers to specify a particular commit to checkout via the
# environment variable VOID_COMMIT.  We still default to the tip of the
# ${VOID_BRANCH} branch when the variable is not provided.  Keeping
# VOID_BRANCH as "main" ensures the rest of the script (and downstream
# consumers) behave exactly as before.
if [[ -n "${VOID_COMMIT}" ]]; then
  echo "Using explicit commit ${VOID_COMMIT}"
  # Fetch just that commit to keep the clone shallow.
  git fetch --depth 1 origin "${VOID_COMMIT}"
  git checkout "${VOID_COMMIT}"
else
  git fetch --depth 1 origin "${VOID_BRANCH}"
  git checkout FETCH_HEAD
fi

MS_VERSION=$( jq -r '.version' "package.json" )
MS_VERSION="${MS_VERSION%%-*}"
# Tag release : base VS Code en major.minor.patch (ex. 1.99.3).
MS_TAG="${MS_VERSION}"
MS_COMMIT=$VOID_BRANCH # Void - MS_COMMIT doesn't seem to do much
VOID_VERSION=$( jq -r '.voidVersion // empty' "product.json" )
[[ "${VOID_VERSION}" == "null" ]] && VOID_VERSION=""

# Tag Git valide pour gh/GitHub (pas d’espaces) ; titre lisible séparé (RELEASE_TITLE).
if [[ -n "${VOID_VERSION}" ]]; then
  RELEASE_VERSION="${MS_TAG}-${VOID_VERSION}"
  RELEASE_TITLE="${MS_TAG} - ${VOID_VERSION}"
else
  RELEASE_VERSION="${MS_TAG}"
  RELEASE_TITLE="${MS_TAG}"
fi
# Downstream (release.sh, notes) : VOID_VERSION reste le numéro Void seul quand présent.
[[ -z "${VOID_VERSION}" ]] && VOID_VERSION="${RELEASE_VERSION}"

echo "RELEASE_TITLE=\"${RELEASE_TITLE}\""
echo "RELEASE_VERSION=\"${RELEASE_VERSION}\""
echo "MS_COMMIT=\"${MS_COMMIT}\""
echo "MS_VERSION=\"${MS_VERSION}\""
echo "MS_TAG=\"${MS_TAG}\""

cd ..

# for GH actions
if [[ "${GITHUB_ENV}" ]]; then
  echo "MS_TAG=${MS_TAG}" >> "${GITHUB_ENV}"
  echo "MS_COMMIT=${MS_COMMIT}" >> "${GITHUB_ENV}"
  echo "RELEASE_VERSION=${RELEASE_VERSION}" >> "${GITHUB_ENV}"
  echo "VOID_VERSION=${VOID_VERSION}" >> "${GITHUB_ENV}"
  # Titres avec espaces : syntaxe multiline officielle pour GITHUB_ENV
  {
    echo "RELEASE_TITLE<<GITHUB_RELEASE_TITLE"
    echo "${RELEASE_TITLE}"
    echo "GITHUB_RELEASE_TITLE"
  } >> "${GITHUB_ENV}"
fi



echo "----------- get_repo exports -----------"
echo "MS_VERSION ${MS_VERSION}"
echo "MS_TAG ${MS_TAG}"
echo "MS_COMMIT ${MS_COMMIT}"
echo "RELEASE_VERSION ${RELEASE_VERSION}"
echo "RELEASE_TITLE ${RELEASE_TITLE}"
echo "VOID VERSION ${VOID_VERSION}"
echo "----------------------"


export MS_TAG
export MS_COMMIT
export RELEASE_VERSION
export RELEASE_TITLE
export VOID_VERSION
