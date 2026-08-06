#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
REPO_ROOT=${SCRIPT_DIR:h:h}
CORE_LIB_DIR=${SIMPLEX_CORE_LIB_DIR:-${REPO_ROOT}/apps/multiplatform/release/main/app/SimpleX.app/Contents/app/resources}
OUTPUT_DIR=${NATIVE_CHAT_OUTPUT_DIR:-/private/tmp/native-chat-build}
SWIFT_BUILD_DIR=${OUTPUT_DIR}/swift-build
APP_DIR=${OUTPUT_DIR}/Native\ Chat.app
SIGN_IDENTITY=${NATIVE_CHAT_SIGN_IDENTITY:--}
APP_VERSION=${NATIVE_CHAT_VERSION:-0.3.0}
APP_BUILD=${NATIVE_CHAT_BUILD_NUMBER:-3}
SOURCE_REPOSITORY=${NATIVE_CHAT_SOURCE_REPOSITORY:-https://github.com/ajzrva-sys/simplex-chat}
SOURCE_REVISION=$(git -C ${REPO_ROOT} rev-parse HEAD)
SOURCE_URL=${SOURCE_REPOSITORY}/tree/${SOURCE_REVISION}
DEVELOPMENT_BUILD=NO

if [[ -n $(git -C ${REPO_ROOT} status --porcelain) ]]; then
  SOURCE_URL=${SOURCE_REPOSITORY}/tree/macos-native
  DEVELOPMENT_BUILD=YES
fi

if [[ ! -f ${CORE_LIB_DIR}/libsimplex.dylib ]]; then
  print -u2 "SimpleX core libraries not found at ${CORE_LIB_DIR}"
  exit 1
fi

env CLANG_MODULE_CACHE_PATH=${OUTPUT_DIR}/clang-cache SWIFTPM_MODULECACHE_OVERRIDE=${OUTPUT_DIR}/swiftpm-cache \
  swift build --disable-sandbox --package-path ${SCRIPT_DIR} --scratch-path ${SWIFT_BUILD_DIR} \
    -c release --arch arm64 --product SimpleXNative

if [[ -d ${APP_DIR} ]]; then
  BUILD_TIMESTAMP=$(date +%Y%m%d-%H%M%S)
  mv ${APP_DIR} ${OUTPUT_DIR}/NativeChat.previous.${BUILD_TIMESTAMP}.app
fi

mkdir -p ${APP_DIR}/Contents/MacOS ${APP_DIR}/Contents/Frameworks ${APP_DIR}/Contents/Resources
cp ${SWIFT_BUILD_DIR}/arm64-apple-macosx/release/SimpleXNative ${APP_DIR}/Contents/MacOS/NativeChat
cp ${CORE_LIB_DIR}/*.dylib ${APP_DIR}/Contents/Frameworks/
if [[ -d ${SWIFT_BUILD_DIR}/arm64-apple-macosx/release/Sparkle.framework ]]; then
  cp -R ${SWIFT_BUILD_DIR}/arm64-apple-macosx/release/Sparkle.framework ${APP_DIR}/Contents/Frameworks/
fi
ICONSET=${OUTPUT_DIR}/NativeChat.iconset
rm -rf ${ICONSET}
mkdir -p ${ICONSET}
xcrun swiftc -module-cache-path ${OUTPUT_DIR}/icon-module-cache -framework AppKit \
  ${SCRIPT_DIR}/Tools/GenerateAppIcon.swift -o ${OUTPUT_DIR}/generate-native-chat-icon
${OUTPUT_DIR}/generate-native-chat-icon ${ICONSET}
cp ${ICONSET}/icon_512x512@2x.png ${APP_DIR}/Contents/Resources/NativeChat.png
cp ${REPO_ROOT}/LICENSE ${APP_DIR}/Contents/Resources/AGPL-3.0.txt
cp ${SCRIPT_DIR}/Resources/NOTICE.txt ${APP_DIR}/Contents/Resources/NOTICE.txt
cp ${SCRIPT_DIR}/MODIFICATIONS.md ${APP_DIR}/Contents/Resources/MODIFICATIONS.md
ditto ${REPO_ROOT}/docs/dependencies/licences ${APP_DIR}/Contents/Resources/ThirdPartyLicenses
/usr/bin/printf 'Corresponding source for this build:\n%s\n\nRevision:\n%s\n' \
  ${SOURCE_URL} ${SOURCE_REVISION} > ${APP_DIR}/Contents/Resources/SourceCode.txt

plutil -create xml1 ${APP_DIR}/Contents/Info.plist
plutil -insert CFBundleDevelopmentRegion -string en ${APP_DIR}/Contents/Info.plist
plutil -insert CFBundleExecutable -string NativeChat ${APP_DIR}/Contents/Info.plist
plutil -insert CFBundleIconFile -string NativeChat.png ${APP_DIR}/Contents/Info.plist
plutil -insert CFBundleIdentifier -string io.github.ajzrva.nativechat ${APP_DIR}/Contents/Info.plist
plutil -insert CFBundleInfoDictionaryVersion -string 6.0 ${APP_DIR}/Contents/Info.plist
plutil -insert CFBundleName -string "Native Chat" ${APP_DIR}/Contents/Info.plist
plutil -insert CFBundleDisplayName -string "Native Chat" ${APP_DIR}/Contents/Info.plist
plutil -insert CFBundlePackageType -string APPL ${APP_DIR}/Contents/Info.plist
plutil -insert CFBundleShortVersionString -string ${APP_VERSION} ${APP_DIR}/Contents/Info.plist
plutil -insert CFBundleVersion -string ${APP_BUILD} ${APP_DIR}/Contents/Info.plist
plutil -insert LSApplicationCategoryType -string public.app-category.social-networking ${APP_DIR}/Contents/Info.plist
plutil -insert LSMultipleInstancesProhibited -bool YES ${APP_DIR}/Contents/Info.plist
plutil -insert LSMinimumSystemVersion -string 14.0 ${APP_DIR}/Contents/Info.plist
plutil -insert NSHighResolutionCapable -bool YES ${APP_DIR}/Contents/Info.plist
plutil -insert NSHumanReadableCopyright -string "Copyright © 2026 Native Chat contributors" ${APP_DIR}/Contents/Info.plist
plutil -insert NSPrincipalClass -string NSApplication ${APP_DIR}/Contents/Info.plist
plutil -insert NSCameraUsageDescription -string "Native Chat uses the camera for video calls and scanning SimpleX QR codes." ${APP_DIR}/Contents/Info.plist
plutil -insert NSMicrophoneUsageDescription -string "Native Chat uses the microphone for calls and voice messages." ${APP_DIR}/Contents/Info.plist
plutil -insert NativeChatKeychainPassphraseStorageEnabled -bool YES ${APP_DIR}/Contents/Info.plist
plutil -insert NativeChatSourceRepository -string ${SOURCE_REPOSITORY} ${APP_DIR}/Contents/Info.plist
plutil -insert NativeChatSourceRevision -string ${SOURCE_REVISION} ${APP_DIR}/Contents/Info.plist
plutil -insert NativeChatSourceURL -string ${SOURCE_URL} ${APP_DIR}/Contents/Info.plist
plutil -insert NativeChatDevelopmentBuild -bool ${DEVELOPMENT_BUILD} ${APP_DIR}/Contents/Info.plist

xattr -cr ${APP_DIR}
# Add rpath for embedded frameworks
install_name_tool -add_rpath @executable_path/../Frameworks ${APP_DIR}/Contents/MacOS/NativeChat 2>/dev/null || true
for library in ${APP_DIR}/Contents/Frameworks/*.dylib; do
  codesign --force --sign ${SIGN_IDENTITY} ${library}
done
# Sign Sparkle framework if present
if [[ -d ${APP_DIR}/Contents/Frameworks/Sparkle.framework ]]; then
  codesign --force --sign ${SIGN_IDENTITY} ${APP_DIR}/Contents/Frameworks/Sparkle.framework
fi
codesign --force --entitlements ${SCRIPT_DIR}/NativeChat.entitlements --sign ${SIGN_IDENTITY} ${APP_DIR}/Contents/MacOS/NativeChat
codesign --force --entitlements ${SCRIPT_DIR}/NativeChat.entitlements --sign ${SIGN_IDENTITY} ${APP_DIR}
codesign --verify --deep --strict ${APP_DIR}
lipo -archs ${APP_DIR}/Contents/MacOS/NativeChat | grep -qx arm64
print ${APP_DIR}
