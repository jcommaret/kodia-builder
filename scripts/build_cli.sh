#!/usr/bin/env bash

set -ex

cd cli

export CARGO_NET_GIT_FETCH_WITH_CLI="true"
export VSCODE_CLI_APP_NAME="$( echo "${APP_NAME}" | awk '{print tolower($0)}' )"
export VSCODE_CLI_BINARY_NAME="$( node -p "require(\"../product.json\").serverApplicationName" )"
export VSCODE_CLI_UPDATE_ENDPOINT="https://raw.githubusercontent.com/voideditor/versions/refs/heads/main" # Void

if [[ "${VSCODE_QUALITY}" == "insider" ]]; then
  export VSCODE_CLI_DOWNLOAD_ENDPOINT="https://github.com/voideditor/void-insiders/releases"
else
  export VSCODE_CLI_DOWNLOAD_ENDPOINT="https://github.com/voideditor/void/releases" # Void
fi

TUNNEL_APPLICATION_NAME="$( node -p "require(\"../product.json\").tunnelApplicationName" )"
NAME_SHORT="$( node -p "require(\"../product.json\").nameShort" )"

npm pack @vscode/openssl-prebuilt@0.0.11
mkdir openssl
tar -xvzf vscode-openssl-prebuilt-0.0.11.tgz --strip-components=1 --directory=openssl

if [[ "${OS_NAME}" == "osx" ]]; then
  if [[ "${VSCODE_ARCH}" == "arm64" ]]; then
    VSCODE_CLI_TARGET="aarch64-apple-darwin"
  else
    VSCODE_CLI_TARGET="x86_64-apple-darwin"
  fi

  export OPENSSL_LIB_DIR="$( pwd )/openssl/out/${VSCODE_ARCH}-osx/lib"
  export OPENSSL_INCLUDE_DIR="$( pwd )/openssl/out/${VSCODE_ARCH}-osx/include"

  rustup target add "${VSCODE_CLI_TARGET}"
  export RUSTFLAGS="-A unused-imports"
  cargo build --release --target "${VSCODE_CLI_TARGET}" --bin=code

  cp "target/${VSCODE_CLI_TARGET}/release/code" "../../VSCode-darwin-${VSCODE_ARCH}/${NAME_SHORT}.app/Contents/Resources/app/bin/${TUNNEL_APPLICATION_NAME}"
elif [[ "${OS_NAME}" == "windows" ]]; then
  # Git Bash place usr\bin très tôt dans PATH : rustc invoque alors « link.exe » Unix,
  # pas le linker MSVC (erreur « /usr/bin/link: extra operand »).
  _sanitize_path_for_rust_windows() {
    local result="" dir norm tmp
    tmp="${PATH//;/:}"
    tmp="${tmp}:"
    while [[ -n "$tmp" ]]; do
      dir="${tmp%%:*}"
      tmp="${tmp#*:}"
      [[ -z "${dir}" ]] && continue
      norm="${dir//\\//}"
      if [[ "${norm}" =~ [Gg]it/.*/usr/bin ]]; then
        continue
      fi
      [[ -n "${result}" ]] && result="${result}:"
      result="${result}${dir}"
    done
    printf '%s' "${result}"
  }

  # VsDevCmd / ilammy/msvc-dev-cmd : forcer link.exe MSVC (Hostx64/x64 ou Hostx64/arm64).
  _force_msvc_linker_for_rust() {
    local host="${1}"
    local vc="${VCToolsInstallDir:-}"
    [[ -z "${vc}" ]] && return 0
    vc="${vc//\\//}"
    [[ "${vc}" != */ ]] && vc="${vc}/"
    local bindir="${vc}bin/Hostx64/${host}"
    local linkexe="${bindir}/link.exe"
    [[ ! -f "${linkexe}" ]] && return 0
    export PATH="${bindir}:${PATH}"
    case "${host}" in
      arm64) export CARGO_TARGET_AARCH64_PC_WINDOWS_MSVC_LINKER="${linkexe}" ;;
      x64) export CARGO_TARGET_X86_64_PC_WINDOWS_MSVC_LINKER="${linkexe}" ;;
    esac
  }

  export PATH="$(_sanitize_path_for_rust_windows)"

  if [[ "${VSCODE_ARCH}" == "arm64" ]]; then
    VSCODE_CLI_TARGET="aarch64-pc-windows-msvc"
    _force_msvc_linker_for_rust "arm64"
    export VSCODE_CLI_RUST="-C target-feature=+crt-static -Clink-args=/guard:cf -Clink-args=/CETCOMPAT:NO"
  else
    VSCODE_CLI_TARGET="x86_64-pc-windows-msvc"
    _force_msvc_linker_for_rust "x64"
    export VSCODE_CLI_RUSTFLAGS="-Ctarget-feature=+crt-static -Clink-args=/guard:cf -Clink-args=/CETCOMPAT"
  fi

  export VSCODE_CLI_CFLAGS="/guard:cf /Qspectre"
  export OPENSSL_LIB_DIR="$( pwd )/openssl/out/${VSCODE_ARCH}-windows-static/lib"
  export OPENSSL_INCLUDE_DIR="$( pwd )/openssl/out/${VSCODE_ARCH}-windows-static/include"

  rustup target add "${VSCODE_CLI_TARGET}"

  export RUSTFLAGS="-A unused-imports"
  cargo build --release --target "${VSCODE_CLI_TARGET}" --bin=code

  cp "target/${VSCODE_CLI_TARGET}/release/code.exe" "../../VSCode-win32-${VSCODE_ARCH}/bin/${TUNNEL_APPLICATION_NAME}.exe"
