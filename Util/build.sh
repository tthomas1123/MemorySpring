#!/usr/bin/env bash
(
set -e
cd "$(dirname "$0")/.."
WORKSPACE=${CM_BUILD_DIR:="${GITHUB_WORKSPACE:="$(pwd)"}"}
export WORKSPACE

function err {
    echo "$1" 1>&2
    return 1
}

echo "Verifying input parameters"

S2D_BUILD_NUMBER="$(echo "$S2D_BUILD_NAME." | cut -d. -f2)"
[ "${APP_VERSION}" ] || err "APP_VERSION is required"
[ "${S2D_BUILD_NAME}" ] || err "S2D_BUILD_NAME is required"
[ "${S2D_BUILD_NUMBER}" ] || err "S2D_BUILD_NAME has invalid format (example: 2026.3729)"
[ "${CERT_PASSWORD}" ] || err "CERT_PASSWORD is required"

if [ "${CI}" ]; then
    echo "Setting up code signing"

    security delete-keychain build.keychain || true
    security create-keychain -p 'Password123' build.keychain
    security default-keychain -s build.keychain
    security import "Util/distribution.p12" -A -P "$CERT_PASSWORD"
    security unlock-keychain -p 'Password123' build.keychain
    security set-keychain-settings build.keychain
    security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k 'Password123' build.keychain > /dev/null
fi

S2D_DMG="Util/S2D-${S2D_BUILD_NUMBER}.dmg"
S2D_MOUNT="$(mktemp -d /tmp/s2d-mount-XXXXXX)"
S2D_TMP="$(mktemp -d /tmp/s2d-tools-XXXXXX)"

cleanup() {
    hdiutil detach "${S2D_MOUNT}" >/dev/null 2>&1 || true
    rm -rf "${S2D_MOUNT}" "${S2D_TMP}"
}
trap cleanup EXIT

if [ ! -f "${S2D_DMG}" ]; then
    echo "Downloading Solar2D"
    curl -L "https://github.com/coronalabs/corona/releases/download/${S2D_BUILD_NUMBER}/Solar2D-macOS-${S2D_BUILD_NAME}.dmg" -o "${S2D_DMG}"
fi

echo "Mounting Solar2D image"
hdiutil attach "${S2D_DMG}" -noautoopen -mountpoint "${S2D_MOUNT}"

echo "Copying builder tools to writable temp location"
cp -R "${S2D_MOUNT}/Corona-${S2D_BUILD_NUMBER}" "${S2D_TMP}/"

echo "Unmounting Solar2D image"
hdiutil detach "${S2D_MOUNT}"

echo "Building the app"
BUILDER="${S2D_TMP}/Corona-${S2D_BUILD_NUMBER}/Native/Corona/mac/bin/CoronaBuilder.app/Contents/MacOS/CoronaBuilder"
[ -f "${BUILDER}" ] || err "CoronaBuilder not found at ${BUILDER}"

"${BUILDER}" build --lua "Util/recipe.lua"
)