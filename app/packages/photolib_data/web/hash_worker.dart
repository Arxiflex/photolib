import 'package:photolib_data/src/hash_url.dart';
import 'package:photolib_workers/worker.dart';

/// The Web Worker that hashes the file at a `blob:` URL with BLAKE3 for an
/// upload (hash_url.dart); tools/data/web.sh compiles it to hash_worker.js.
void main() => serveWorker(const [hashInWorker]);