else
  export OPENSSL_LIB_DIR="$( pwd )/openssl/out/${VSCODE_ARCH}-linux/lib"
  export OPENSSL_INCLUDE_DIR="$( pwd )/openssl/out/${VSCODE_ARCH}-linux/include"
  export VSCODE_SYSROOT_DIR="../.build/sysroots"

  if [[ "${VSCODE_ARCH}" == "arm64" ]]; then
    VSCODE_CLI_TARGET="aarch64-unknown-linux-gnu"

    if [[ "${CI_BUILD}" != "no" ]]; then
      export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER=aarch64-linux-gnu-gcc
      export CC_aarch64_unknown_linux_gnu=aarch64-linux-gnu-gcc
      export CXX_aarch64_unknown_linux_gnu=aarch64-linux-gnu-g++
      export PKG_CONFIG_ALLOW_CROSS=1
    fi
  elif [[ "${VSCODE_ARCH}" == "armhf" ]]; then
    VSCODE_CLI_TARGET="armv7-unknown-linux-gnueabihf"

    export OPENSSL_LIB_DIR="$( pwd )/openssl/out/arm-linux/lib"
    export OPENSSL_INCLUDE_DIR="$( pwd )/openssl/out/arm-linux/include"

    if [[ "${CI_BUILD}" != "no" ]]; then
      export CARGO_TARGET_ARMV7_UNKNOWN_LINUX_GNUEABIHF_LINKER=arm-linux-gnueabihf-gcc
      export CC_armv7_unknown_linux_gnueabihf=arm-linux-gnueabihf-gcc
      export CXX_armv7_unknown_linux_gnueabihf=arm-linux-gnueabihf-g++
      export PKG_CONFIG_ALLOW_CROSS=1
    fi
  elif [[ "${VSCODE_ARCH}" == "x64" ]]; then
    VSCODE_CLI_TARGET="x86_64-unknown-linux-gnu"
  fi

  if [[ -n "${VSCODE_CLI_TARGET}" ]]; then
    rustup target add "${VSCODE_CLI_TARGET}"

    export RUSTFLAGS="-A unused-imports"
    cargo build --release --target "${VSCODE_CLI_TARGET}" --bin=code

    cp "target/${VSCODE_CLI_TARGET}/release/code" "../../VSCode-linux-${VSCODE_ARCH}/bin/${TUNNEL_APPLICATION_NAME}"
  fi
fi

cd ..
