#!/bin/bash
set -euo pipefail

APP_NAME="zyquo"
BUNDLE_ID="dev.zyquo.cli"
VERSION="1.2.0"
IDENTITY="Developer ID Application: Simon-Pierre Boucher (3YM54G49SN)"
KEYCHAIN_PROFILE="MacLustr-Notarize"
ENTITLEMENTS="Entitlements/Zyquo.entitlements"
DMG_NAME="Zyquo.dmg"
ZIP_NAME="Zyquo.zip"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${PROJECT_DIR}"

release() {
    echo "==> Building release..."
    swift build -c release
    echo "    Release build complete."
    echo "    Binary: .build/release/${APP_NAME}"
    ls -lh ".build/release/${APP_NAME}"
}

sign() {
    echo "==> Signing with Developer ID..."

    local BINARY=".build/release/${APP_NAME}"
    if [ ! -f "${BINARY}" ]; then
        echo "    Error: Binary not found. Run '$0 release' first."
        exit 1
    fi

    codesign --force --options runtime \
        --entitlements "${ENTITLEMENTS}" \
        --sign "${IDENTITY}" \
        --timestamp \
        "${BINARY}"

    echo "    Signed: ${BINARY}"
}

zip_pkg() {
    echo "==> Creating ZIP for notarization..."

    local BINARY=".build/release/${APP_NAME}"
    if [ ! -f "${BINARY}" ]; then
        echo "    Error: Binary not found. Run '$0 release' first."
        exit 1
    fi

    rm -f "${ZIP_NAME}"
    ditto -c -k --keepParent "${BINARY}" "${ZIP_NAME}"
    echo "    ZIP created: ${ZIP_NAME}"
}

notarize() {
    echo "==> Submitting for notarization..."

    if [ ! -f "${ZIP_NAME}" ]; then
        echo "    Error: ZIP not found. Run '$0 zip' first."
        exit 1
    fi

    xcrun notarytool submit "${ZIP_NAME}" \
        --keychain-profile "${KEYCHAIN_PROFILE}" \
        --wait

    echo "    Notarization complete."
}

dmg() {
    echo "==> Creating DMG..."

    local BINARY=".build/release/${APP_NAME}"
    if [ ! -f "${BINARY}" ]; then
        echo "    Error: Binary not found. Run '$0 release' first."
        exit 1
    fi

    local STAGING_DIR=$(mktemp -d)
    cp "${BINARY}" "${STAGING_DIR}/"

    rm -f "${DMG_NAME}"
    hdiutil create -volname "Zyquo" \
        -srcfolder "${STAGING_DIR}" \
        -ov -format UDZO \
        "${DMG_NAME}"

    codesign --force --sign "${IDENTITY}" --timestamp "${DMG_NAME}"
    rm -rf "${STAGING_DIR}"
    echo "    DMG created: ${DMG_NAME}"
}

staple() {
    echo "==> Stapling tickets..."

    if [ -f "${DMG_NAME}" ]; then
        xcrun stapler staple "${DMG_NAME}"
        echo "    Stapled: ${DMG_NAME}"
    fi

    echo "    Stapling complete."
}

verify() {
    echo "==> Verifying signatures..."

    local BINARY=".build/release/${APP_NAME}"
    if [ ! -f "${BINARY}" ]; then
        echo "    Error: Binary not found."
        exit 1
    fi

    echo "--- codesign ---"
    codesign -dvv "${BINARY}" 2>&1 || true

    echo ""
    echo "--- spctl (Gatekeeper) ---"
    spctl -a -t execute -vv "${BINARY}" 2>&1 || true

    echo ""
    echo "    Verification complete."
}

notarize_dmg() {
    echo "==> Submitting DMG for notarization..."

    if [ ! -f "${DMG_NAME}" ]; then
        echo "    Error: DMG not found. Run '$0 dmg' first."
        exit 1
    fi

    xcrun notarytool submit "${DMG_NAME}" \
        --keychain-profile "${KEYCHAIN_PROFILE}" \
        --wait

    echo "    DMG notarization complete."
}

dist() {
    echo "========================================="
    echo "  Zyquo — Full Distribution Build"
    echo "========================================="
    release
    sign
    dmg
    notarize_dmg
    staple
    verify
    echo ""
    echo "  Distribution complete!"
    echo "  Binary: .build/release/${APP_NAME}"
    echo "  DMG: ${DMG_NAME}"
    echo "========================================="
}

clean() {
    echo "==> Cleaning..."
    rm -f "${DMG_NAME}" "${ZIP_NAME}"
    echo "    Clean complete."
}

help() {
    echo "Usage: $0 <command>"
    echo ""
    echo "Commands:"
    echo "  release    Release build (swift build -c release)"
    echo "  sign       Code sign with Developer ID"
    echo "  zip        Create ZIP for notarization submission"
    echo "  notarize   Submit to Apple notarization"
    echo "  dmg        Create DMG installer"
    echo "  staple     Staple notarization tickets"
    echo "  verify     Verify code signatures"
    echo "  dist       Full pipeline: release → sign → zip → notarize → dmg → staple → verify"
    echo "  clean      Remove distribution artifacts"
    echo ""
}

case "${1:-help}" in
    release)   release ;;
    sign)      sign ;;
    zip)       zip_pkg ;;
    notarize)  notarize ;;
    dmg)       dmg ;;
    staple)    staple ;;
    verify)    verify ;;
    dist)      dist ;;
    clean)     clean ;;
    *)         help ;;
esac
