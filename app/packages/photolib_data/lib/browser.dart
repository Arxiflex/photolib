/// What only browsers have of the library: the files of the folders they keep
/// (ADR-0082) the poster frames their players show (ADR-0116) and the hashing
/// of what is picked for upload on a worker (M2-25).
library;

export 'src/browser_folders.dart' show browserFile;
export 'src/browser_posters.dart';
export 'src/hash_url.dart' show hashOnWorker, hashUrl;
