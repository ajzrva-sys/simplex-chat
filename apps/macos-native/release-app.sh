#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
IDENTITY=${DEVELOPER_ID_APPLICATION:-}
OUTPUT_DIR=${NATIVE_CHAT_OUTPUT_DIR:-/private/tmp/native-chat-build}
APP_DIR=${OUTPUT_DIR}/Native\ Chat.app
ARCHIVE=${OUTPUT_DIR}/NativeChat.zip

if [[ -z ${IDENTITY} ]]; then
  print -u2 "Set DEVELOPER_ID_APPLICATION to a Developer ID Application identity."
  exit 2
fi
if ! security find-identity -v -p codesigning | grep -Fq "${IDENTITY}"; then
  print -u2 "The requested Developer ID Application identity is not installed."
  exit 2
fi

NATIVE_CHAT_SIGN_IDENTITY=- ${SCRIPT_DIR}/build-app.sh >/dev/null
for library in ${APP_DIR}/Contents/Frameworks/*.dylib; do
  codesign --force --options runtime --timestamp --sign "${IDENTITY}" "${library}"
done
codesign --force --options runtime --timestamp --entitlements ${SCRIPT_DIR}/NativeChat.entitlements --sign "${IDENTITY}" "${APP_DIR}/Contents/MacOS/NativeChat"
codesign --force --options runtime --timestamp --entitlements ${SCRIPT_DIR}/NativeChat.entitlements --sign "${IDENTITY}" "${APP_DIR}"
codesign --verify --deep --strict --verbose=2 "${APP_DIR}"
spctl --assess --type execute --verbose=2 "${APP_DIR}"
ditto -c -k --keepParent "${APP_DIR}" "${ARCHIVE}"

if [[ ${NATIVE_CHAT_NOTARIZE:-0} == 1 ]]; then
  if ! command -v asc >/dev/null; then
    print -u2 "Install and authenticate asc before requesting notarization."
    exit 2
  fi
  asc notarization submit --file "${ARCHIVE}" --wait
  xcrun stapler staple "${APP_DIR}"
  xcrun stapler validate "${APP_DIR}"
fi

print "${ARCHIVE}"
