#!/usr/bin/env bash
set -euo pipefail

BUNDLE_NAME="${BUNDLE_NAME:-PDF-Protecter-Preview}"
DISPLAY_NAME="${DISPLAY_NAME:-PDF-Protecter}"
BUNDLE_ID="${BUNDLE_ID:-com.pdfprotecter.preview}"
EXECUTABLE_NAME="PDFProtecter"
VERSION="${VERSION:-1.0.0}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DIST_DIR="${PROJECT_ROOT}/dist"
BUILD_DIR="${TMPDIR:-/tmp}/pdf-protecter-macos-app-${USER:-user}-$$"
APP_DIR="${DIST_DIR}/${BUNDLE_NAME}.app"
RESOURCES_DIR="${APP_DIR}/Contents/Resources"
MACOS_DIR="${APP_DIR}/Contents/MacOS"
ZIP_PATH="${DIST_DIR}/${BUNDLE_NAME}-${VERSION}-macOS.zip"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "error: required command not found: $1" >&2
    exit 1
  fi
}

require_macos() {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "error: macOS app builds must run on macOS." >&2
    exit 1
  fi
}

prepare_app() {
  rm -rf "${APP_DIR}" "${ZIP_PATH}"
  mkdir -p "${RESOURCES_DIR}" "${MACOS_DIR}" "${DIST_DIR}" "${BUILD_DIR}"
  cp "${PROJECT_ROOT}/pdf_protecter.py" "${RESOURCES_DIR}/pdf_protecter.py"
}

cleanup_build_tree() {
  rm -rf "${BUILD_DIR}" 2>/dev/null || true
}

write_plist() {
  cat >"${APP_DIR}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>${EXECUTABLE_NAME}</string>
  <key>CFBundleIdentifier</key>
  <string>${BUNDLE_ID}</string>
  <key>CFBundleName</key>
  <string>${DISPLAY_NAME}</string>
  <key>CFBundleDisplayName</key>
  <string>${DISPLAY_NAME}</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${VERSION}</string>
  <key>CFBundleVersion</key>
  <string>${VERSION}</string>
  <key>LSMinimumSystemVersion</key>
  <string>10.15</string>
  <key>NSQuitAlwaysKeepsWindows</key>
  <false/>
  <key>NSWindowRestoresWorkspaceAtLaunch</key>
  <false/>
</dict>
</plist>
PLIST
  printf "APPL????" >"${APP_DIR}/Contents/PkgInfo"
}

write_launcher() {
  xcrun swiftc "${PROJECT_ROOT}/macos/PDFProtecterApp.swift" \
    -module-cache-path "${BUILD_DIR}/ModuleCache" \
    -sdk "$(xcrun --show-sdk-path)" \
    -framework AppKit \
    -o "${MACOS_DIR}/${EXECUTABLE_NAME}"
  chmod 0755 "${MACOS_DIR}/${EXECUTABLE_NAME}"
}

package_zip() {
  find "${APP_DIR}" -name "._*" -delete
  if command -v xattr >/dev/null 2>&1; then
    xattr -cr "${APP_DIR}"
    xattr -dr com.apple.provenance "${APP_DIR}" 2>/dev/null || true
  fi
  if command -v codesign >/dev/null 2>&1; then
    codesign --force --deep --sign - "${APP_DIR}" >/dev/null
  fi
  ditto -c -k --keepParent "${APP_DIR}" "${ZIP_PATH}"
}

main() {
  require_macos
  require_command xcrun
  trap cleanup_build_tree EXIT
  prepare_app
  write_plist
  write_launcher
  package_zip
  echo "Created ${APP_DIR}"
  echo "Created ${ZIP_PATH}"
}

main "$@"
