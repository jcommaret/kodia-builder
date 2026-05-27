#!/usr/bin/env bash
# shellcheck disable=SC1091

set -e

# voidVersion : priorité à VOID_VERSION (job check), comme prepare_assets.sh
voidVersion="${VOID_VERSION:-}"
[[ "${voidVersion}" == "null" ]] && voidVersion=""
if [[ -z "${voidVersion}" ]]; then
  voidVersion=$(jq -r '.voidVersion // empty' product.json 2>/dev/null || true)
  [[ "${voidVersion}" == "null" ]] && voidVersion=""
fi
if [[ -z "${voidVersion}" ]] && [[ -f vscode/product.json ]]; then
    voidVersion=$(jq -r '.voidVersion // empty' vscode/product.json)
    [[ "${voidVersion}" == "null" ]] && voidVersion=""
fi
if [[ -z "${voidVersion}" && -n "${RELEASE_VERSION}" && "${RELEASE_VERSION}" == *-* ]]; then
  voidVersion="${RELEASE_VERSION#*-}"
fi
# Doit rester aligné avec prepare_assets.sh / release.sh (PAS un nom codé en dur « voidversion »).
APP_NAME="${APP_NAME:-Void}"

if [[ "${SHOULD_BUILD}" != "yes" && "${FORCE_UPDATE}" != "true" ]]; then
  echo "Will not update version JSON because we did not build"
  exit 0
fi

if [[ -z "${GH_TOKEN}" ]] && [[ -z "${GITHUB_TOKEN}" ]] && [[ -z "${GH_ENTERPRISE_TOKEN}" ]] && [[ -z "${GITHUB_ENTERPRISE_TOKEN}" ]]; then
  echo "Will not update version JSON because no GITHUB_TOKEN defined"
  exit 0
else
  GITHUB_TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-${GH_ENTERPRISE_TOKEN:-${GITHUB_ENTERPRISE_TOKEN}}}}"
fi

# Support for GitHub Enterprise
GH_HOST="${GH_HOST:-github.com}"

if [[ "${FORCE_UPDATE}" == "true" ]]; then
  # shellcheck source=scripts/lib/utils.sh
  . scripts/lib/utils.sh
  ensure_build_sourceversion
fi

if [[ -z "${BUILD_SOURCEVERSION}" ]]; then
  echo "Will not update version JSON because no BUILD_SOURCEVERSION defined"
  exit 0
fi

# --- Gestion de la version persistante ---
if [[ -z "${RELEASE_VERSION}" ]]; then
  if [[ -n "${GITHUB_ACTIONS}" ]]; then
    echo "RELEASE_VERSION must be set in CI (from the check job). Exiting."
    exit 1
  fi
  if [[ -f "VERSION" ]]; then
    RELEASE_VERSION=$(cat VERSION)
    echo "Using RELEASE_VERSION from VERSION file: ${RELEASE_VERSION}"
  else
    echo "No RELEASE_VERSION or VERSION file found. Exiting."
    exit 1
  fi
fi

# DÉFINIR REPOSITORY_NAME AVANT DE L'UTILISER
REPOSITORY_NAME="${VERSIONS_REPOSITORY/*\//}"

# init versions repo for later commiting + pushing the json file to it
echo "Cloning repository: ${VERSIONS_REPOSITORY}"
GIT_LFS_SKIP_SMUDGE=1 git clone "https://${GH_HOST}/${VERSIONS_REPOSITORY}.git" "${REPOSITORY_NAME}" || { echo "Failed to clone repository ${VERSIONS_REPOSITORY}"; exit 1; }
if [[ ! -d "${REPOSITORY_NAME}" ]]; then
  echo "Error: Cloned directory '${REPOSITORY_NAME}' not found."
  exit 1
fi

