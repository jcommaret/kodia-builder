#!/usr/bin/env bash
# shellcheck disable=SC1091,2154

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export VOID_BUILDER_ROOT="${REPO_ROOT}"
# shellcheck source=scripts/lib/utils.sh
. "${REPO_ROOT}/scripts/lib/utils.sh"
# shellcheck source=scripts/lib/ci_lib.sh
source "${REPO_ROOT}/scripts/lib/ci_lib.sh"

# Void - disable icon copying, we already handled icons
# if [[ "${VSCODE_QUALITY}" == "insider" ]]; then
#   cp -rp src/insider/* vscode/
# else
#   cp -rp src/stable/* vscode/
# fi

# Void - keep our license...
# cp -f LICENSE vscode/LICENSE.txt

cd vscode || { echo "'vscode' dir not found"; exit 1; }

# nls.ts uses `!typescript` which is falsy for empty strings "".
# An empty .ts file (e.g. dialogHandler.ts in jcommaret/void) produces sourcesContent:[""]
# which causes a spurious build error. Allow empty source content through; the patch()
# function already returns early when there are no localize() calls.
if [[ -f build/lib/nls.ts ]]; then
  replace 's/if \(!typescript\) \{/if (typescript == null) {/' build/lib/nls.ts
fi

"${REPO_ROOT}/scripts/update_settings.sh"

# apply patches
{ set +x; } 2>/dev/null

echo "APP_NAME=\"${APP_NAME}\""
echo "APP_NAME_LC=\"${APP_NAME_LC}\""
echo "BINARY_NAME=\"${BINARY_NAME}\""
echo "GH_REPO_PATH=\"${GH_REPO_PATH}\""
echo "ORG_NAME=\"${ORG_NAME}\""

