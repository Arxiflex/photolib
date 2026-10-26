// ignore_for_file: unused-code

import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:photolib_data/browser.dart';

/// The BLAKE3 of [file], as lowercase hex, hashed on a Web Worker so that the
/// page keeps drawing (a browser's file is a `blob:` URL); [progress] gets the
/// share read, from 0 to 1, as it grows.
Future<String> hashFile(XFile file, void Function(double done) progress) =>
    hashOnWorker(file.path, progress: progress);
