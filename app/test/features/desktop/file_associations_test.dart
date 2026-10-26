// Open with Photolib: each desktop offers the app for every file type the
// library indexes (docs/10 §8.2), and hands it the files it opens with.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:photolib_data/photolib_data.dart' show mediaExtensions;

const _mime = {
  'jpg': 'image/jpeg', 'jpeg': 'image/jpeg', 'png': 'image/png', //
  'gif': 'image/gif', 'webp': 'image/webp', 'heic': 'image/heic',
  'heif': 'image/heif', 'avif': 'image/avif', 'jxl': 'image/jxl',
  'bmp': 'image/bmp', 'tif': 'image/tiff', 'tiff': 'image/tiff',
  'dng': 'image/x-adobe-dng', 'cr2': 'image/x-canon-cr2',
  'cr3': 'image/x-canon-cr3', 'nef': 'image/x-nikon-nef',
  'arw': 'image/x-sony-arw', 'orf': 'image/x-olympus-orf',
  'rw2': 'image/x-panasonic-rw2', 'raf': 'image/x-fuji-raf',
  'srw': 'image/x-samsung-srw', 'pef': 'image/x-pentax-pef',
  'mp4': 'video/mp4', 'mov': 'video/quicktime', 'm4v': 'video/x-m4v',
  'avi': 'video/x-msvideo', 'mkv': 'video/x-matroska', 'webm': 'video/webm',
  '3gp': 'video/3gpp', 'mts': 'video/mp2t', 'm2ts': 'video/mp2t',
};

void main() {
  test('Linux: the desktop entry opens every media type with the files', () {
    final entry = File('linux/packaging/org.photolib.photolib.desktop')
        .readAsStringSync();
    // URLs, for photolib: links (ADR-0243); openedArg takes file: URLs.
    expect(entry, contains('\nExec=photolib %U\n'));
    final types = RegExp(
      r'^MimeType=(.*);$',
      multiLine: true,
    ).firstMatch(entry)![1]!.split(';');
    for (final extension in mediaExtensions) {
      expect(types, contains(_mime[extension]), reason: extension);
    }
  });

  test('macOS: Finder offers the app for photos and videos, never as their '
      'default (photolib-design#553)', () {
    expect(
      File('macos/Runner/Info.plist').readAsStringSync(),
      allOf(
        contains('<key>CFBundleDocumentTypes</key>'),
        contains('<string>public.image</string>'),
        contains('<string>public.movie</string>'),
        matches(RegExp(r'<key>LSHandlerRank</key>\s*<string>Alternate<')),
        isNot(contains('<string>Owner</string>')),
      ),
    );
  });

  test('Windows: the package associates every media extension', () {
    final manifest = File('windows/packaging/AppxManifest.xml')
        .readAsStringSync();
    expect(manifest, contains('Category="windows.fileTypeAssociation"'));
    for (final extension in mediaExtensions) {
      expect(
        manifest,
        contains('<uap:FileType>.$extension</uap:FileType>'),
        reason: extension,
      );
    }
  });
}
