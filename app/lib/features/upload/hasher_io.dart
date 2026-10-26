import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:photolib_workers/blake3.dart';

/// The BLAKE3 of [file], as lowercase hex, read in pieces as the platform
/// gives them; [progress] gets the share read, from 0 to 1, as it grows.
Future<String> hashFile(XFile file, void Function(double done) progress) async {
  final size = await file.length();
  final hash = Blake3();
  var read = 0;
  await for (final chunk in file.openRead()) {
    hash.add(chunk);
    read += chunk.length;
    if (size > 0) progress(read / size);
  }
  progress(1);
  return hash.hex;
}
