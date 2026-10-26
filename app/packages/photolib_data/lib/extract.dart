/// Reads files' metadata with the kernel, natively, as the data isolate's
/// extraction does: for files outside the device index too.
library;

export 'src/extract_native.dart' show kernelExtract, readMetadata;
