#!/usr/bin/env bash
# shellcheck disable=SC1091

set -e

# Linux CI: a package format is built only when its SHOULD_BUILD_* flag says yes (stable-linux.yml: tar.gz, .deb, .rpm)
if [[ "${OS_NAME}" == "linux" && "${GITHUB_ACTIONS}" == "true" ]]; then
  [[ "${SHOULD_BUILD_DEB}" == "yes" ]] || SHOULD_BUILD_DEB="no"
  [[ "${SHOULD_BUILD_RPM}" == "yes" ]] || SHOULD_BUILD_RPM="no"
  [[ "${SHOULD_BUILD_APPIMAGE}" == "yes" ]] || SHOULD_BUILD_APPIMAGE="no"
  echo "Linux CI: DEB=${SHOULD_BUILD_DEB} RPM=${SHOULD_BUILD_RPM} APPIMAGE=${SHOULD_BUILD_APPIMAGE} TAR=${SHOULD_BUILD_TAR:-yes}"
fi

# voidVersion : priorité VOID_VERSION du job check (évite l’ancienne valeur dans product.json).
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

APP_NAME="${APP_NAME:-Void}"

# --- Alias pour les nouveaux noms de secrets macOS (si différents) ---
CERTIFICATE_OSX_APP_PASSWORD="${CERTIFICATE_OSX_NEW_APP_PASSWORD:-${CERTIFICATE_OSX_APP_PASSWORD}}"
CERTIFICATE_OSX_ID="${CERTIFICATE_OSX_NEW_ID:-${CERTIFICATE_OSX_ID}}"
CERTIFICATE_OSX_P12_DATA="${CERTIFICATE_OSX_NEW_P12_DATA:-${CERTIFICATE_OSX_P12_DATA}}"
CERTIFICATE_OSX_P12_PASSWORD="${CERTIFICATE_OSX_NEW_P12_PASSWORD:-${CERTIFICATE_OSX_P12_PASSWORD}}"
CERTIFICATE_OSX_TEAM_ID="${CERTIFICATE_OSX_NEW_TEAM_ID:-${CERTIFICATE_OSX_TEAM_ID}}"

APP_NAME_LC="$( echo "${APP_NAME}" | awk '{print tolower($0)}' )"

mkdir -p assets

if [[ "${OS_NAME}" == "osx" ]]; then
  # Signature et notarisation désactivées (certificat Apple expiré) : décommenter ces blocs pour les réactiver.
  # if [[ -n "${CERTIFICATE_OSX_P12_DATA}" ]]; then
    # if [[ "${CI_BUILD}" == "no" ]]; then
      # RUNNER_TEMP="${TMPDIR}"
    # fi
#
    # CERTIFICATE_P12="${APP_NAME}.p12"
    # KEYCHAIN="${RUNNER_TEMP}/buildagent.keychain"
    # AGENT_TEMPDIRECTORY="${RUNNER_TEMP}"
    # shellcheck disable=SC2006
    # KEYCHAINS=`security list-keychains | xargs`
#
    # rm -f "${KEYCHAIN}"
#
    # echo "${CERTIFICATE_OSX_P12_DATA}" | base64 --decode > "${CERTIFICATE_P12}"
#
    # echo "+ create temporary keychain"
    # security create-keychain -p pwd "${KEYCHAIN}"
    # security set-keychain-settings -lut 21600 "${KEYCHAIN}"
    # security unlock-keychain -p pwd "${KEYCHAIN}"
    # shellcheck disable=SC2086
    # security list-keychains -s $KEYCHAINS "${KEYCHAIN}"
    # security show-keychain-info "${KEYCHAIN}"
#
    # echo "+ import certificate to keychain"
    # security import "${CERTIFICATE_P12}" -k "${KEYCHAIN}" -P "${CERTIFICATE_OSX_P12_PASSWORD}" -T /usr/bin/codesign
    # security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k pwd "${KEYCHAIN}" > /dev/null
    # security find-identity "${KEYCHAIN}"
#
    # CODESIGN_IDENTITY="$( security find-identity -v -p codesigning "${KEYCHAIN}" | grep -oEi "([0-9A-F]{40})" | head -n 1 )"
#
    # echo "+ signing"
    # export CODESIGN_IDENTITY AGENT_TEMPDIRECTORY
#
    # DEBUG="electron-osx-sign*" node --experimental-strip-types vscode/build/darwin/sign.ts "$( pwd )"
    # codesign --display --entitlements :- ""
#
    # echo "+ notarize"
#
    # cd "VSCode-darwin-${VSCODE_ARCH}"
    # ZIP_FILE="./${APP_NAME}-darwin-${VSCODE_ARCH}-${RELEASE_VERSION}.zip"
