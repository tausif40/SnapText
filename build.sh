#!/bin/bash
# Builds CopyText.app into ./build.
#
#   ./build.sh            build the app
#   ./build.sh install    build, copy to /Applications and open it
#   ./build.sh package    build for Apple silicon and Intel, and zip it for sharing
#   ./build.sh test       run the tests
#
# Screen Recording permission is tied to the app's signature. The default ad hoc signature changes with
# every build, so the permission must be granted again after rebuilding. To keep it across builds, sign
# with a certificate from your keychain: SIGN_IDENTITY="Apple Development" ./build.sh

set -euo pipefail
cd "$(dirname "$0")"

# Xcode refuses to run until its license is accepted; the standalone Command Line Tools have no such step.
if ! xcrun --find swift >/dev/null 2>&1 && [ -d /Library/Developer/CommandLineTools ]; then
    export DEVELOPER_DIR=/Library/Developer/CommandLineTools
fi

# Assembles and signs an app bundle at $2 around the executable at $1.
make_app() {
    rm -rf "$2"
    mkdir -p "$2/Contents/MacOS" "$2/Contents/Resources"
    cp "$1" "$2/Contents/MacOS/CopyText"
    cp Resources/Info.plist "$2/Contents/Info.plist"
    cp Resources/AppIcon.icns "$2/Contents/Resources/AppIcon.icns"
    codesign --force --sign "${SIGN_IDENTITY:--}" "$2"
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
package)
    # A copy to hand to other people: it runs on both kinds of Mac and comes with a note on opening it,
    # because macOS blocks apps that Apple has not notarized the first time they are opened.
    swift build -c release --arch arm64 --arch x86_64
    folder=build/package/CopyText
    rm -rf build/package build/CopyText.zip
    mkdir -p "$folder"
    make_app "$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/CopyText" "$folder/CopyText.app"
    cp docs/install-note.txt "$folder/How to open CopyText.txt"
    ditto -c -k --sequesterRsrc --keepParent "$folder" build/CopyText.zip
    echo "Packaged build/CopyText.zip"
    ;;
*)
    swift build -c release
    make_app "$(swift build -c release --show-bin-path)/CopyText" build/CopyText.app
    echo "Built build/CopyText.app"

    if [ "${1:-}" = install ]; then
        pkill -x CopyText || true
        rm -rf /Applications/CopyText.app
        ditto build/CopyText.app /Applications/CopyText.app
        open /Applications/CopyText.app
        echo "Installed and opened /Applications/CopyText.app"
    fi
    ;;
esac
