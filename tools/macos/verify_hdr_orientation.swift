// Checks on a Mac that an HDR photo with an EXIF orientation decodes upright and stays HDR (ADR-0394): the one command
//
//   swift tools/macos/verify_hdr_orientation.swift
//
// copies testdata/corpus/files/hdr/ultra-hdr.jpg (4032x3024) with exiftool -n -Orientation=6 (brew install exiftool),
// decodes the copy with the leaf's old call and with decodeUpright, the function app/macos/Runner/HdrLeaf.swift and
// app/ios/Runner/HdrLeaf.swift share, and prints both sizes. Expected output ends with
//
//   old 4032x3024 (sideways)   new 3024x4032 (upright, 10 bit)   PASS
//
// and exits 0; anything else exits 1. A different photo: pass its path (a landscape file, rotated the same way).
import Foundation
import ImageIO

// The same text as decodeUpright in the two HdrLeaf.swift files.
func decodeUpright(_ source: CGImageSource, _ options: [CFString: Any]) -> CGImage? {
  var options = options
  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
  let orientation = properties?[kCGImagePropertyOrientation] as? UInt32 ?? 1
  guard orientation != 1, let width = properties?[kCGImagePropertyPixelWidth] as? Int,
    let height = properties?[kCGImagePropertyPixelHeight] as? Int
  else { return CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary) }
  options[kCGImageSourceCreateThumbnailFromImageAlways] = true
  options[kCGImageSourceCreateThumbnailWithTransform] = true
  options[kCGImageSourceThumbnailMaxPixelSize] = max(width, height)
  return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
}

func fail(_ message: String) -> Never {
  FileHandle.standardError.write(Data("verify_hdr_orientation: \(message)\n".utf8))
  exit(1)
}

let here = URL(fileURLWithPath: #filePath)
let sample = CommandLine.arguments.count > 1
  ? URL(fileURLWithPath: CommandLine.arguments[1])
  : here.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("testdata/corpus/files/hdr/ultra-hdr.jpg")
let rotated = FileManager.default.temporaryDirectory.appendingPathComponent("photolib-rotated-\(getpid()).jpg")
defer { try? FileManager.default.removeItem(at: rotated) }

let exiftool = Process()
exiftool.executableURL = URL(fileURLWithPath: "/usr/bin/env")
exiftool.arguments = ["exiftool", "-q", "-n", "-Orientation=6", "-o", rotated.path, sample.path]
do { try exiftool.run() } catch { fail("exiftool did not start: \(error); brew install exiftool") }
exiftool.waitUntilExit()
guard exiftool.terminationStatus == 0 else { fail("exiftool failed on \(sample.path); brew install exiftool") }

guard let source = CGImageSourceCreateWithURL(rotated as CFURL, nil) else { fail("cannot read \(rotated.path)") }
var options: [CFString: Any] = [kCGImageSourceShouldCacheImmediately: true]
if #available(macOS 14, *) { options[kCGImageSourceDecodeRequest] = kCGImageSourceDecodeToHDR }
guard let old = CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary),
  let new = decodeUpright(source, options)
else { fail("ImageIO decoded nothing") }

let passed = old.width > old.height && new.height > new.width && old.width == new.height && old.height == new.width
let sizes = "old \(old.width)x\(old.height) (sideways)   new \(new.width)x\(new.height)"
print(sizes, "(upright, \(new.bitsPerComponent) bit)", passed ? "  PASS" : "  FAIL")
exit(passed ? 0 : 1)