#
    # zip -r -X -y "${ZIP_FILE}" ./*.app
#
    # xcrun notarytool store-credentials "${APP_NAME}" --apple-id "${CERTIFICATE_OSX_ID}" --team-id "${CERTIFICATE_OSX_TEAM_ID}" --password "${CERTIFICATE_OSX_APP_PASSWORD}" --keychain "${KEYCHAIN}"
    # xcrun notarytool history --keychain-profile "${APP_NAME}" --keychain "${KEYCHAIN}"
    # xcrun notarytool submit "${ZIP_FILE}" --keychain-profile "${APP_NAME}" --wait --keychain "${KEYCHAIN}"
#
    # echo "+ attach staple"
    # xcrun stapler staple ./*.app
    # spctl --assess -vv --type install ./*.app
#
    # rm "${ZIP_FILE}"
#
    # cd ..
  # fi

  # Signature ad-hoc (pas d'identité Apple tant que la signature est désactivée) : sans bundle scellé,
  # Gatekeeper refuse les apps téléchargées et affiche « endommagé ». Retirer ce bloc quand la signature
  # Developer ID est réactivée (le bloc signé ci-dessus prend alors le relais).
  echo "Ad-hoc signing the app bundle"
  for APP_BUNDLE in VSCode-darwin-"${VSCODE_ARCH}"/*.app; do
    codesign --force --deep --sign - "${APP_BUNDLE}"
    codesign --verify --deep --strict "${APP_BUNDLE}"
  done

  if [[ "${SHOULD_BUILD_ZIP}" != "no" ]]; then
    echo "Building and moving ZIP"
    cd "VSCode-darwin-${VSCODE_ARCH}"
    zip -r -X -y "../assets/${APP_NAME}-darwin-${VSCODE_ARCH}-${RELEASE_VERSION}.zip" ./*.app
    cd ..
  fi

  if [[ "${SHOULD_BUILD_DMG}" != "no" ]]; then
    echo "Building and moving DMG"
    # npx depuis void-builder échoue après popd (ENOENT package.json) — install isolée
    CREATE_DMG_PREFIX="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/vb-create-dmg"
    CREATE_DMG_BIN="${CREATE_DMG_PREFIX}/node_modules/.bin/create-dmg"
    mkdir -p "${CREATE_DMG_PREFIX}"
    if [[ ! -x "${CREATE_DMG_BIN}" ]]; then
      npm install --prefix="${CREATE_DMG_PREFIX}" --no-save create-dmg@8.1.0
    fi
    if [[ ! -x "${CREATE_DMG_BIN}" ]]; then
      echo "create-dmg introuvable après install (attendu: ${CREATE_DMG_BIN})" >&2
      exit 1
    fi
    pushd "VSCode-darwin-${VSCODE_ARCH}"
    # La signature est désactivée (certificat expiré) : sans --no-code-sign, create-dmg échoue faute d'identité.
    # Retirer ce flag quand la signature est réactivée.
    "${CREATE_DMG_BIN}" --no-code-sign ./*.app .
    # Aligné avec update_version.sh : ${APP_NAME}-<voidVersion>-<arch>.dmg
    DMG_FILE=$(ls *.dmg)
    mv "${DMG_FILE}" "../assets/${APP_NAME}-${voidVersion}-${VSCODE_ARCH}.dmg"
    popd
  fi

  if [[ "${SHOULD_BUILD_SRC}" == "yes" ]]; then
    git archive --format tar.gz --output="./assets/${APP_NAME}-${RELEASE_VERSION}-src.tar.gz" HEAD
    git archive --format zip --output="./assets/${APP_NAME}-${RELEASE_VERSION}-src.zip" HEAD
  fi

  # if [[ -n "${CERTIFICATE_OSX_P12_DATA}" ]]; then
    # echo "+ clean"
    # security delete-keychain "${KEYCHAIN}"
    # shellcheck disable=SC2086
    # security list-keychains -s $KEYCHAINS
  # fi

  VSCODE_PLATFORM="darwin"
elif [[ "${OS_NAME}" == "windows" ]]; then
  cd vscode || { echo "'vscode' dir not found"; exit 1; }

  # Void: skip Appx/MSIX context-menu package – not built in OSS CI (Inno Setup would fail).
  if [[ -f build/gulpfile.vscode.win32.ts ]]; then
    node --input-type=commonjs - << 'NODEEOF'
const {readFileSync, writeFileSync} = require('fs');
const f = 'build/gulpfile.vscode.win32.ts';
let c = readFileSync(f, 'utf8');
const needle = "if (quality === 'stable' || quality === 'insider') {";
const patch = "if (false /* Void: no Appx package */ && (quality === 'stable' || quality === 'insider')) {";
if (c.includes(needle) && !c.includes('Void: no Appx package')) {
  c = c.replace(needle, patch);
  writeFileSync(f, c);
  console.log('patched build/gulpfile.vscode.win32.ts: Appx disabled');
}
NODEEOF
  fi

  # Contournement Inno (x.y.z.w) : patch temporaire de package.json, puis restauration x.y.z
  # shellcheck source=scripts/lib/ci_lib.sh
  source "${VOID_BUILDER_ROOT:-${GITHUB_WORKSPACE:-.}}/scripts/lib/ci_lib.sh"
  ci_apply_win_inno_package_version

  # inno-updater ajoute tools/ au dossier de l'app : il passe avant tout le reste, que le MSI et les setups embarquent.
  npm run gulp "vscode-win32-${VSCODE_ARCH}-inno-updater"

  # Ensuite le zip, les deux setups Inno et le MSI ne font que lire le dossier de l'app et écrivent chacun ailleurs
  # (.build/win32-*/{system,user}-setup, build/windows/msi/releasedir) : on les construit en parallèle. Chaque outil
  # n'occupe qu'un ou deux cœurs du runner, et ils prenaient environ 15 min à la suite.
  win_build_zip() {
    7z.exe a -tzip "../assets/${APP_NAME}-win32-${VSCODE_ARCH}-${RELEASE_VERSION}.zip" -x!CodeSignSummary*.md -x!tools "../VSCode-win32-${VSCODE_ARCH}/*" -r
  }
  win_build_system_setup() {
    npm run gulp "vscode-win32-${VSCODE_ARCH}-system-setup"
  }
  win_build_user_setup() {
    npm run gulp "vscode-win32-${VSCODE_ARCH}-user-setup"
  }
  win_build_msi() {
    . ../build/windows/msi/build.sh
  }

  win_names=()
  win_pids=()
  win_start() {
    echo "Starting ${1} in the background"
    ( set -e; "${1}" ) > "../${1}.log" 2>&1 &
    win_names+=("${1}")
    win_pids+=("$!")
  }

  [[ "${SHOULD_BUILD_ZIP}" != "no" ]] && win_start win_build_zip
  [[ "${SHOULD_BUILD_EXE_SYS}" != "no" ]] && win_start win_build_system_setup
  [[ "${SHOULD_BUILD_EXE_USR}" != "no" ]] && win_start win_build_user_setup
  if [[ "${VSCODE_ARCH}" == "ia32" || "${VSCODE_ARCH}" == "x64" ]] && [[ "${SHOULD_BUILD_MSI}" != "no" ]]; then
    win_start win_build_msi
  fi

  win_failed=0
  for i in "${!win_pids[@]}"; do
    if wait "${win_pids[$i]}"; then
      win_status="ok"
    else
      win_status="FAILED"
      win_failed=1
    fi
    echo "::group::${win_names[$i]} (${win_status})"
    cat "../${win_names[$i]}.log"
    echo "::endgroup::"
    rm -f "../${win_names[$i]}.log"
  done

  if (( win_failed )); then
    echo "At least one Windows package failed: see the groups above" >&2
    exit 1
  fi

  # Les setups Inno lisent la version x.y.z.w de package.json : on ne la restaure qu'une fois qu'ils sont terminés.
  ci_restore_package_json_version

  cd ..

  if [[ "${SHOULD_BUILD_EXE_SYS}" != "no" ]]; then
    echo "Moving System EXE"
    mv "vscode\\.build\\win32-${VSCODE_ARCH}\\system-setup\\VSCodeSetup.exe" "assets\\${APP_NAME}Setup-${VSCODE_ARCH}-${RELEASE_VERSION}.exe"
  fi

  if [[ "${SHOULD_BUILD_EXE_USR}" != "no" ]]; then
    echo "Moving User EXE"
    mv "vscode\\.build\\win32-${VSCODE_ARCH}\\user-setup\\VSCodeSetup.exe" "assets\\${APP_NAME}UserSetup-${VSCODE_ARCH}-${RELEASE_VERSION}.exe"
  fi

  if [[ "${VSCODE_ARCH}" == "ia32" || "${VSCODE_ARCH}" == "x64" ]]; then
    if [[ "${SHOULD_BUILD_MSI}" != "no" ]]; then
      echo "Moving MSI"
      mv "build\\windows\\msi\\releasedir\\${APP_NAME}-${VSCODE_ARCH}-${RELEASE_VERSION}.msi" assets/
    fi
  fi

  VSCODE_PLATFORM="win32"
else
  cd vscode || { echo "'vscode' dir not found"; exit 1; }

  if [[ "${SHOULD_BUILD_APPIMAGE}" == "yes" && "${VSCODE_ARCH}" != "x64" ]]; then
    SHOULD_BUILD_APPIMAGE="no"
  fi

  if [[ "${SHOULD_BUILD_DEB}" == "yes" ]]; then
    npm run gulp "vscode-linux-${VSCODE_ARCH}-prepare-deb"
    npm run gulp "vscode-linux-${VSCODE_ARCH}-build-deb"
  fi

  if [[ "${SHOULD_BUILD_RPM}" == "yes" ]]; then
    npm run gulp "vscode-linux-${VSCODE_ARCH}-prepare-rpm"
    npm run gulp "vscode-linux-${VSCODE_ARCH}-build-rpm"
  fi

  if [[ "${SHOULD_BUILD_APPIMAGE}" == "yes" ]]; then
    . ../build/linux/appimage/build.sh
  fi

  cd ..

  if [[ "${CI_BUILD}" == "no" ]]; then
    . ./stores/snapcraft/build.sh

    if [[ "${SKIP_ASSETS}" == "no" ]]; then
      mv stores/snapcraft/build/*.snap assets/
    fi
  fi

  if [[ "${SHOULD_BUILD_TAR}" != "no" ]]; then
    echo "Building and moving TAR"
    cd "VSCode-linux-${VSCODE_ARCH}"
    tar czf "../assets/${APP_NAME}-linux-${VSCODE_ARCH}-${RELEASE_VERSION}.tar.gz" .
    cd ..
  fi

  if [[ "${SHOULD_BUILD_DEB}" == "yes" ]]; then
    echo "Moving DEB"
    # Nom stable (sans le timestamp de build du paquet) : un re-run écrase le .deb au lieu d'en ajouter un second.
    mv vscode/.build/linux/deb/*/deb/*.deb "assets/${APP_NAME}-linux-${VSCODE_ARCH}-${RELEASE_VERSION}.deb"
  fi

  if [[ "${SHOULD_BUILD_RPM}" == "yes" ]]; then
    echo "Moving RPM"
    # Nom stable, comme pour le .deb.
    mv vscode/.build/linux/rpm/*/*.rpm "assets/${APP_NAME}-linux-${VSCODE_ARCH}-${RELEASE_VERSION}.rpm"
  fi

  if [[ "${SHOULD_BUILD_APPIMAGE}" == "yes" ]]; then
    echo "Moving AppImage"
    mv build/linux/appimage/out/*.AppImage* assets/

    find assets -name '*.AppImage*' -exec bash -c 'mv $0 ${0/_-_/-}' {} \;
  fi

  VSCODE_PLATFORM="linux"
fi

if [[ "${SHOULD_BUILD_REH}" != "no" ]]; then
  echo "Building and moving REH"
  cd "vscode-reh-${VSCODE_PLATFORM}-${VSCODE_ARCH}"
  tar czf "../assets/${APP_NAME_LC}-reh-${VSCODE_PLATFORM}-${VSCODE_ARCH}-${RELEASE_VERSION}.tar.gz" .
  cd ..
fi

if [[ "${SHOULD_BUILD_REH_WEB}" != "no" ]]; then
  echo "Building and moving REH-web"
  cd "vscode-reh-web-${VSCODE_PLATFORM}-${VSCODE_ARCH}"
  tar czf "../assets/${APP_NAME_LC}-reh-web-${VSCODE_PLATFORM}-${VSCODE_ARCH}-${RELEASE_VERSION}.tar.gz" .
  cd ..
fi

write_asset_checksums() {
  local file="${1}"
  if [[ ! -f "${file}" ]]; then
    return 0
  fi
  echo "Calculating checksum for ${file}"
  if [[ "${OS_NAME}" == "osx" ]] && command -v shasum &>/dev/null; then
    shasum -a 256 "${file}" | awk '{print $1}' > "${file}.sha256"
  elif command -v checksum &>/dev/null; then
    checksum -a sha256 "${file}" > "${file}.sha256"
  elif [[ "${OS_NAME}" == "windows" ]] && command -v certutil &>/dev/null; then
    certutil -hashfile "${file}" SHA256 | awk 'NR==2 {print $1}' > "${file}.sha256"
  elif command -v shasum &>/dev/null; then
    shasum -a 256 "${file}" | awk '{print $1}' > "${file}.sha256"
  elif command -v sha256sum &>/dev/null; then
    sha256sum "${file}" | awk '{print $1}' > "${file}.sha256"
  else
    echo "No checksum tool available for ${file}" >&2
    return 1
  fi
}

(
  cd assets
  for FILE in *; do
    if [[ -f "${FILE}" ]]; then
      write_asset_checksums "${FILE}"
    fi
  done
)
