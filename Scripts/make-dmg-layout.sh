#!/bin/bash
# Records the layout of the disk image window and writes Resources/DMGLayout.DS_Store.
# Run from the project root after changing the layout: Scripts/make-dmg-layout.sh
#
# Only Finder can write a window layout, and on recent versions of macOS it rewrites it with its defaults a few
# seconds after the window closes. So this asks Finder to lay out a scratch disk image, copies the .DS_Store the
# moment it holds the layout, and build.sh puts that copy into every disk image it makes.
#
# Positions are the centers of the icons, from the top left of the window. They must match the background,
# which Scripts/make-dmg-background.swift draws. The first run asks to let Terminal control Finder.

set -euo pipefail
cd "$(dirname "$0")/.."

volume=/Volumes/SnapText
scratch=$(mktemp -d)
trap 'hdiutil detach "$volume" -quiet 2>/dev/null || true; rm -rf "$scratch"' EXIT

# Stand-ins with the same names as the real items: Finder keeps positions by name.
folder="$scratch/SnapText"
mkdir -p "$folder/SnapText.app" "$folder/.background"
ln -s /Applications "$folder/Applications"
touch "$folder/How to open SnapText.txt"
cp Resources/DMGBackground.tiff "$folder/.background/background.tiff"

# Finder tells disks apart by name, so eject any copy of the disk image that is still open.
for mounted in /Volumes/SnapText /Volumes/SnapText\ [0-9]*; do
    if [ -d "$mounted" ]; then hdiutil detach "$mounted" -quiet; fi
done
hdiutil create -volname SnapText -srcfolder "$folder" -fs HFS+ -format UDRW -ov "$scratch/layout.dmg" -quiet
hdiutil attach "$scratch/layout.dmg" -readwrite -noverify -noautoopen -mountpoint "$volume" -quiet

osascript <<'APPLESCRIPT'
tell application "Finder"
    tell disk "SnapText"
        open
        -- Settings made before the window has finished opening are not kept.
        delay 1
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {200, 120, 840, 548}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 80
        set text size of viewOptions to 12
        set background picture of viewOptions to file ".background:background.tiff"
        set position of item "SnapText.app" to {160, 200}
        set position of item "Applications" to {480, 200}
        set position of item "How to open SnapText.txt" to {320, 330}
        update without registering applications
        delay 1
        close
    end tell
end tell
APPLESCRIPT

# Succeeds once the .DS_Store holds a single icon view record, and it is the one asked for above.
has_layout() {
    python3 -I - "$volume/.DS_Store" <<'PYTHON'
import plistlib, sys

data = open(sys.argv[1], "rb").read()
records = []
start = data.find(b"bplist00")
while start >= 0:
    for end in range(start + 40, min(len(data), start + 6000)):
        try:
            plist = plistlib.loads(data[start:end])
        except Exception:
            continue
        if "iconSize" in plist:
            records.append(plist)
        break
    start = data.find(b"bplist00", start + 8)
sys.exit(0 if [(r["iconSize"], r["backgroundType"], r["arrangeBy"]) for r in records] == [(80, 2, "none")] else 1)
PYTHON
}

for _ in $(seq 50); do
    if [ -f "$volume/.DS_Store" ] && has_layout; then
        cp "$volume/.DS_Store" Resources/DMGLayout.DS_Store
        echo "Wrote Resources/DMGLayout.DS_Store"
        exit 0
    fi
    sleep 0.2
done
echo "Finder did not save the layout. Run the script again." >&2
exit 1
