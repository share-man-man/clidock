#!/bin/bash
# Build the daily-use configuration, install it alongside Release, and launch it.
set -euo pipefail
cd "$(dirname "$0")/.."

derived="$PWD/build/DerivedData"
configuration=Local
xcodegen generate
xcodebuild -project Clidock.xcodeproj -scheme Clidock -configuration "$configuration" \
    -destination 'platform=macOS' -derivedDataPath "$derived" build

app_name=ClidockLocal
built="$derived/Build/Products/$configuration/$app_name.app"
installed="/Applications/$app_name.app"

# Stage on the destination volume and verify the copy before touching a running app.
stage=$(mktemp -d "/Applications/.$app_name.XXXXXX")
trap 'rm -rf "$stage"' EXIT
ditto "$built" "$stage/$app_name.app"
codesign --verify --deep --strict "$stage/$app_name.app"

xcrun swift - "$stage/$app_name.app" "$installed" <<'SWIFT'
import AppKit

// The verified copy and its destination are on the same volume.
let staged = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
// Resolve only instances launched from the requested installation path.
let destination = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
for app in NSWorkspace.shared.runningApplications where app.bundleURL?.standardizedFileURL == destination.standardizedFileURL {
    // A normal quit gives SwiftData time to save before replacement.
    app.terminate()
    // NSRunningApplication updates its state on the main run loop.
    let deadline = Date(timeIntervalSinceNow: 10)
    while !app.isTerminated && Date() < deadline {
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
    }
    guard app.isTerminated else {
        FileHandle.standardError.write(Data("Quit \(destination.lastPathComponent) and rerun the installer.\n".utf8))
        exit(1)
    }
}

// Replace the whole bundle atomically so an interrupted update cannot leave mixed files.
let files = FileManager.default
if files.fileExists(atPath: destination.path) {
    _ = try files.replaceItemAt(destination, withItemAt: staged, options: .usingNewMetadataOnly)
} else {
    try files.moveItem(at: staged, to: destination)
}
SWIFT
# Refresh LaunchServices metadata so Finder and IconServices pick up updated bundle icons.
touch "$installed"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$installed" >/dev/null 2>&1 || true
open "$installed"
echo "Installed $installed"
