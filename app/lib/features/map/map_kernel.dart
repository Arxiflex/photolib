import 'package:photolib_data/photolib_data.dart' show AsyncKernelCall;

/// A kernel of its own for the map's index, which holds up to a million
/// positions and so lives off the UI isolate (or, where there are no
/// isolates, in the page): its `call` runs one kernel function.
class MapKernel {
  /// A kernel whose calls are `call`, freed by `free`.
  const new(this.call, this._free);

  /// Runs a kernel function by method id on an encoded request.
  final AsyncKernelCall call;

  final Future<void> Function() _free;

  /// Frees the kernel and its indexes; the calls after it fail.
  Future<void> close() => _free();
}