# Racine void-builder (assets/) vs clone du dépôt versions (stable/…/latest.json)
BUILDER_ROOT="${VOID_BUILDER_ROOT:-$(pwd)}"
ASSETS_DIR="${BUILDER_ROOT}/assets"
REPO_ABSOLUTE_PATH="${BUILDER_ROOT}/${REPOSITORY_NAME}"
cd "${REPOSITORY_NAME}" || { echo "'${REPOSITORY_NAME}' dir not found"; exit 1; }
git config user.email "$( echo "${GITHUB_USERNAME}" | awk '{print tolower($0)}' )-ci@not-real.com"
git config user.name "${GITHUB_USERNAME} CI"
git remote rm origin
git remote add origin "https://${GITHUB_USERNAME}:${GITHUB_TOKEN}@${GH_HOST}/${VERSIONS_REPOSITORY}.git" &> /dev/null

# --- Définition des fonctions après le cd ---
URL_BASE="https://${GH_HOST}/${ASSETS_REPOSITORY}/releases/download/${RELEASE_VERSION}"

generateJson() {
  local url name version productVersion sha1hash sha256hash timestamp
  JSON_DATA="{}"

  # generate parts
  url="${URL_BASE}/${ASSET_NAME}"
  name="${RELEASE_VERSION}"
  version="${BUILD_SOURCEVERSION}"
  productVersion="$( transformVersion "${RELEASE_VERSION}" )"
  timestamp=$( node -e 'console.log(Date.now())' )

  local asset_path="${ASSETS_DIR}/${ASSET_NAME}"

  if [[ ! -f "${asset_path}" ]]; then
    echo "Downloading asset '${ASSET_NAME}' from ${ASSETS_REPOSITORY}@${RELEASE_VERSION}"
    mkdir -p "${ASSETS_DIR}"
    set +e
    gh release download --repo "${ASSETS_REPOSITORY}" "${RELEASE_VERSION}" \
      --dir "${ASSETS_DIR}" --pattern "${ASSET_NAME}*"
    set -e
  fi

  if [[ ! -f "${asset_path}" ]]; then
    echo "Asset '${ASSET_NAME}' introuvable dans ${ASSETS_DIR} ni sur la release — skip."
    return 1
  fi

  sha1hash=$( awk '{ print $1 }' "${ASSETS_DIR}/${ASSET_NAME}.sha1" )
  sha256hash=$( awk '{ print $1 }' "${ASSETS_DIR}/${ASSET_NAME}.sha256" )

  # check that nothing is blank (blank indicates something awry with build)
  for key in url name version productVersion sha1hash timestamp sha256hash; do
    if [[ -z "${!key}" ]]; then
      echo "Variable '${key}' is empty; exiting..."
      exit 1
    fi
  done

  # generate json
  JSON_DATA=$( jq \
    --arg url             "${url}" \
    --arg name            "${name}" \
    --arg version         "${version}" \
    --arg productVersion  "${productVersion}" \
    --arg hash            "${sha1hash}" \
    --arg timestamp       "${timestamp}" \
    --arg sha256hash      "${sha256hash}" \
    '. | .url=$url | .name=$name | .version=$version | .productVersion=$productVersion | .hash=$hash | .timestamp=$timestamp | .sha256hash=$sha256hash' \
    <<<'{}' )
}

transformVersion() {
  local version parts

  version="${1%-insider}"

  # Tag composite type « 1.99.3-1.4.9 » : dériver le semver produit à partir de la base VS Code (prefix avant le tiret).
  if [[ "${version}" == *-* ]]; then
    version="${version%%-*}"
  fi

  IFS='.' read -r -a parts <<< "${version}"

  # Remove leading zeros from third part
  parts[2]="$((10#${parts[2]}))"

  version="${parts[0]}.${parts[1]}.${parts[2]}.0"

  if [[ "${1}" == *-insider ]]; then
    version="${version}-insider"
  fi

  echo "${version}"
}

updateLatestVersion() {
  echo "Updating ${VERSION_PATH}/latest.json"

  # do not update the same version
  if [[ -f "${VERSION_PATH}/latest.json" ]]; then
    CURRENT_VERSION=$( jq -r '.name' "${VERSION_PATH}/latest.json" )
    echo "CURRENT_VERSION: ${CURRENT_VERSION}"

    if [[ "${CURRENT_VERSION}" == "${RELEASE_VERSION}" && "${FORCE_UPDATE}" != "true" ]]; then
      return 0
    fi
  fi

  echo "Generating ${VERSION_PATH}/latest.json"

  mkdir -p "${VERSION_PATH}"

  if ! generateJson; then
    echo "Skipped ${VERSION_PATH} (asset manquant)"
    return 0
  fi

  echo "${JSON_DATA}" > "${VERSION_PATH}/latest.json"

  echo "${JSON_DATA}"
}

