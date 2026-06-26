#!/usr/bin/env bash
set -euo pipefail

APP_NAME="PDF-Protecter"
EXECUTABLE_NAME="PDFProtecter"
PACKAGE_ID="com.pdfprotecter.cli"
VERSION="${VERSION:-1.0.0}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DIST_DIR="${PROJECT_ROOT}/dist"
BUILD_DIR="${TMPDIR:-/tmp}/pdf-protecter-macos-pkg-${USER:-user}-$$"
PAYLOAD_ROOT="${BUILD_DIR}/payload"
SCRIPTS_DIR="${BUILD_DIR}/scripts"
COMPONENT_PKG="${BUILD_DIR}/${APP_NAME}.component.pkg"
OUTPUT_PKG="${DIST_DIR}/${APP_NAME}-${VERSION}.pkg"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "error: required command not found: $1" >&2
    exit 1
  fi
}

require_macos() {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "error: macOS package builds must run on macOS." >&2
    exit 1
  fi
}

prepare_build_tree() {
  mkdir -p "${PAYLOAD_ROOT}/usr/local/lib/pdf-protecter"
  mkdir -p "${PAYLOAD_ROOT}/usr/local/bin"
  mkdir -p "${SCRIPTS_DIR}"
  mkdir -p "${DIST_DIR}"
}

cleanup_build_tree() {
  rm -rf "${BUILD_DIR}" 2>/dev/null || true
}

create_payload() {
  cp "${PROJECT_ROOT}/pdf_protecter.py" "${PAYLOAD_ROOT}/usr/local/lib/pdf-protecter/pdf_protecter.py"
  chmod 0755 "${PAYLOAD_ROOT}/usr/local/lib/pdf-protecter/pdf_protecter.py"
  ln -s "../lib/pdf-protecter/pdf_protecter.py" "${PAYLOAD_ROOT}/usr/local/bin/pdf-protecter"

  mkdir -p "${PAYLOAD_ROOT}/Applications/${APP_NAME}.app/Contents/MacOS"
  mkdir -p "${PAYLOAD_ROOT}/Applications/${APP_NAME}.app/Contents/Resources"
  cp "${PROJECT_ROOT}/pdf_protecter.py" "${PAYLOAD_ROOT}/Applications/${APP_NAME}.app/Contents/Resources/pdf_protecter.py"
  cat >"${PAYLOAD_ROOT}/Applications/${APP_NAME}.app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>${EXECUTABLE_NAME}</string>
  <key>CFBundleIdentifier</key>
  <string>${PACKAGE_ID}.app</string>
  <key>CFBundleName</key>
  <string>${APP_NAME}</string>
  <key>CFBundleDisplayName</key>
  <string>${APP_NAME}</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${VERSION}</string>
  <key>CFBundleVersion</key>
  <string>${VERSION}</string>
  <key>NSQuitAlwaysKeepsWindows</key>
  <false/>
  <key>NSWindowRestoresWorkspaceAtLaunch</key>
  <false/>
</dict>
</plist>
PLIST
  printf "APPL????" >"${PAYLOAD_ROOT}/Applications/${APP_NAME}.app/Contents/PkgInfo"
  xcrun swiftc "${PROJECT_ROOT}/macos/PDFProtecterApp.swift" \
    -module-cache-path "${BUILD_DIR}/ModuleCache" \
    -sdk "$(xcrun --show-sdk-path)" \
    -framework AppKit \
    -o "${PAYLOAD_ROOT}/Applications/${APP_NAME}.app/Contents/MacOS/${EXECUTABLE_NAME}"
  chmod 0755 "${PAYLOAD_ROOT}/Applications/${APP_NAME}.app/Contents/MacOS/${EXECUTABLE_NAME}"
}

create_scripts() {
  cat >"${SCRIPTS_DIR}/postinstall" <<'POSTINSTALL'
#!/usr/bin/env bash
set -euo pipefail

if ! command -v python3 >/dev/null 2>&1; then
  echo "PDF-Protecter requires python3. Install Command Line Tools or Python 3." >&2
fi

exit 0
POSTINSTALL
  chmod 0755 "${SCRIPTS_DIR}/postinstall"
}

build_package() {
  find "${PAYLOAD_ROOT}" -name "._*" -delete
  if command -v xattr >/dev/null 2>&1; then
    xattr -cr "${PAYLOAD_ROOT}"
    xattr -dr com.apple.provenance "${PAYLOAD_ROOT}" 2>/dev/null || true
  fi
  if command -v codesign >/dev/null 2>&1; then
    codesign --force --deep --sign - "${PAYLOAD_ROOT}/Applications/${APP_NAME}.app" >/dev/null
  fi

  COPYFILE_DISABLE=1 pkgbuild \
    --root "${PAYLOAD_ROOT}" \
    --scripts "${SCRIPTS_DIR}" \
    --identifier "${PACKAGE_ID}" \
    --version "${VERSION}" \
    --install-location "/" \
    "${COMPONENT_PKG}"

  COPYFILE_DISABLE=1 productbuild \
    --package "${COMPONENT_PKG}" \
    "${OUTPUT_PKG}"
}

main() {
  require_macos
  require_command xcrun
  require_command pkgbuild
  require_command productbuild
  trap cleanup_build_tree EXIT

  prepare_build_tree
  create_payload
  create_scripts
  build_package

  echo "Created ${OUTPUT_PKG}"
  echo "Install with: sudo installer -pkg \"${OUTPUT_PKG}\" -target /"
  echo "Run with: pdf-protecter --help"
  echo "Open the GUI with: open -a PDF-Protecter"
}

main "$@"