echo "Applying patches at ../patches/*.patch..." # Void comment
for file in ../patches/*.patch; do
  if [[ -f "${file}" ]]; then
    # Upstream drift in Void regularly breaks these patches.
    # - policies.patch: policy-watcher churn in package.json
    # - add-remote-url.patch: gulpfile JS->TS migration in upstream
    # Policy watcher lock is handled separately by patches/helper/apply_policy_watcher_lock.sh.
    if [[ "$(basename "${file}")" == "policies.patch" || "$(basename "${file}")" == "add-remote-url.patch" ]]; then
      echo "Skipping volatile patch: ${file}"
      continue
    fi
    apply_patch "${file}"
  fi
done

if [[ -x "../patches/helper/apply_policy_watcher_lock.sh" ]]; then
  ../patches/helper/apply_policy_watcher_lock.sh
fi

if [[ "${VSCODE_QUALITY}" == "insider" ]]; then
  echo "Applying insider patches..." # Void comment
  for file in ../patches/insider/*.patch; do
    if [[ -f "${file}" ]]; then
      apply_patch "${file}"
    fi
  done
fi

# OS_NAME vide = job compile Ubuntu : ne pas traiter ../patches/ comme un « sous-dossier OS »
# (sinon on réapplique ../patches/*.patch deux fois et add-remote-url etc. échouent).
if [[ -n "${OS_NAME}" ]] && [[ -d "../patches/${OS_NAME}/" ]]; then
  echo "Applying OS patches (${OS_NAME})..." # Void comment
  for file in "../patches/${OS_NAME}/"*.patch; do
    if [[ -f "${file}" ]]; then
      apply_patch "${file}"
    fi
  done
fi

echo "Applying user patches..." # Void comment
for file in ../patches/user/*.patch; do
  if [[ -f "${file}" ]]; then
    apply_patch "${file}"
  fi
done

set -x

export ELECTRON_SKIP_BINARY_DOWNLOAD=1
export PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1

if [[ "${OS_NAME}" == "linux" ]]; then
  export VSCODE_SKIP_NODE_VERSION_CHECK=1

   if [[ "${npm_config_arch}" == "arm" ]]; then
    export npm_config_arm_version=7
  fi
elif [[ "${OS_NAME}" == "windows" ]]; then
  if [[ "${npm_config_arch}" == "arm" ]]; then
    export npm_config_arm_version=7
  fi
else
  if [[ "${CI_BUILD}" != "no" ]]; then
    clang++ --version
  fi
fi

# Since VS Code 1.141 the postinstall fetches electron.d.ts using the Electron version read
# from .npmrc, which ../npmrc does not carry. Fetch it now so the postinstall finds it in place.
if [[ -f build/npm/electronTypes.ts ]]; then
  node build/npm/electronTypes.ts
fi

mv .npmrc .npmrc.bak
cp ../npmrc .npmrc

for i in {1..5}; do # try 5 times
  if [[ "${CI_BUILD}" != "no" && "${OS_NAME}" == "osx" ]]; then
    CXX=clang++ npm ci && break
  else
    npm ci && break
  fi

  echo "npm ci failed (attempt ${i}), trying npm install fallback..."
  if [[ "${CI_BUILD}" != "no" && "${OS_NAME}" == "osx" ]]; then
    CXX=clang++ npm install --no-audit --no-fund && break
  else
    npm install --no-audit --no-fund && break
  fi

  if [[ $i == 3 ]]; then
    echo "Npm install failed too many times" >&2
    exit 1
  fi
  echo "Npm install failed $i, trying again..."

  sleep $(( 15 * (i + 1)))
done

mv .npmrc.bak .npmrc

setpath() {
  local jsonTmp
  { set +x; } 2>/dev/null
  jsonTmp=$( jq --arg 'path' "${2}" --arg 'value' "${3}" 'setpath([$path]; $value)' "${1}.json" )
  echo "${jsonTmp}" > "${1}.json"
  set -x
}

setpath_json() {
  local jsonTmp
  { set +x; } 2>/dev/null
  jsonTmp=$( jq --arg 'path' "${2}" --argjson 'value' "${3}" 'setpath([$path]; $value)' "${1}.json" )
  echo "${jsonTmp}" > "${1}.json"
  set -x
}

# product.json
cp product.json{,.bak}

setpath "product" "checksumFailMoreInfoUrl" "https://go.microsoft.com/fwlink/?LinkId=828886"
setpath "product" "documentationUrl" "https://github.com/${GH_REPO_PATH}#readme"
# setpath_json "product" "extensionsGallery" '{"serviceUrl": "https://open-vsx.org/vscode/gallery", "itemUrl": "https://open-vsx.org/vscode/item"}'
setpath "product" "introductoryVideosUrl" "https://go.microsoft.com/fwlink/?linkid=832146"
setpath "product" "keyboardShortcutsUrlLinux" "https://go.microsoft.com/fwlink/?linkid=832144"
setpath "product" "keyboardShortcutsUrlMac" "https://go.microsoft.com/fwlink/?linkid=832143"
setpath "product" "keyboardShortcutsUrlWin" "https://go.microsoft.com/fwlink/?linkid=832145"
setpath "product" "licenseUrl" "https://github.com/${GH_REPO_PATH}/blob/master/LICENSE.txt"
# setpath_json "product" "linkProtectionTrustedDomains" '["https://open-vsx.org"]'
# setpath "product" "releaseNotesUrl" "https://go.microsoft.com/fwlink/?LinkID=533483#vscode"
setpath "product" "reportIssueUrl" "https://github.com/${GH_REPO_PATH}/issues/new"
setpath "product" "requestFeatureUrl" "https://github.com/${GH_REPO_PATH}/issues/new"
setpath "product" "tipsAndTricksUrl" "https://go.microsoft.com/fwlink/?linkid=852118"

if [[ "${DISABLE_UPDATE}" != "yes" ]]; then
  setpath "product" "updateUrl" "https://raw.githubusercontent.com/${VERSIONS_REPOSITORY:-${GH_REPO_PATH}}/refs/heads/master"
  setpath "product" "downloadUrl" "https://github.com/${ASSETS_REPOSITORY:-${GH_REPO_PATH}}/releases"
fi

if [[ "${VSCODE_QUALITY}" == "insider" ]]; then
  setpath "product" "nameShort" "Kodia - Insiders"
  setpath "product" "nameLong" "Kodia - Insiders"
  setpath "product" "applicationName" "kodia-insiders"
  setpath "product" "dataFolderName" ".kodia-insiders"
  setpath "product" "linuxIconName" "kodia-insiders"
  setpath "product" "quality" "insider"
  setpath "product" "urlProtocol" "kodia-insiders"
  setpath "product" "serverApplicationName" "kodia-server-insiders"
  setpath "product" "serverDataFolderName" ".kodia-server-insiders"
  setpath "product" "darwinBundleIdentifier" "com.jcommaret.kodia.insiders"
  setpath "product" "win32AppUserModelId" "Kodia.KodiaInsiders"
  setpath "product" "win32DirName" "Kodia Insiders"
  setpath "product" "win32MutexName" "kodiainsiders"
  setpath "product" "win32NameVersion" "Kodia Insiders"
  setpath "product" "win32RegValueName" "KodiaInsiders"
  setpath "product" "win32ShellNameShort" "Kodia Insiders"
  setpath "product" "win32AppId" "{{9D19AA49-FF13-4B3F-BA21-469C9470E5E2}"
  setpath "product" "win32x64AppId" "{{C246875C-2B2B-461E-B18D-1C76BA1BB8E8}"
  setpath "product" "win32arm64AppId" "{{DBCCA03C-A859-4235-8D9B-24B82E896C1D}"
  setpath "product" "win32UserAppId" "{{06BDFE9D-D233-4BF2-A45A-289755673D42}"
  setpath "product" "win32x64UserAppId" "{{4E412965-A587-4349-8D14-FAB4512DC45D}"
  setpath "product" "win32arm64UserAppId" "{{5BB79E2E-1106-48C9-9F7C-8D173EE48E18}"
else
  setpath "product" "nameShort" "Kodia"
  setpath "product" "nameLong" "Kodia"
  setpath "product" "applicationName" "kodia"
  setpath "product" "linuxIconName" "kodia"
  setpath "product" "quality" "stable"
  setpath "product" "urlProtocol" "kodia"
  setpath "product" "serverApplicationName" "kodia-server"
  setpath "product" "serverDataFolderName" ".kodia-server"
  setpath "product" "darwinBundleIdentifier" "com.jcommaret.kodia"
  setpath "product" "win32AppUserModelId" "Void.Void"
  setpath "product" "win32DirName" "Kodia"
  setpath "product" "win32MutexName" "void"
  setpath "product" "win32NameVersion" "Kodia"
  setpath "product" "win32RegValueName" "Void"
  setpath "product" "win32ShellNameShort" "K&odia"
  # Windows installer identity (AppIds in jcommaret/kodia's product.json, mutex, registry and AppUserModelId) still
  # Void's: changing it needs the installer to remove the previous install first, tested on Windows
fi

jsonTmp=$( jq -s '.[0] * .[1]' product.json ../product.json )
echo "${jsonTmp}" > product.json && unset jsonTmp

if [[ -n "${VOID_VERSION}" ]]; then
  setpath "product" "voidVersion" "${VOID_VERSION}"
fi

cat product.json

# package.json
cp package.json{,.bak}

# package.json : x.y.z (app macOS/Linux, affichage). Inno x.y.z.0 → prepare_assets.sh (Windows uniquement).
package_version="$(ci_normalize_ms_tag "${MS_TAG:-${RELEASE_VERSION%-insider}}")"
echo "package.json version: ${package_version} (MS_TAG=${MS_TAG:-?} RELEASE_VERSION=${RELEASE_VERSION})"
setpath "package" "version" "${package_version}"

replace 's|Microsoft Corporation|Void|' package.json

cp resources/server/manifest.json{,.bak}

if [[ "${VSCODE_QUALITY}" == "insider" ]]; then
  setpath "resources/server/manifest" "name" "Void - Insiders"
  setpath "resources/server/manifest" "short_name" "Void - Insiders"
else
  setpath "resources/server/manifest" "name" "Void"
  setpath "resources/server/manifest" "short_name" "Void"
fi

cp resources/server/manifest.json{,.bak}

if [[ "${VSCODE_QUALITY}" == "insider" ]]; then
  setpath "resources/server/manifest" "name" "Void - Insiders"
  setpath "resources/server/manifest" "short_name" "Void - Insiders"
else
  # Void already has this
  setpath "resources/server/manifest" "name" "Void"
  setpath "resources/server/manifest" "short_name" "Void"
fi

# announcements
# replace "s|\\[\\/\\* BUILTIN_ANNOUNCEMENTS \\*\\/\\]|$( tr -d '\n' < ../announcements-builtin.json )|" src/vs/workbench/contrib/welcomeGettingStarted/browser/gettingStarted.ts

"${REPO_ROOT}/scripts/undo_telemetry.sh"

# Escape non-ASCII chars that fail esbuild's minification integrity check.
# ›(U+203A) ❯(U+276F) ▸(U+25B8) ▶(U+25B6) appear as string/regex literals in
# some TS source files; esbuild only auto-converts them inside /regex/ literals,
# not inside quoted strings. Must be done after npm ci so ripgrep is available.
# Remove Copilot: make prepareBuiltInCopilotRipgrepShim a no-op when the
# extension or its SDK directory is absent (we don't install/bundle Copilot).
if [[ -f build/lib/copilot.ts ]]; then
  node --input-type=commonjs - << 'NODEEOF'
const {readFileSync, writeFileSync} = require('fs');
const f = 'build/lib/copilot.ts';
let c = readFileSync(f, 'utf8');
// Replace the throw with a warn+return so build doesn't fail when Copilot is absent.
c = c.replace(
  "throw new Error(`[prepareBuiltInCopilotRipgrepShim] Copilot SDK directory not found at ${copilotSdkBase}`);",
  "console.warn('[prepareBuiltInCopilotRipgrepShim] Copilot SDK absent – shim skipped.'); return;"
);
writeFileSync(f, c);
console.log('patched build/lib/copilot.ts: shim is now optional');
NODEEOF
fi

# Remove extensions/copilot from the postinstall dirs so npm ci never installs it.
if [[ -f build/npm/dirs.ts ]]; then
  node --input-type=commonjs - << 'NODEEOF'
const {readFileSync, writeFileSync} = require('fs');
const f = 'build/npm/dirs.ts';
let c = readFileSync(f, 'utf8');
c = c.replace(/^\s*'extensions\/copilot',?\n/m, '');
for (const ext of ['extensions/open-remote-ssh', 'extensions/open-remote-wsl']) {
  if (!c.includes(`'${ext}'`)) {
    c = c.replace(/(\t'remote',)/, `\t'${ext}',\n$1`);
  }
}
writeFileSync(f, c);
console.log('patched build/npm/dirs.ts: removed extensions/copilot, ensured void remote extensions');
NODEEOF
fi

echo "Escaping non-ASCII chars in TypeScript sources (esbuild minify guard)..."
node --input-type=commonjs - << 'NODEEOF'
const {readFileSync, writeFileSync, existsSync} = require('fs');
const {execSync} = require('child_process');
const CHARS = {'\u203a':'\\u203a', '\u276f':'\\u276f', '\u25b8':'\\u25b8', '\u25b6':'\\u25b6'};
const PATTERN = /[\u203a\u276f\u25b8\u25b6]/g;
const rg = './node_modules/@vscode/ripgrep/bin/rg';
const needle = '\u203a\u276f\u25b8\u25b6';
let files = [];
try {
  if (existsSync(rg)) {
    files = execSync(rg + " --no-ignore -l '[" + needle + "]' src/", {encoding:'utf8'}).trim().split('\n').filter(Boolean);
  } else {
    files = execSync("grep -rl --include='*.ts' '[" + needle + "]' src/ 2>/dev/null || true", {encoding:'utf8', shell:'/bin/bash'}).trim().split('\n').filter(Boolean);
  }
} catch { /* no matches — no files need fixing */ }
for (const f of files) {
  const orig = readFileSync(f, 'utf8');
  const fixed = orig.replace(PATTERN, c => CHARS[c]);
  if (fixed !== orig) { writeFileSync(f, fixed); console.log('fixed non-ASCII in:', f); }
}
NODEEOF