# Rester dans le clone versions : VERSION_PATH = stable/… sous ce dépôt ; assets = ${BUILDER_ROOT}/assets
if [[ "${OS_NAME}" == "osx" ]]; then
  ASSET_NAME="${APP_NAME}-${voidVersion}-${VSCODE_ARCH}.dmg"
  VERSION_PATH="${VSCODE_QUALITY}/darwin/${voidVersion}"
  updateLatestVersion
elif [[ "${OS_NAME}" == "windows" ]]; then
  # system installer (prepare_assets : pas de voidVersion dans le nom de fichier)
  ASSET_NAME="${APP_NAME}Setup-${VSCODE_ARCH}-${RELEASE_VERSION}.exe"
  VERSION_PATH="${VSCODE_QUALITY}/win32/${RELEASE_VERSION}/system"
  updateLatestVersion

  # user installer
  ASSET_NAME="${APP_NAME}UserSetup-${VSCODE_ARCH}-${RELEASE_VERSION}.exe"
  VERSION_PATH="${VSCODE_QUALITY}/win32/${RELEASE_VERSION}/user"
  updateLatestVersion

  # windows archive
  ASSET_NAME="${APP_NAME}-win32-${VSCODE_ARCH}-${RELEASE_VERSION}.zip"
  VERSION_PATH="${VSCODE_QUALITY}/win32/${RELEASE_VERSION}/archive"
  updateLatestVersion

  if [[ "${VSCODE_ARCH}" == "ia32" || "${VSCODE_ARCH}" == "x64" ]]; then
    # msi
    ASSET_NAME="${APP_NAME}-${VSCODE_ARCH}-${RELEASE_VERSION}.msi"
    VERSION_PATH="${VSCODE_QUALITY}/win32/${RELEASE_VERSION}/msi"
    updateLatestVersion

    # updates-disabled msi
    ASSET_NAME="${APP_NAME}-${VSCODE_ARCH}-updates-disabled-${RELEASE_VERSION}.msi"
    VERSION_PATH="${VSCODE_QUALITY}/win32/${RELEASE_VERSION}/msi-updates-disabled"
    updateLatestVersion
  fi
else # linux
  ASSET_NAME="${APP_NAME}-linux-${VSCODE_ARCH}-${RELEASE_VERSION}.tar.gz"
  VERSION_PATH="${VSCODE_QUALITY}/linux/${RELEASE_VERSION}"
  updateLatestVersion
fi

# Retour au dépôt cloné pour commiter (chemin absolu)
if [[ ! -d "${REPO_ABSOLUTE_PATH}" ]]; then
  echo "Error: Directory '${REPO_ABSOLUTE_PATH}' not found. Cloning may have failed."
  exit 1
fi
cd "${REPO_ABSOLUTE_PATH}" || { echo "'${REPO_ABSOLUTE_PATH}' dir not found"; exit 1; }

git pull origin master
git add .

CHANGES=$( git status --porcelain )

if [[ -n "${CHANGES}" ]]; then
  echo "Some changes have been found, pushing them"
  dateAndMonth=$( date "+%D %T" )
  git commit -m "CI update: ${dateAndMonth} (Build ${GITHUB_RUN_NUMBER})"
if ! git push origin master --quiet; then
  git pull origin master
  git push origin master --quiet
  fi
else
  echo "No changes"
fi

# Fichier VERSION : une seule écriture (job macOS) pour éviter les conflits git avec Windows/Linux
if [[ "${WRITE_VERSION_FILE}" == "yes" ]]; then
  echo "${RELEASE_VERSION}" > VERSION
  git add VERSION
  if ! git commit -m "Update VERSION file to ${RELEASE_VERSION}" --quiet; then
    echo "No changes to VERSION file or already up to date."
  fi
  git push origin master --quiet
fi
