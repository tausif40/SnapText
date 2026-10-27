#!/bin/bash
# Builds SnapText.app into ./build.
#
#   ./build.sh            build the app
#   ./build.sh install    build, copy to /Applications and open it
#   ./build.sh package    build for Apple silicon and Intel, and zip it for sharing
#   ./build.sh dmg        build for Apple silicon and Intel, and put it in a disk image for sharing
#   ./build.sh test       run the tests
#
# Screen Recording permission is tied to the app's signature. An ad hoc signature changes with every build,
# so the permission would have to be granted again after each rebuild. The app is therefore signed with the
# Apple Development certificate from your keychain when there is one, which keeps the permission across
# builds. Pick another certificate with SIGN_IDENTITY="…" ./build.sh, or force ad hoc with SIGN_IDENTITY=-

set -euo pipefail
cd "$(dirname "$0")"

# Xcode refuses to run until its license is accepted; the standalone Command Line Tools have no such step.
if ! xcrun --find swift >/dev/null 2>&1 && [ -d /Library/Developer/CommandLineTools ]; then
    export DEVELOPER_DIR=/Library/Developer/CommandLineTools
fi

if [ -z "${SIGN_IDENTITY:-}" ]; then
    if security find-identity -v -p codesigning 2>/dev/null | grep -q '"Apple Development'; then
        SIGN_IDENTITY="Apple Development"
    else
        SIGN_IDENTITY=-
    fi
fi

# Assembles and signs an app bundle at $2 around the executable at $1.
make_app() {
    rm -rf "$2"
    mkdir -p "$2/Contents/MacOS" "$2/Contents/Resources"
    cp "$1" "$2/Contents/MacOS/SnapText"
    cp Resources/Info.plist "$2/Contents/Info.plist"
    cp Resources/AppIcon.icns "$2/Contents/Resources/AppIcon.icns"
    codesign --force --sign "$SIGN_IDENTITY" "$2"
}

# Makes the disk image build/SnapText.dmg from the folder $1. Its window shows the app beside a link to
# Applications, on a background with an arrow from one to the other, so installing is a single drag. The layout
# comes from Resources/DMGLayout.DS_Store, which Scripts/make-dmg-layout.sh records.
make_dmg() {
    ln -s /Applications "$1/Applications"
    mkdir "$1/.background"
    cp Resources/DMGBackground.tiff "$1/.background/background.tiff"
    cp Resources/DMGLayout.DS_Store "$1/.DS_Store"
    hdiutil create -volname SnapText -srcfolder "$1" -fs HFS+ -format UDZO -imagekey zlib-level=9 -ov \
        build/SnapText.dmg -quiet
}

case "${1:-}" in
test)
    # The Command Line Tools keep swift-testing's macro plugin outside the compiler's search path.
    plugins="$(dirname "$(xcrun --find swift)")/../lib/swift/host/plugins/testing"
    if [ -d "$plugins" ]; then
        exec swift test -Xswiftc -plugin-path -Xswiftc "$plugins"
    fi
    exec swift test
    ;;
package | dmg)
    # A copy to hand to other people: it runs on both kinds of Mac and comes with a note on opening it,
    # because macOS blocks apps that Apple has not notarized the first time they are opened.
    swift build -c release --arch arm64 --arch x86_64
    folder=build/package/SnapText
    rm -rf build/package
    mkdir -p "$folder"
    make_app "$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/SnapText" "$folder/SnapText.app"
    cp docs/install-note.txt "$folder/How to open SnapText.txt"

    if [ "$1" = dmg ]; then
        make_dmg "$folder"
        echo "Packaged build/SnapText.dmg"
    else
        rm -f build/SnapText.zip
        ditto -c -k --sequesterRsrc --keepParent "$folder" build/SnapText.zip
        echo "Packaged build/SnapText.zip"
    fi
    ;;
*)
    swift build -c release
    make_app "$(swift build -c release --show-bin-path)/SnapText" build/SnapText.app
    echo "Built build/SnapText.app"

    if [ "${1:-}" = install ]; then
        pkill -x SnapText || true
        rm -rf /Applications/SnapText.app
        ditto build/SnapText.app /Applications/SnapText.app
        open /Applications/SnapText.app
        echo "Installed and opened /Applications/SnapText.app"
    fi
    ;;
esac
