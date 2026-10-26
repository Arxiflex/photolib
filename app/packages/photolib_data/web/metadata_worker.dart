import 'package:photolib_data/src/extract_web.dart';
import 'package:photolib_workers/worker.dart';

/// The Web Worker that reads the metadata of browser folders' files with the
/// kernel's module (extract_web.dart); tools/data/web.sh compiles it to
/// metadata_worker.js.
void main() => serveWorker(const [readFolderFiles]);
