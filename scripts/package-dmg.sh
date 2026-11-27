#!/bin/bash
# Build a universal local DMG, or sign and notarize the exact checked-out release tag.
set -euo pipefail
cd "$(dirname "$0")/.."
mode=${1:---local}
case "$mode" in
    --local) ;;
    --release)
        : "${RELEASE_TAG:?Set the release tag, for example v0.1.0}"
        : "${DEVELOPER_ID:?Set the Developer ID Application identity}"
        : "${NOTARY_PROFILE:?Set the notarytool keychain profile}"
        [[ "$DEVELOPER_ID" == "Developer ID Application: "* ]]
        test "$(git rev-parse HEAD)" = "$(git rev-parse "refs/tags/$RELEASE_TAG^{commit}")"
        test -z "$(git status --porcelain --untracked-files=normal)"
        ;;
    *) echo "Usage: $0 [--local|--release]" >&2; exit 2 ;;
esac

# Build both architectures with the same source and the package version in project.yml.
xcodegen generate
derived="$PWD/build/DerivedData"
xcodebuild -project Clidock.xcodeproj -scheme Clidock -configuration Release \
    -destination 'generic/platform=macOS' -derivedDataPath "$derived" \
    'ARCHS=arm64 x86_64' ONLY_ACTIVE_ARCH=NO build
mkdir -p dist
scratch=$(mktemp -d "$PWD/build/package.XXXXXX")
trap 'rm -rf "$scratch"' EXIT
stage="$scratch/image"
mkdir "$stage"
app="$stage/Clidock.app"
ditto "$derived/Build/Products/Release/Clidock.app" "$app"
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Contents/Info.plist")
lipo "$app/Contents/MacOS/Clidock" -verify_arch arm64 x86_64

# Notarize the app as well as its carrier so the installed app keeps an offline ticket.
if [[ "$mode" == "--release" ]]; then
    [[ "$RELEASE_TAG" == "v$version" ]] || { echo "Tag does not match the app version" >&2; exit 1; }
    codesign --force --timestamp --options runtime --sign "$DEVELOPER_ID" "$app"
    ditto -c -k --keepParent "$app" "$scratch/app.zip"
    xcrun notarytool submit "$scratch/app.zip" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$app"
    xcrun stapler validate "$app"
    spctl --assess --type execute "$app"
    name="Clidock-$version"
else
    name="Clidock-$version-local"
fi
codesign --verify --deep --strict "$app"
ln -s /Applications "$stage/Applications"
dmg="$scratch/$name.dmg"
hdiutil create -volname Clidock -srcfolder "$stage" -format UDZO "$dmg"
if [[ "$mode" == "--release" ]]; then
    codesign --timestamp --sign "$DEVELOPER_ID" "$dmg"
    xcrun notarytool submit "$dmg" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$dmg"
    xcrun stapler validate "$dmg"
    spctl --assess --type open --context context:primary-signature "$dmg"

    # Include the actual linked dependency, license and all build/installation scripts.
    tree="$scratch/$name-source"
    mkdir -p "$tree/Dependencies/KeyboardShortcuts"
    git archive "$RELEASE_TAG" | tar -x -C "$tree"
    git -C "$derived/SourcePackages/checkouts/KeyboardShortcuts" archive HEAD | tar -x -C "$tree/Dependencies/KeyboardShortcuts"
    tar -czf "$scratch/$name-source.tar.gz" -C "$scratch" "$name-source"
fi
hdiutil verify "$dmg"
files=("$name.dmg")
if [[ "$mode" == "--release" ]]; then files+=("$name-source.tar.gz"); fi
(cd "$scratch" && shasum -a 256 "${files[@]}" > "$name.sha256" && shasum -a 256 -c "$name.sha256")
for file in "${files[@]}" "$name.sha256"; do mv "$scratch/$file" dist/; done
