#!/usr/bin/env bash
# An HDR photo shows upright (ADR-0394): the native leaf decodes with CGImageSourceCreateImageAtIndex, which ignores
# the EXIF orientation, so a photo with an orientation other than 1 goes through the thumbnail path with the transform
# flag at its full size (DecodeToHDR kept), and an upright one keeps the plain decode. Swift cannot run here, so this
# reads both leaves as text: the deciding function is the same in the macOS and the iOS copy.
# tools/macos/verify_hdr_orientation.swift measures the real thing on a Mac.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$REPO_ROOT" || exit 1

MAC=app/macos/Runner/HdrLeaf.swift IOS=app/ios/Runner/HdrLeaf.swift

# upright <file>: the text of decodeUpright, from its declaration to the closing brace at the left margin.
upright() { sed -n '/^private func decodeUpright(/,/^}/p' "$1"; }

[[ -n $(upright "$MAC") ]] && ok "$MAC defines decodeUpright" || fail "$MAC defines no decodeUpright"
if [[ -n $(upright "$MAC") && $(upright "$MAC") == "$(upright "$IOS")" ]]; then
  ok "decodeUpright is the same in the macOS and the iOS leaf"
else
  fail "decodeUpright differs between $MAC and $IOS"
fi

# has <text> <regex> <description>
has() {
  if grep -Eq -- "$2" <<<"$1"; then ok "$3"; else fail "$3 (no match for /$2/)"; fi
}

for leaf in "$MAC" "$IOS"; do
  body=$(upright "$leaf")
  has "$body" 'CGImageSourceCopyPropertiesAtIndex\(source, 0, nil\)' "$leaf reads the properties"
  has "$body" 'kCGImagePropertyOrientation\] as\? UInt32 \?\? 1' "$leaf: no orientation means upright"
  has "$body" 'guard orientation != 1, let width' "$leaf: an upright photo keeps the plain decode"
  has "$body" 'else \{ return CGImageSourceCreateImageAtIndex\(source, 0, options as CFDictionary\) \}' \
    "$leaf: the plain decode is the fallback, as before"
  has "$body" 'kCGImageSourceCreateThumbnailFromImageAlways\] = true' "$leaf asks for a thumbnail even with an embedded one"
  has "$body" 'kCGImageSourceCreateThumbnailWithTransform\] = true' "$leaf applies the orientation"
  has "$body" 'kCGImageSourceThumbnailMaxPixelSize\] = max\(width, height\)' "$leaf keeps the full size"
  has "$body" 'return CGImageSourceCreateThumbnailAtIndex\(source, 0, options as CFDictionary\)' \
    "$leaf decodes the transformed image"
  assert_matches "$leaf" 'kCGImageSourceDecodeRequest\] = kCGImageSourceDecodeToHDR' "$leaf still decodes to HDR"
  assert_matches "$leaf" 'decodeUpright\(source, options\)' "$leaf decodes through decodeUpright"
  others=$(sed '/^private func decodeUpright(/,/^}/d' "$leaf" | grep -c 'CGImageSourceCreateImageAtIndex')
  [[ $others -eq 0 ]] && ok "$leaf has no other CGImageSourceCreateImageAtIndex call" ||
    fail "$leaf decodes some other way than through decodeUpright"
done
assert_file tools/macos/verify_hdr_orientation.swift
assert_matches tools/macos/verify_hdr_orientation.swift '4032x3024' "the Mac check names the sideways size"
assert_matches tools/macos/verify_hdr_orientation.swift '3024x4032' "the Mac check names the upright size"

finish