[[ -f build/lib/electron.js ]] && replace 's|Microsoft Corporation|Void|' build/lib/electron.js
[[ -f build/lib/electron.ts ]] && replace 's|Microsoft Corporation|Void|' build/lib/electron.ts
[[ -f build/lib/electron.js ]] && replace 's|([0-9]) Microsoft|\1 Void|' build/lib/electron.js
[[ -f build/lib/electron.ts ]] && replace 's|([0-9]) Microsoft|\1 Void|' build/lib/electron.ts

if [[ "${OS_NAME}" == "linux" ]]; then
  # microsoft adds their apt repo to sources
  # unless the app name is code-oss
  # as we are renaming the application to void
  # we need to edit a line in the post install template
  if [[ "${VSCODE_QUALITY}" == "insider" ]]; then
    sed -i "s/code-oss/kodia-insiders/" resources/linux/debian/postinst.template
  else
    sed -i "s/code-oss/kodia/" resources/linux/debian/postinst.template
  fi

  # fix the packages metadata
  # code.appdata.xml
  sed -i 's|Visual Studio Code|Void|g' resources/linux/code.appdata.xml
  sed -i "s|https://code.visualstudio.com/docs/setup/linux|https://github.com/${GH_REPO_PATH}|" resources/linux/code.appdata.xml
  sed -i 's|https://code.visualstudio.com/home/home-screenshot-linux-lg.png|https://vscodium.com/img/vscodium.png|' resources/linux/code.appdata.xml
  sed -i "s|https://code.visualstudio.com|https://github.com/${GH_REPO_PATH}|" resources/linux/code.appdata.xml

  # control.template
  sed -i 's|Microsoft Corporation <vscode-linux@microsoft.com>|Void Team <team@voideditor.com>|'  resources/linux/debian/control.template
  sed -i 's|Visual Studio Code|Void|g' resources/linux/debian/control.template
  sed -i "s|https://code.visualstudio.com/docs/setup/linux|https://github.com/${GH_REPO_PATH}|" resources/linux/debian/control.template
  sed -i "s|https://code.visualstudio.com|https://github.com/${GH_REPO_PATH}|" resources/linux/debian/control.template

  # code.spec.template
  sed -i 's|Microsoft Corporation|Void Team|' resources/linux/rpm/code.spec.template
  sed -i 's|Visual Studio Code Team <vscode-linux@microsoft.com>|Void Team <team@voideditor.com>|' resources/linux/rpm/code.spec.template
  sed -i 's|Visual Studio Code|Void|' resources/linux/rpm/code.spec.template
  sed -i "s|https://code.visualstudio.com/docs/setup/linux|https://github.com/${GH_REPO_PATH}|" resources/linux/rpm/code.spec.template
  sed -i "s|https://code.visualstudio.com|https://github.com/${GH_REPO_PATH}|" resources/linux/rpm/code.spec.template

  # snapcraft.yaml
  sed -i 's|Visual Studio Code|Void|'  resources/linux/rpm/code.spec.template
elif [[ "${OS_NAME}" == "windows" ]]; then
  # code.iss
  sed -i "s|https://code.visualstudio.com|https://github.com/${GH_REPO_PATH}|" build/win32/code.iss
  sed -i 's|Microsoft Corporation|Void|' build/win32/code.iss
fi

cd ..
