import 'package:photolib_kernel/photolib_kernel.dart';
import 'package:photolib_kernel/testing.dart';

/// The kernel built from this checkout's kernel/ffi, as photolib_kernel's own tests build it: call it in `main`.
Kernel testKernel() => Kernel.open(buildKernel());
