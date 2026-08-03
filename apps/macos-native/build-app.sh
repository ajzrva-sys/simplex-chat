#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
REPO_ROOT=${SCRIPT_DIR:h:h}
CORE_LIB_DIR=${SIMPLEX_CORE_LIB_DIR:-${REPO_ROOT}/apps/multiplatform/release/main/app/SimpleX.app/Contents/app/resources}
OUTPUT_DIR=${NATIVE_CHAT_OUTPUT_DIR:-/private/tmp/native-chat-build}
APP_DIR=${OUTPUT_DIR}/Native\ Chat.app
SIGN_IDENTITY=${NATIVE_CHAT_SIGN_IDENTITY:--}

if [[ ! -f ${CORE_LIB_DIR}/libsimplex.dylib ]]; then
  print -u2 "SimpleX core libraries not found at ${CORE_LIB_DIR}"
  exit 1
fi

env CLANG_MODULE_CACHE_PATH=${OUTPUT_DIR}/clang-cache SWIFTPM_MODULECACHE_OVERRIDE=${OUTPUT_DIR}/swiftpm-cache \
  swift build --disable-sandbox --package-path ${SCRIPT_DIR} -c release --arch arm64 --product SimpleXNative

if [[ -d ${APP_DIR} ]]; then
  BUILD_TIMESTAMP=$(date +%Y%m%d-%H%M%S)
  mv ${APP_DIR} ${OUTPUT_DIR}/NativeChat.previous.${BUILD_TIMESTAMP}.app
fi

mkdir -p ${APP_DIR}/Contents/MacOS ${APP_DIR}/Contents/Frameworks ${APP_DIR}/Contents/Resources
cp ${SCRIPT_DIR}/.build/arm64-apple-macosx/release/SimpleXNative ${APP_DIR}/Contents/MacOS/NativeChat
cp ${CORE_LIB_DIR}/*.dylib ${APP_DIR}/Contents/Frameworks/
ICONSET=${OUTPUT_DIR}/NativeChat.iconset
rm -rf ${ICONSET}
mkdir -p ${ICONSET}
xcrun swiftc -module-cache-path ${OUTPUT_DIR}/icon-module-cache -framework AppKit \
  ${SCRIPT_DIR}/Tools/GenerateAppIcon.swift -o ${OUTPUT_DIR}/generate-native-chat-icon
${OUTPUT_DIR}/generate-native-chat-icon ${ICONSET}
cp ${ICONSET}/icon_512x512@2x.png ${APP_DIR}/Contents/Resources/NativeChat.png

plutil -create xml1 ${APP_DIR}/Contents/Info.plist
plutil -insert CFBundleDevelopmentRegion -string en ${APP_DIR}/Contents/Info.plist
plutil -insert CFBundleExecutable -string NativeChat ${APP_DIR}/Contents/Info.plist
plutil -insert CFBundleIconFile -string NativeChat.png ${APP_DIR}/Contents/Info.plist
plutil -insert CFBundleIdentifier -string io.github.ajzrva.nativechat ${APP_DIR}/Contents/Info.plist
plutil -insert CFBundleInfoDictionaryVersion -string 6.0 ${APP_DIR}/Contents/Info.plist
plutil -insert CFBundleName -string "Native Chat" ${APP_DIR}/Contents/Info.plist
plutil -insert CFBundleDisplayName -string "Native Chat" ${APP_DIR}/Contents/Info.plist
plutil -insert CFBundlePackageType -string APPL ${APP_DIR}/Contents/Info.plist
plutil -insert CFBundleShortVersionString -string 7.0.0 ${APP_DIR}/Contents/Info.plist
plutil -insert CFBundleVersion -string 1 ${APP_DIR}/Contents/Info.plist
plutil -insert LSApplicationCategoryType -string public.app-category.social-networking ${APP_DIR}/Contents/Info.plist
plutil -insert LSMultipleInstancesProhibited -bool YES ${APP_DIR}/Contents/Info.plist
plutil -insert LSMinimumSystemVersion -string 14.0 ${APP_DIR}/Contents/Info.plist
plutil -insert NSHighResolutionCapable -bool YES ${APP_DIR}/Contents/Info.plist
plutil -insert NSHumanReadableCopyright -string "Copyright © 2026 Native Chat contributors" ${APP_DIR}/Contents/Info.plist
plutil -insert NSPrincipalClass -string NSApplication ${APP_DIR}/Contents/Info.plist
plutil -insert NSCameraUsageDescription -string "Native Chat uses the camera for video calls." ${APP_DIR}/Contents/Info.plist
plutil -insert NSMicrophoneUsageDescription -string "Native Chat uses the microphone for calls and voice messages." ${APP_DIR}/Contents/Info.plist
plutil -insert NativeChatKeychainPassphraseStorageEnabled -bool YES ${APP_DIR}/Contents/Info.plist

xattr -cr ${APP_DIR}
for library in ${APP_DIR}/Contents/Frameworks/*.dylib; do
  codesign --force --sign ${SIGN_IDENTITY} ${library}
done
codesign --force --entitlements ${SCRIPT_DIR}/NativeChat.entitlements --sign ${SIGN_IDENTITY} ${APP_DIR}/Contents/MacOS/NativeChat
codesign --force --entitlements ${SCRIPT_DIR}/NativeChat.entitlements --sign ${SIGN_IDENTITY} ${APP_DIR}
codesign --verify --deep --strict ${APP_DIR}
lipo -archs ${APP_DIR}/Contents/MacOS/NativeChat | grep -qx arm64
print ${APP_DIR}
